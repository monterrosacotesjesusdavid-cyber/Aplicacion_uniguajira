import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/liveness_screen.dart';
import '../../core/foto_salon_screen.dart';
import '../../core/offline.dart';
import '../../core/offline_widgets.dart';
import '../../core/gps_helper.dart';
import '../auth/login_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'estudiantes_clase_screen.dart';

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
        title: Row(children: [
          Container(width: 32, height: 32,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Image.asset('assets/escudo.png', fit: BoxFit.contain)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('UniGuajira', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            Text('Portal Docente',
              style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.75),
                fontWeight: FontWeight.w400)),
          ]),
        ]),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 4),
            child: Center(child: Text(_nombre,
              style: const TextStyle(color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.w600)))),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20, color: Colors.white70),
            onPressed: _logout),
        ],
      ),
      body: screens[_idx],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.borde))),
        child: BottomNavigationBar(
          currentIndex: _idx,
          onTap: (i) => setState(() => _idx = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.today_rounded), label: 'Hoy'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_month_rounded), label: 'Horario'),
          ],
        ),
      ),
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

  @override
  void initState() { super.initState(); _initGps(); _load(); }

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

  /// Habilita o cierra la firma de los estudiantes de esta clase.
  Future<void> _sesion(Map clase, bool abrir) async {
    try {
      final r = await Api.sesionClase(clase['id'], abrir);
      if (!mounted) return;
      if (r['_status'] == 200) {
        _snack(abrir ? '✓ Los estudiantes ya pueden firmar' : 'Asistencia de estudiantes cerrada');
        _load();
      } else {
        _snack(r['error'] ?? 'No se pudo actualizar', error: true);
      }
    } catch (_) {
      if (mounted) _snack('Sin conexión: habilitar a los estudiantes requiere internet', error: true);
    }
  }

  Future<void> _firmar(Map clase) async {
    if (_pos == null) {
      _snack(GpsHelper.mensajeError, error: true);
      return;
    }
    // Verificación facial con prueba de vida
    final foto = await LivenessScreen.abrir(context, titulo: 'Verifica tu identidad');
    if (foto == null || !mounted) return;
    // Sin internet: no se llama al servidor, se guarda la evidencia en el celular.
    if (clase['offline'] == true) { await _guardarOffline(clase, foto); return; }

    // Foto a los estudiantes en el salón (cámara trasera): prueba de presencia
    final fotoSalon = await FotoSalonScreen.abrir(context);
    if (fotoSalon == null || !mounted) return;

    final idx = _clases.indexOf(clase);
    setState(() => _clases[idx] = {...Map.from(clase), '_firmando': true});

    try {
      final r = await Api.firmarAsistenciaProfesor(
        horarioId: clase['id'],
        lat: _pos!.latitude,
        lon: _pos!.longitude,
        fotoBase64: foto,
        fotoSalonBase64: fotoSalon,
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
    final hoy = DateFormat("EEEE d 'de' MMMM", 'es_CO').format(DateTime.now());
    return RefreshIndicator(
      onRefresh: () async { await _initGps(); await _load(); },
      color: C.verdeClaro, backgroundColor: C.sup,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // GPS
          _GpsBanner(loading: _gpsLoading, pos: _pos),
          const SizedBox(height: 12),
          OfflineBanner(onCambio: _load),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text('Clases de hoy',
              style: const TextStyle(color: C.tinta, fontSize: 19,
                fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: C.verde, borderRadius: BorderRadius.circular(6)),
              child: Text(hoy, style: const TextStyle(color: Colors.white, fontSize: 10,
                fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 14),

          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: C.verde)))
          else if (_clases.isEmpty)
            _Vacio()
          else
            ..._clases.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ClaseProfCard(
                clase: c, gpsOk: _pos != null,
                onFirmar: () => _firmar(c),
                onSesion: (abrir) => _sesion(c, abrir),
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

class _GpsBanner extends StatelessWidget {
  final bool loading; final Position? pos;
  const _GpsBanner({required this.loading, required this.pos});
  @override
  Widget build(BuildContext context) {
    final ok = pos != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (loading ? Colors.orange : ok ? C.verde : C.rojo).withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (loading ? Colors.orange : ok ? C.verde : C.rojo).withOpacity(0.3))),
      child: Row(children: [
        Icon(loading ? Icons.gps_not_fixed : ok ? Icons.gps_fixed : Icons.gps_off,
          color: loading ? Colors.orange : ok ? C.verdeClaro : C.rojo, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(
          loading ? 'Obteniendo ubicación...'
            : ok ? 'GPS activo — precisión ±${pos!.accuracy.toStringAsFixed(0)}m'
            : 'GPS no disponible — actívalo para firmar',
          style: TextStyle(
            color: loading ? Colors.orange : ok ? C.verdeClaro : C.rojo,
            fontSize: 12, fontWeight: FontWeight.w500))),
        if (loading) const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)),
      ]),
    );
  }
}

class _ClaseProfCard extends StatelessWidget {
  final dynamic clase; final bool gpsOk; final VoidCallback onFirmar;
  final void Function(bool abrir) onSesion;
  final VoidCallback onVer;
  const _ClaseProfCard({required this.clase, required this.gpsOk,
    required this.onFirmar, required this.onSesion, required this.onVer});

  @override
  Widget build(BuildContext context) {
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

    return Card(child: Column(children: [
      InkWell(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        onTap: onVer,
        child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: C.verde,
            borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Text(clase['hora_inicio']?.substring(0, 5) ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 15,
                fontWeight: FontWeight.w700)),
            Text(clase['hora_fin']?.substring(0, 5) ?? '',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(clase['materia'] ?? '',
            style: const TextStyle(color: C.tinta, fontSize: 14,
              fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(clase['salon'] ?? '',
            style: TextStyle(color: C.tinta.withOpacity(0.45), fontSize: 12)),
          if (clase['bloque'] != null)
            Text(clase['bloque'],
              style: TextStyle(color: C.tinta.withOpacity(0.3), fontSize: 11)),
        ])),
        const Icon(Icons.chevron_right_rounded, color: C.suave),
      ]))),

      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: pend
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: C.dorado.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: C.dorado.withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.schedule_send_rounded, color: C.doradoClaro, size: 18),
                SizedBox(width: 10),
                Expanded(child: Text(
                  'Evidencia guardada — pendiente de envío y aprobación',
                  style: TextStyle(color: C.doradoClaro, fontSize: 12,
                    fontWeight: FontWeight.w600))),
              ]))
        : yaReg
          ? Column(children: [Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: C.verde.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: C.verde.withOpacity(0.2))),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, color: C.verdeClaro, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Asistencia registrada — ${clase['asistencia_estado'] == 'a_tiempo' ? 'A tiempo' : 'Tardanza'}  •  ${clase['hora_registro']?.toString().substring(11, 16) ?? ''}',
                  style: const TextStyle(color: C.verdeClaro, fontSize: 12,
                    fontWeight: FontWeight.w600))),
              ])),
              const SizedBox(height: 10),
              if (sesion) ...[
                Row(children: [
                  const Icon(Icons.groups_rounded, color: C.verdeClaro, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Estudiantes habilitados — firmaron $firmaron de $total',
                    style: const TextStyle(color: C.tinta70, fontSize: 12))),
                ]),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => onSesion(false),
                  icon: const Icon(Icons.lock_outline_rounded, size: 18),
                  label: const Text('Cerrar asistencia de estudiantes'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: C.tinta,
                    side: const BorderSide(color: C.borde),
                    minimumSize: const Size(double.infinity, 42))),
              ] else
                ElevatedButton.icon(
                  onPressed: () => onSesion(true),
                  icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                  label: const Text('Habilitar asistencia a estudiantes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: C.azul, minimumSize: const Size(double.infinity, 44))),
            ])
          : ElevatedButton.icon(
              onPressed: (disponible && gpsOk && !firmando) ? onFirmar : null,
              icon: firmando
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.camera_alt_rounded, size: 18),
              label: Text(firmando ? 'Registrando...'
                : disponible
                  ? (clase['offline'] == true ? 'Tomar evidencia (sin conexión)'
                      : tardanza ? '⚠ Registrar (Tardanza)' : 'Registrar con foto')
                  : (expirado ? 'Tiempo expirado' : msg)),
              style: ElevatedButton.styleFrom(
                backgroundColor: tardanza ? C.naranja : C.verde,
                disabledBackgroundColor: C.borde),
            ),
      ),
    ]));
  }
}

class _Vacio extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
    child: Column(children: [
      Icon(Icons.event_available_rounded, size: 48, color: C.suave),
      const SizedBox(height: 14),
      const Text('Sin clases hoy', style: TextStyle(color: C.tinta, fontSize: 17,
        fontWeight: FontWeight.w600)),
    ]),
  ));
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
  final _dias = ['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await Api.horarioSemanaProfesor();
      setState(() { _horario = list; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load, color: C.verdeClaro, backgroundColor: C.sup,
    child: _loading
      ? const Center(child: CircularProgressIndicator(color: C.verde))
      : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Mi Horario Semanal', style: TextStyle(color: C.tinta,
              fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            ..._dias.map((dia) {
              final clases = _horario.where((c) => c['dia_semana'] == dia).toList();
              if (clases.isEmpty) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 10, bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: C.verde.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: C.verde.withOpacity(0.3))),
                    child: Text(dia, style: const TextStyle(color: C.verdeClaro,
                      fontSize: 12, fontWeight: FontWeight.w700)))),
                ...clases.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => EstudiantesClaseScreen(
                        horarioId: c['id'], materia: (c['materia'] ?? '').toString()))),
                    child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: C.verde.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8)),
                        child: Column(children: [
                          Text(c['hora_inicio']?.substring(0, 5) ?? '',
                            style: const TextStyle(color: C.verdeClaro, fontSize: 13,
                              fontWeight: FontWeight.w700)),
                          Text(c['hora_fin']?.substring(0, 5) ?? '',
                            style: TextStyle(color: C.tinta.withOpacity(0.4),
                              fontSize: 10)),
                        ])),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c['materia'] ?? '', style: const TextStyle(
                          color: C.tinta, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(c['salon'] ?? '', style: TextStyle(
                          color: C.tinta.withOpacity(0.45), fontSize: 12)),
                      ])),
                      const Icon(Icons.chevron_right_rounded, color: C.suave),
                    ])))))),
              ]);
            }),
          ]),
  );
}
