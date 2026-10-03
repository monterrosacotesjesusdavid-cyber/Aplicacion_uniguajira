import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/liveness_screen.dart';
import '../../core/offline.dart';
import '../../core/offline_widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/gps_helper.dart';
import '../../core/ui_kit.dart';
import 'asistencias_clase_screen.dart';

class ClasesEstudianteScreen extends StatefulWidget {
  const ClasesEstudianteScreen({super.key});
  @override
  State<ClasesEstudianteScreen> createState() => _ClasesEstState();
}

class _ClasesEstState extends State<ClasesEstudianteScreen> {
  List _clases = [];
  bool _loading = true;
  Position? _pos;
  bool _gpsLoading = true;

  Timer? _poll;

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
    // Si el profesor aún no habilitó la asistencia, revisa cada 15 s sin molestar.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_clases.any((c) => c['esperando_profesor'] == true)) _load(silencioso: true);
    });
  }

  @override
  void dispose() { _poll?.cancel(); super.dispose(); }

  Future<void> _initGps() async {
    final p = await GpsHelper.obtenerPosicion();
    if (mounted) setState(() { _pos = p; _gpsLoading = false; });
  }

  Future<void> _load({bool silencioso = false}) async {
    if (!silencioso) setState(() => _loading = true);
    try {
      final list = await Api.misClasesEstudiante();
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

  Future<void> _firmar(Map clase) async {
    if (_pos == null) {
      _snack(GpsHelper.mensajeError, error: true);
      return;
    }
    final foto = await LivenessScreen.abrir(context, titulo: 'Verifica tu identidad');
    if (foto == null || !mounted) return;
    // Sin internet: no se llama al servidor, se guarda la evidencia en el celular.
    if (clase['offline'] == true) { await _guardarOffline(clase, foto); return; }
    final idx = _clases.indexOf(clase);
    setState(() => _clases[idx] = {...Map.from(clase), '_firmando': true});
    try {
      final r = await Api.firmarAsistenciaEstudiante(
        horarioId: clase['id'], lat: _pos!.latitude, lon: _pos!.longitude,
        fotoBase64: foto);
      if (!mounted) return;
      if (r['_status'] == 200 || r['success'] == true) {
        _snack('✓ Asistencia firmada correctamente');
        _load();
      } else {
        _snack(r['error'] ?? 'No se pudo firmar', error: true);
        setState(() => _clases[idx] = Map.from(clase));
      }
    } catch (e) {
      if (!mounted) return;
      if (Net.esErrorDeRed(e)) {
        // Se cayó el internet justo al firmar: se conserva la foto ya tomada.
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
              textoOk: 'GPS activo, listo para firmar'),
          ),
          OfflineBanner(onCambio: _load),
          const SizedBox(height: 4),

          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: C.verde)))
          else if (sinClases)
            EstadoVacio(
              titulo: 'Hoy no tienes clases',
              mensaje: 'No hay clases programadas para hoy.',
              extra: ProximaClase(cargar: Api.horarioSemanaEstudiante))
          else
            ..._clases.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ClaseCard(
                clase: c, gpsOk: _pos != null,
                onVerAsistencias: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) =>
                    AsistenciasClaseScreen(horarioId: c['id'], materia: c['materia']))),
                onFirmar: () => _firmar(c),
              ),
            )),
        ],
      ),
    );
  }
}

// ── CLASE CARD ────────────────────────────────────────────────────────
class _ClaseCard extends StatelessWidget {
  final dynamic clase;
  final bool gpsOk;
  final VoidCallback onVerAsistencias;
  final VoidCallback onFirmar;
  const _ClaseCard({required this.clase, required this.gpsOk,
    required this.onVerAsistencias, required this.onFirmar});

  @override
  Widget build(BuildContext context) {
    final yaFirmo   = clase['ya_firmo'] == true;
    final disponible= clase['disponible'] == true;
    final firmando  = clase['_firmando'] == true;
    final msg       = (clase['mensaje'] ?? '') as String;
    final expirado  = msg.contains('expirado') || msg.contains('Ausente');
    final pend      = clase['pendiente_offline'] == true;
    final esperando = clase['esperando_profesor'] == true;
    final virtual   = clase['modalidad'] == 'virtual';
    final link      = (clase['link_virtual'] ?? '').toString();

    // El color de la barra lateral resume el estado de la clase.
    final acento = yaFirmo ? C.verde
        : pend || esperando ? C.dorado
        : disponible ? C.azul
        : expirado ? C.rojo
        : C.suave.withOpacity(0.35);

    // Clase virtual: el estudiante no firma; el profesor marca su asistencia.
    Widget botonMeet() => ElevatedButton.icon(
      onPressed: link.isEmpty ? null : () async {
        try {
          await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No se pudo abrir el link'), backgroundColor: C.rojo));
          }
        }
      },
      icon: const Icon(Icons.videocam_rounded, size: 16),
      label: Text(link.isEmpty ? 'Link pendiente' : 'Unirme a Meet'),
      style: estiloBoton(fondo: C.azul, alto: 44, ancho: false),
    );

    return Tarjeta(child: Column(children: [
      // Info de la clase
      ClaseResumen(
        inicio: hm(clase['hora_inicio']), fin: hm(clase['hora_fin']),
        materia: (clase['materia'] ?? '').toString(),
        persona: clase['profesor_nombre']?.toString(),
        lugar: lugarDe(clase), virtual: virtual, acento: acento,
        trailing: virtual
          ? Pastilla(texto: yaFirmo ? 'Presente' : 'Virtual',
              color: yaFirmo ? C.verdeClaro : C.azul)
          : _EstadoBadge(
              yaFirmo: yaFirmo, disponible: disponible,
              expirado: expirado, msg: msg, pendiente: pend, esperando: esperando),
      ),
      if (esperando)
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: AvisoEstado(
            icono: Icons.hourglass_top_rounded, color: C.doradoClaro, texto: msg)),

      // Botones
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: onVerAsistencias,
            icon: const Icon(Icons.bar_chart_rounded, size: 16),
            label: const Text('Mis asistencias'),
            style: OutlinedButton.styleFrom(
              foregroundColor: C.tinta,
              side: const BorderSide(color: C.borde),
              minimumSize: const Size(0, 44),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          )),
          const SizedBox(width: 10),
          Expanded(child: virtual ? botonMeet() : ElevatedButton.icon(
            onPressed: (!yaFirmo && disponible && gpsOk && !firmando) ? onFirmar : null,
            icon: firmando
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(yaFirmo ? Icons.check_circle_rounded : Icons.edit_rounded, size: 16),
            label: Text(yaFirmo ? 'Firmado' : pend ? 'Guardado'
                : (disponible ? (clase['offline'] == true ? 'Tomar evidencia' : 'Firmar')
                    : (esperando ? 'Esperando' : 'No disponible'))),
            style: estiloBoton(
              fondo: yaFirmo ? C.verde.withOpacity(0.4)
                : (expirado ? C.rojo.withOpacity(0.3) : C.verde),
              alto: 44, ancho: false),
          )),
        ]),
      ),
    ]));
  }
}

class _EstadoBadge extends StatelessWidget {
  final bool yaFirmo, disponible, expirado, pendiente, esperando; final String msg;
  const _EstadoBadge({required this.yaFirmo, required this.disponible,
    required this.expirado, required this.msg,
    this.pendiente = false, this.esperando = false});

  @override
  Widget build(BuildContext context) {
    if (yaFirmo)        return const Pastilla(texto: 'Firmado', color: C.verdeClaro);
    if (pendiente)      return const Pastilla(texto: 'Pendiente', color: C.doradoClaro);
    if (esperando)      return const Pastilla(texto: 'Esperando', color: C.doradoClaro);
    if (disponible)     return const Pastilla(texto: 'Disponible', color: C.azul);
    if (expirado)       return const Pastilla(texto: 'Expirado', color: C.rojo);
    return const Pastilla(texto: 'En espera', color: C.suave);
  }
}
