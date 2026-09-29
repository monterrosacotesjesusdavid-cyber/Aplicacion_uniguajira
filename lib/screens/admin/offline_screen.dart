import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/theme.dart';

/// El administrador revisa las asistencias tomadas sin internet:
/// ve la foto de evidencia, la hora del celular, la distancia al salón y
/// el puntaje de coincidencia facial, y las aprueba o las rechaza.
class OfflineAdminScreen extends StatefulWidget {
  const OfflineAdminScreen({super.key});
  @override
  State<OfflineAdminScreen> createState() => _OfflineAdminState();
}

class _OfflineAdminState extends State<OfflineAdminScreen> {
  String _estado = 'pendiente';
  List _items = [];
  int _total = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await Api.offlineAdmin(estado: _estado);
      if (!mounted) return;
      setState(() { _items = d['items']; _total = d['total'] ?? 0; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'No se pudo cargar'; });
    }
  }

  void _snack(String m, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(m), backgroundColor: error ? C.rojo : C.verde));

  Future<void> _revisar(Map it, bool aprobar) async {
    String? motivo;
    if (!aprobar) {
      final ctrl = TextEditingController();
      motivo = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Motivo del rechazo', style: TextStyle(color: Colors.white)),
          content: TextField(controller: ctrl, autofocus: true, maxLength: 200,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'Ej: la foto no coincide')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: C.suave))),
            TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Rechazar', style: TextStyle(color: C.rojo))),
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

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load, color: C.verdeClaro, backgroundColor: C.sup,
    child: ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        const Expanded(child: Text('Asistencias sin internet',
          style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: C.dorado, borderRadius: BorderRadius.circular(20)),
          child: Text('$_total', style: const TextStyle(color: Colors.white,
            fontSize: 12, fontWeight: FontWeight.w700))),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        for (final e in const ['pendiente', 'aprobada', 'rechazada'])
          ChoiceChip(
            label: Text(e[0].toUpperCase() + e.substring(1)),
            selected: _estado == e,
            onSelected: (_) { _estado = e; _load(); }),
      ]),
      const SizedBox(height: 14),
      if (_loading)
        const Center(child: Padding(padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: C.verde)))
      else if (_error != null)
        Center(child: Text(_error!, style: const TextStyle(color: C.rojo)))
      else if (_items.isEmpty)
        const Card(child: Padding(padding: EdgeInsets.all(40),
          child: Center(child: Text('Nada por aquí',
            style: TextStyle(color: C.suave)))))
      else
        ..._items.map((it) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _Tarjeta(it: it, revisable: _estado == 'pendiente', onRevisar: _revisar))),
    ]),
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
    Widget dato(IconData i, String t, {Color c = Colors.white70}) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Icon(i, size: 14, color: c), const SizedBox(width: 6),
        Expanded(child: Text(t, style: TextStyle(color: c, fontSize: 12))),
      ]));

    return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(it['nombre'] ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (esProf ? C.verde : C.azul).withOpacity(0.2),
            borderRadius: BorderRadius.circular(20)),
          child: Text(esProf ? 'Profesor' : 'Estudiante',
            style: TextStyle(color: esProf ? C.verdeClaro : const Color(0xFF5DADE2),
              fontSize: 10, fontWeight: FontWeight.w700))),
      ]),
      const SizedBox(height: 2),
      Text('${it['materia']}  •  ${it['salon']}',
        style: const TextStyle(color: C.doradoClaro, fontSize: 12)),
      dato(Icons.phone_android_rounded,
        'Hora del celular (no verificada): ${_hora(it['hora_dispositivo'])}'),
      dato(Icons.cloud_upload_rounded, 'Enviada: ${_hora(it['hora_envio'])}'),
      dato(fuera ? Icons.wrong_location_rounded : Icons.location_on_rounded,
        it['distancia_m'] == null ? 'Sin ubicación'
          : fuera ? 'FUERA del salón (a ${it['distancia_m']} m)' : 'Dentro del salón (${it['distancia_m']} m)',
        c: fuera ? const Color(0xFFFF6B6B) : C.verdeClaro),
      dato(Icons.face_rounded,
        'Coincidencia facial — evidencia: ${sc == null ? 'n/d' : sc.toStringAsFixed(2)}'
        '  •  selfie de envío: ${se == null ? 'n/d' : se.toStringAsFixed(2)}'),
      if ((it['motivo'] ?? '').toString().isNotEmpty)
        dato(Icons.notes_rounded, 'Motivo: ${it['motivo']}'),
      const SizedBox(height: 10),
      if (_foto != null)
        ClipRRect(borderRadius: BorderRadius.circular(10),
          child: Image.memory(_foto!, height: 240, width: double.infinity, fit: BoxFit.cover))
      else
        OutlinedButton.icon(
          onPressed: _cargandoFoto ? null : _verFoto,
          icon: _cargandoFoto
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.image_rounded, size: 18),
          label: Text(_errorFoto ? 'No se pudo cargar — reintentar' : 'Ver foto de evidencia'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white,
            side: const BorderSide(color: C.borde), minimumSize: const Size(double.infinity, 42))),
      if (widget.revisable) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => widget.onRevisar(it, false),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF6B6B),
              side: const BorderSide(color: C.rojo), minimumSize: const Size(0, 44)),
            child: const Text('Rechazar'))),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            onPressed: () => widget.onRevisar(it, true),
            style: ElevatedButton.styleFrom(backgroundColor: C.verde, minimumSize: const Size(0, 44)),
            child: const Text('Aprobar'))),
        ]),
      ],
    ])));
  }
}
