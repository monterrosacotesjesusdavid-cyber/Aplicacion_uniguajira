import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/admin_ui.dart';
import '../../core/api.dart';

/// El administrador revisa las asistencias tomadas sin internet:
/// ve la foto de evidencia, la hora del celular, la distancia al salón y
/// el puntaje de coincidencia facial, y las aprueba o las rechaza.
class OfflineAdminScreen extends StatefulWidget {
  /// Se llama con el total de pendientes cada vez que se carga esa pestaña
  /// (sirve para el globo rojo del menú).
  final ValueChanged<int>? onPendientes;
  const OfflineAdminScreen({super.key, this.onPendientes});
  @override
  State<OfflineAdminScreen> createState() => _OfflineAdminState();
}

class _OfflineAdminState extends State<OfflineAdminScreen> {
  String _estado = 'pendiente';
  List _items = [];
  int _total = 0;
  bool _loading = true;
  String? _error;

  static const _etiquetas = {
    'pendiente': 'Pendiente', 'aprobada': 'Aprobada', 'rechazada': 'Rechazada'};
  static const _titulos = {
    'pendiente': 'Pendientes de revisión',
    'aprobada': 'Aprobadas', 'rechazada': 'Rechazadas'};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await Api.offlineAdmin(estado: _estado);
      if (!mounted) return;
      final total = (d['total'] as num?)?.toInt() ?? 0;
      setState(() { _items = d['items']; _total = total; _loading = false; });
      if (_estado == 'pendiente') widget.onPendientes?.call(total);
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'No se pudo cargar'; });
    }
  }

  void _snack(String m, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: const TextStyle(color: Colors.white)),
        backgroundColor: error ? A.malFuerte : A.teal));

  Future<void> _revisar(Map it, bool aprobar) async {
    String? motivo;
    if (!aprobar) {
      final ctrl = TextEditingController();
      motivo = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Motivo del rechazo', style: TextStyle(
            color: A.texto, fontWeight: FontWeight.w700)),
          content: TextField(controller: ctrl, autofocus: true, maxLength: 200,
            style: const TextStyle(color: A.texto),
            decoration: const InputDecoration(hintText: 'Ej: la foto no coincide')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d),
              child: const Text('Cancelar', style: TextStyle(color: A.suave))),
            TextButton(onPressed: () => Navigator.pop(d, ctrl.text.trim()),
              child: const Text('Rechazar', style: TextStyle(color: A.mal))),
          ],
        ),
      );
      if (motivo == null) return;
    }
    try {
      final r = await Api.revisarOffline(it['id'], aprobar, motivo: motivo);
      if (!mounted) return;
      if (r['_status'] == 200) {
        _snack(aprobar ? 'Aprobada: asistencia registrada' : 'Rechazada');
        _load();
      } else {
        _snack(r['error'] ?? 'No se pudo completar', error: true);
        if (r['_status'] == 409) _load();
      }
    } catch (_) {
      if (mounted) _snack('Error de conexión', error: true);
    }
  }

  Widget _selector() => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: A.card2, borderRadius: BorderRadius.circular(18),
      border: Border.all(color: A.borde)),
    child: Row(children: [
      for (final e in _etiquetas.keys)
        Expanded(child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () { if (_estado != e) { _estado = e; _load(); } },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              gradient: _estado == e ? A.gradOro : null,
              borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text(_etiquetas[e]!, style: TextStyle(
              color: _estado == e ? A.sobreOro : A.suave,
              fontSize: 12.5,
              fontWeight: _estado == e ? FontWeight.w800 : FontWeight.w600)))))),
    ]),
  );

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load, color: A.oro, backgroundColor: A.card1,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _selector(),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text(_titulos[_estado]!, style: const TextStyle(
            color: A.texto, fontSize: 15, fontWeight: FontWeight.w700))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
            decoration: BoxDecoration(
              gradient: A.gradOro, borderRadius: BorderRadius.circular(20)),
            child: Text('$_total', style: const TextStyle(color: A.sobreOro,
              fontSize: 12, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator(color: A.oro)))
        else if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 24),
            child: AdmVacio(Icons.cloud_off_rounded, _error!,
              accion: TextButton(onPressed: _load,
                child: const Text('Reintentar', style: TextStyle(
                  color: A.oro, fontWeight: FontWeight.w700)))))
        else if (_items.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 24),
            child: AdmVacio(Icons.inbox_rounded, 'Nada por aquí',
              sub: 'No hay asistencias en esta categoría.'))
        else
          ..._items.map((it) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Tarjeta(
              it: it, revisable: _estado == 'pendiente', onRevisar: _revisar))),
      ],
    ),
  );
}

class _Tarjeta extends StatefulWidget {
  final Map it;
  final bool revisable;
  final Future<void> Function(Map, bool) onRevisar;
  const _Tarjeta({required this.it, required this.revisable, required this.onRevisar});
  @override
  State<_Tarjeta> createState() => _TarjetaState();
}

class _TarjetaState extends State<_Tarjeta> {
  Uint8List? _foto;
  bool _cargandoFoto = false, _errorFoto = false;

  Future<void> _verFoto() async {
    setState(() { _cargandoFoto = true; _errorFoto = false; });
    Uint8List? b;
    try { b = await Api.fotoOffline(widget.it['id']); } catch (_) {}
    if (!mounted) return;
    setState(() { _foto = b; _cargandoFoto = false; _errorFoto = b == null; });
  }

  String _hora(dynamic iso) {
    final s = (iso ?? '').toString();
    return s.length >= 16 ? '${s.substring(0, 10)}  ${s.substring(11, 16)}' : s;
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.it;
    final esProf = it['rol'] == 'profesor';
    final fuera = it['fuera_zona'] == true;
    final sc = it['score_evidencia'] as num?;
    final se = it['score_envio'] as num?;

    Widget dato(IconData i, String t, {Color? c}) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(i, size: 15, color: c ?? A.suave),
        const SizedBox(width: 8),
        Expanded(child: Text(t, style: TextStyle(
          color: c ?? A.suave, fontSize: 12, height: 1.3))),
      ]));

    return AdmCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AdmIcono(esProf ? Icons.school_rounded : Icons.person_rounded,
            esProf ? A.tealClaro : A.azul, tam: 40),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((it['nombre'] ?? '').toString(),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: A.texto, fontSize: 14,
                fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${it['materia']}  ·  ${it['salon']}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: A.oroClaro, fontSize: 12)),
          ])),
          const SizedBox(width: 8),
          AdmPill(esProf ? 'Profesor' : 'Estudiante',
            esProf ? A.tealClaro : A.azul, size: 10),
        ]),
        const SizedBox(height: 6),
        const Divider(color: A.borde, height: 18),
        dato(Icons.phone_android_rounded,
          'Hora del celular (no verificada): ${_hora(it['hora_dispositivo'])}'),
        dato(Icons.cloud_upload_rounded, 'Enviada: ${_hora(it['hora_envio'])}'),
        dato(fuera ? Icons.wrong_location_rounded : Icons.location_on_rounded,
          it['distancia_m'] == null ? 'Sin ubicación'
            : fuera ? 'FUERA del salón (a ${it['distancia_m']} m)'
                    : 'Dentro del salón (${it['distancia_m']} m)',
          c: it['distancia_m'] == null ? null : (fuera ? A.mal : A.ok)),
        dato(Icons.face_rounded,
          'Coincidencia facial — evidencia: ${sc == null ? 'n/d' : sc.toStringAsFixed(2)}'
          '  ·  selfie de envío: ${se == null ? 'n/d' : se.toStringAsFixed(2)}'),
        if ((it['motivo'] ?? '').toString().isNotEmpty)
          dato(Icons.notes_rounded, 'Motivo: ${it['motivo']}'),
        const SizedBox(height: 14),
        if (_foto != null)
          ClipRRect(borderRadius: BorderRadius.circular(16),
            child: Image.memory(_foto!, height: 240,
              width: double.infinity, fit: BoxFit.cover))
        else
          OutlinedButton.icon(
            onPressed: _cargandoFoto ? null : _verFoto,
            icon: _cargandoFoto
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: A.oro))
              : const Icon(Icons.image_rounded, size: 18),
            label: Text(_errorFoto
              ? 'No se pudo cargar — reintentar' : 'Ver foto de evidencia'),
            style: OutlinedButton.styleFrom(
              foregroundColor: A.texto,
              side: const BorderSide(color: A.borde),
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)))),
        if (widget.revisable) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => widget.onRevisar(it, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: A.mal,
                side: BorderSide(color: A.mal.withOpacity(0.6)),
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
              child: const Text('Rechazar',
                style: TextStyle(fontWeight: FontWeight.w700)))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: () => widget.onRevisar(it, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: A.ok, foregroundColor: A.sobreOro,
                elevation: 0, minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
              child: const Text('Aprobar',
                style: TextStyle(fontWeight: FontWeight.w800)))),
          ]),
        ],
      ]),
    );
  }
}
