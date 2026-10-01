import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/liveness_screen.dart';
import '../../core/offline.dart';
import '../../core/offline_widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/gps_helper.dart';
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

  @override
  void initState() {
    super.initState();
    _initGps();
    _load();
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

          // Cabecera
          Row(children: [
            Expanded(child: Text('Mis Clases',
              style: const TextStyle(color: C.tinta, fontSize: 19,
                fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: C.azul, borderRadius: BorderRadius.circular(6)),
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

// ── GPS BANNER ────────────────────────────────────────────────────────
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
          color: (loading ? Colors.orange : ok ? C.verde : C.rojo).withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(loading ? Icons.gps_not_fixed : ok ? Icons.gps_fixed : Icons.gps_off,
          color: loading ? Colors.orange : ok ? C.verdeClaro : C.rojo, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(
          loading ? 'Obteniendo ubicación...'
            : ok ? 'GPS activo — listo para firmar'
            : 'GPS no disponible — actívalo para firmar',
          style: TextStyle(
            color: loading ? Colors.orange : ok ? C.verdeClaro : C.rojo,
            fontSize: 12, fontWeight: FontWeight.w500),
        )),
        if (loading) const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)),
      ]),
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

    return Card(child: Column(children: [
      // Info clase
      Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: C.azul.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Text(clase['hora_inicio']?.substring(0, 5) ?? '',
              style: const TextStyle(color: C.azul, fontSize: 15,
                fontWeight: FontWeight.w700)),
            Text(clase['hora_fin']?.substring(0, 5) ?? '',
              style: TextStyle(color: C.tinta.withOpacity(0.4), fontSize: 10)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(clase['materia'] ?? '',
            style: const TextStyle(color: C.tinta, fontSize: 14,
              fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(clase['profesor_nombre'] ?? '',
            style: const TextStyle(color: C.doradoClaro, fontSize: 12)),
          Text(clase['salon'] ?? '',
            style: TextStyle(color: C.tinta.withOpacity(0.4), fontSize: 11)),
        ])),
        // Estado badge
        _EstadoBadge(
          yaFirmo: yaFirmo, disponible: disponible,
          expirado: expirado, msg: msg, pendiente: pend, esperando: esperando),
      ])),
      if (esperando)
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(children: [
            const Icon(Icons.hourglass_top_rounded, size: 14, color: C.doradoClaro),
            const SizedBox(width: 6),
            Expanded(child: Text(msg,
              style: const TextStyle(color: C.doradoClaro, fontSize: 11))),
          ])),

      // Botones
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Row(children: [
          // Ver asistencias
          Expanded(child: OutlinedButton.icon(
            onPressed: onVerAsistencias,
            icon: const Icon(Icons.bar_chart_rounded, size: 16),
            label: const Text('Mis asistencias'),
            style: OutlinedButton.styleFrom(
              foregroundColor: C.tinta,
              side: const BorderSide(color: C.borde),
              minimumSize: const Size(0, 42),
              textStyle: const TextStyle(fontSize: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          )),
          const SizedBox(width: 10),
          // Firmar
          Expanded(child: ElevatedButton.icon(
            onPressed: (!yaFirmo && disponible && gpsOk && !firmando) ? onFirmar : null,
            icon: firmando
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(yaFirmo ? Icons.check_circle_rounded : Icons.edit_rounded, size: 16),
            label: Text(yaFirmo ? 'Firmado' : pend ? 'Guardado'
                : (disponible ? (clase['offline'] == true ? 'Tomar evidencia' : 'Firmar')
                    : (esperando ? 'Esperando' : 'No disp.'))),
            style: ElevatedButton.styleFrom(
              backgroundColor: yaFirmo ? C.verde.withOpacity(0.4)
                : (expirado ? C.rojo.withOpacity(0.3) : C.verde),
              disabledBackgroundColor: C.borde,
              minimumSize: const Size(0, 42),
              textStyle: const TextStyle(fontSize: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
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
    Color col, bg;
    String txt;
    if (yaFirmo)        { col = C.verdeClaro; bg = C.verde.withOpacity(0.12); txt = 'Firmado'; }
    else if (pendiente) { col = C.doradoClaro; bg = C.dorado.withOpacity(0.12); txt = 'Pendiente'; }
    else if (esperando) { col = C.doradoClaro; bg = C.dorado.withOpacity(0.12); txt = 'Esperando'; }
    else if (disponible){ col = Colors.amber.shade400; bg = Colors.amber.withOpacity(0.1); txt = 'Disponible'; }
    else if (expirado)  { col = C.rojo; bg = C.rojo.withOpacity(0.1); txt = 'Expirado'; }
    else                { col = C.suave; bg = C.borde; txt = 'En espera'; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(txt, style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w700)),
    );
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
      const SizedBox(height: 6),
      Text('No tienes clases programadas para hoy',
        style: TextStyle(color: C.tinta.withOpacity(0.45), fontSize: 13),
        textAlign: TextAlign.center),
    ]),
  ));
}
