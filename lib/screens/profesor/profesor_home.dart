import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/liveness_screen.dart';
import '../../core/foto_salon_screen.dart';
import '../../core/offline.dart';
import '../../core/offline_widgets.dart';
import '../../core/gps_helper.dart';
import '../../core/ui_kit.dart';
import '../auth/login_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'estudiantes_clase_screen.dart';
import 'lista_virtual_screen.dart';

class ProfesorHome extends StatefulWidget {
  const ProfesorHome({super.key});
  @override
  State<ProfesorHome> createState() => _ProfHomeState();
}

class _ProfHomeState extends State<ProfesorHome> {
  int _idx = 0;
  String _nombre = '';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance()
        .then((p) => setState(() => _nombre = p.getString('nombre') ?? ''));
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión', style: TextStyle(color: C.tinta)),
        content: const Text('¿Deseas salir?', style: TextStyle(color: C.suave)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: C.suave))),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir', style: TextStyle(color: C.rojo))),
        ],
      ),
    );
    if (ok == true) {
      await Api.logout();
      if (mounted) Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [const ClasesProfScreen(), const HorarioSemanaScreen()];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: const MarcaAppBar(sub: 'Portal Docente'),
        actions: [MenuUsuario(nombre: _nombre, onSalir: _logout)],
      ),
      body: screens[_idx],
      bottomNavigationBar: BarraInferior(
        indice: _idx, onTap: (i) => setState(() => _idx = i)),
    );
  }
}

// ── CLASES DE HOY ─────────────────────────────────────────────────────
class ClasesProfScreen extends StatefulWidget {
  const ClasesProfScreen({super.key});
  @override
  State<ClasesProfScreen> createState() => _ClasesProfState();
}

class _ClasesProfState extends State<ClasesProfScreen> {
  List _clases = [];
  bool _loading = true;
  Position? _pos;
  bool _gpsLoading = true;

  bool get _soloVirtual =>
      _clases.isNotEmpty && _clases.every((c) => c['modalidad'] == 'virtual');

  @override
  void initState() {
    super.initState();
    // Las clases virtuales no usan GPS: solo se pide ubicación si hay alguna presencial.
    _load().then((_) {
      if (!_soloVirtual) {
        _initGps();
      } else if (mounted) {
        setState(() => _gpsLoading = false);
      }
    });
  }

  Future<void> _initGps() async {
    final p = await GpsHelper.obtenerPosicion();
    if (mounted) setState(() { _pos = p; _gpsLoading = false; });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await Api.misClasesProfesor();
      if (mounted) setState(() { _clases = list; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _guardarOffline(Map clase, String foto) async {
    await OfflineQueue.agregar(
      horarioId: clase['id'], materia: (clase['materia'] ?? '').toString(),
      lat: _pos?.latitude, lon: _pos?.longitude, fotoBase64: foto);
    if (!mounted) return;
    _snack('Evidencia guardada. Se enviará cuando haya internet.');
    _load();
  }

  /// Habilita la firma de los estudiantes. Primero se toma la foto del salón con la
  /// cámara trasera; si no se toma la foto, no se habilita.
  Future<void> _habilitar(Map clase) async {
    final foto = await FotoSalonScreen.abrir(context);
    if (foto == null || !mounted) return;
    try {
      final r = await Api.sesionClase(clase['id'], true, fotoSalonBase64: foto);
      if (!mounted) return;
      if (r['_status'] == 200) {
        _snack('✓ Los estudiantes ya pueden firmar');
        _load();
      } else {
        _snack(r['error'] ?? 'No se pudo habilitar', error: true);
      }
    } catch (_) {
      if (mounted) _snack('Sin conexión: habilitar a los estudiantes requiere internet', error: true);
    }
  }

  Future<void> _firmar(Map clase) async {
    final virtual = clase['modalidad'] == 'virtual';
    if (!virtual && _pos == null) {
      _snack(GpsHelper.mensajeError, error: true);
      return;
    }
    if (virtual && clase['offline'] == true) {
      _snack('Las clases virtuales requieren internet para registrarse', error: true);
      return;
    }
    // Verificación facial con prueba de vida
    final foto = await LivenessScreen.abrir(context, titulo: 'Verifica tu identidad');
    if (foto == null || !mounted) return;
    // Sin internet: no se llama al servidor, se guarda la evidencia en el celular.
    if (clase['offline'] == true) { await _guardarOffline(clase, foto); return; }

    final idx = _clases.indexOf(clase);
    setState(() => _clases[idx] = {...Map.from(clase), '_firmando': true});

    try {
      final r = await Api.firmarAsistenciaProfesor(
        horarioId: clase['id'],
        lat: virtual ? null : _pos?.latitude,
        lon: virtual ? null : _pos?.longitude,
        fotoBase64: foto,
      );
      if (!mounted) return;
      if (r['_status'] == 200 || r['success'] == true) {
        final estado = r['estado'] == 'tardanza' ? 'Tardanza' : '✓ A tiempo';
        _snack('Asistencia registrada — $estado');
        _load();
      } else {
        _snack(r['error'] ?? 'No se pudo registrar', error: true);
        setState(() => _clases[idx] = Map.from(clase));
      }
    } catch (e) {
      if (!mounted) return;
      if (Net.esErrorDeRed(e)) {
        // Se cayó el internet justo al registrar: se conserva la foto ya tomada.
        Net.offline.value = true;
        await _guardarOffline(clase, foto);
      } else {
        _snack('Error de conexión', error: true);
        if (idx >= 0) setState(() => _clases[idx] = Map.from(clase));
      }
    }
  }

  void _snack(String msg, {bool error = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: error ? C.rojo : C.verde));

  @override
  Widget build(BuildContext context) {
    final n = _clases.length;
    final resumen = (_loading || n == 0) ? ''
        : n == 1 ? 'Tienes 1 clase hoy' : 'Tienes $n clases hoy';
    final sinClases = !_loading && n == 0;

    return RefreshIndicator(
      onRefresh: () async { await _load(); if (!_soloVirtual) await _initGps(); },
      color: C.verdeClaro, backgroundColor: C.sup,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          CabeceraHoy(
            resumen: resumen,
            // El GPS no aplica solo si todas las clases de hoy son virtuales.
            extra: _soloVirtual ? null : GpsChip(
              cargando: _gpsLoading, ok: _pos != null,
              textoOk: _pos == null ? ''
                  : 'GPS activo (±${_pos!.accuracy.toStringAsFixed(0)} m)'),
          ),
          OfflineBanner(onCambio: _load),
          const SizedBox(height: 4),

          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: C.verde)))
          else if (sinClases)
            EstadoVacio(
              titulo: 'Hoy no tienes clases',
              mensaje: 'Disfruta el día libre.',
              extra: ProximaClase(cargar: Api.horarioSemanaProfesor))
          else
            ..._clases.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ClaseProfCard(
                clase: c, gpsOk: _pos != null,
                onFirmar: () => _firmar(c),
                onHabilitar: () => _habilitar(c),
                onLista: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ListaVirtualScreen(
                    horarioId: c['id'], materia: (c['materia'] ?? '').toString())))
                  .then((_) => _load()),
                onVer: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => EstudiantesClaseScreen(
                    horarioId: c['id'], materia: (c['materia'] ?? '').toString()))),
              ),
            )),
        ],
      ),
    );
  }
}

class _ClaseProfCard extends StatelessWidget {
  final dynamic clase; final bool gpsOk; final VoidCallback onFirmar;
  final VoidCallback onHabilitar;
  final VoidCallback onLista;
  final VoidCallback onVer;
  const _ClaseProfCard({required this.clase, required this.gpsOk,
    required this.onFirmar, required this.onHabilitar, required this.onLista,
    required this.onVer});

  @override
  Widget build(BuildContext context) {
    final virtual  = clase['modalidad'] == 'virtual';
    final yaReg    = clase['asistencia_estado'] != null;
    final disponible = clase['disponible'] == true;
    final firmando = clase['_firmando'] == true;
    final msg      = (clase['mensaje'] ?? '') as String;
    final tardanza = msg.contains('Tardanza');
    final expirado = msg.contains('expirado') || msg.contains('Ausente');
    final pend     = clase['pendiente_offline'] == true;
    final sesion   = clase['sesion_abierta'] == true;
    final firmaron = clase['estudiantes_firmaron'] ?? 0;
    final total    = clase['estudiantes_total'] ?? 0;

    // El color de la barra lateral resume el estado de la clase.
    final acento = yaReg ? C.verde
        : pend ? C.dorado
        : disponible ? (tardanza ? C.naranja : C.verde)
        : C.suave.withOpacity(0.35);

    final hora = clase['hora_registro']?.toString();
    final horaTxt = (hora != null && hora.length >= 16) ? hora.substring(11, 16) : '';

    return Tarjeta(child: Column(children: [
      InkWell(
        onTap: onVer,
        child: ClaseResumen(
          inicio: hm(clase['hora_inicio']), fin: hm(clase['hora_fin']),
          materia: (clase['materia'] ?? '').toString(),
          lugar: lugarDe(clase), virtual: virtual, acento: acento,
          trailing: const Icon(Icons.chevron_right_rounded, color: C.suave)),
      ),

      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: pend
          ? const AvisoEstado(
              icono: Icons.schedule_send_rounded, color: C.doradoClaro,
              texto: 'Evidencia guardada, pendiente de envío y aprobación')
        : yaReg
          ? Column(children: [
              AvisoEstado(
                icono: Icons.check_circle_rounded, color: C.verdeClaro,
                texto: horaTxt.isEmpty
                  ? 'Asistencia registrada (${clase['asistencia_estado'] == 'a_tiempo' ? 'a tiempo' : 'con tardanza'})'
                  : 'Asistencia registrada a las $horaTxt (${clase['asistencia_estado'] == 'a_tiempo' ? 'a tiempo' : 'con tardanza'})'),
              const SizedBox(height: 12),
              if (virtual) ...[
                Row(children: [
                  const Icon(Icons.groups_rounded, color: C.verdeClaro, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Presentes: $firmaron de $total',
                    style: const TextStyle(color: C.tinta70, fontSize: 13))),
                ]),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: onLista,
                  icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                  label: const Text('Pasar lista'),
                  style: estiloBoton(fondo: C.azul)),
              ] else if (sesion) ...[
                Row(children: [
                  const Icon(Icons.groups_rounded, color: C.verdeClaro, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Estudiantes habilitados: firmaron $firmaron de $total',
                    style: const TextStyle(color: C.tinta70, fontSize: 13))),
                ]),
              ] else
                ElevatedButton.icon(
                  onPressed: onHabilitar,
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: const Text('Tomar asistencia a estudiantes'),
                  style: estiloBoton(fondo: C.azul)),
            ])
          : ElevatedButton.icon(
              onPressed: (disponible && (gpsOk || virtual) && !firmando) ? onFirmar : null,
              icon: firmando
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.camera_alt_rounded, size: 18),
              label: Text(firmando ? 'Registrando...'
                : disponible
                  ? (clase['offline'] == true ? 'Tomar evidencia (sin conexión)'
                      : tardanza ? 'Registrar con tardanza'
                      : (virtual ? 'Registrar (clase virtual)' : 'Registrar con foto'))
                  : (expirado ? 'Tiempo expirado' : msg)),
              style: estiloBoton(fondo: tardanza ? C.naranja : C.verde),
            ),
      ),
    ]));
  }
}

// ── HORARIO SEMANAL ───────────────────────────────────────────────────
class HorarioSemanaScreen extends StatefulWidget {
  const HorarioSemanaScreen({super.key});
  @override
  State<HorarioSemanaScreen> createState() => _HorSemState();
}

class _HorSemState extends State<HorarioSemanaScreen> {
  List _horario = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await Api.horarioSemanaProfesor();
      if (mounted) setState(() { _horario = list; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load, color: C.verdeClaro, backgroundColor: C.sup,
    child: _loading
      ? const Center(child: CircularProgressIndicator(color: C.verde))
      : ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            const TituloPantalla(
              titulo: 'Mi horario',
              sub: 'Toca una clase para ver a tus estudiantes'),
            if (_horario.isEmpty)
              const EstadoVacio(
                titulo: 'Sin clases asignadas',
                mensaje: 'Cuando tengas clases en tu horario aparecerán aquí.')
            else
              ...List.generate(7, (i) => i + 1).map((n) {
                final clases = _horario.where((c) => c['dia_num'] == n).toList();
                if (clases.isEmpty) return const SizedBox.shrink();
                final esHoy = n == DateTime.now().weekday;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  EncabezadoDia(dia: kDias[n], esHoy: esHoy),
                  ...clases.map((c) => TarjetaHorario(
                    inicio: hm(c['hora_inicio']), fin: hm(c['hora_fin']),
                    materia: (c['materia'] ?? '').toString(),
                    lugar: lugarDe(c),
                    virtual: c['modalidad'] == 'virtual',
                    esHoy: esHoy,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => EstudiantesClaseScreen(
                        horarioId: c['id'], materia: (c['materia'] ?? '').toString()))),
                  )),
                ]);
              }),
          ]),
  );
}
