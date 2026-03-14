import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api.dart';

class DetalleProfesorScreen extends StatefulWidget {
  final int profesorId;
  final String nombre;
  const DetalleProfesorScreen(
      {super.key, required this.profesorId, required this.nombre});
  @override
  State<DetalleProfesorScreen> createState() => _DetState();
}

class _DetState extends State<DetalleProfesorScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await Api.detalleProfesor(widget.profesorId);
      setState(() { _data = d; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nombre, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context)),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: C.verde))
        : RefreshIndicator(
            onRefresh: _load, color: C.verdeClaro, backgroundColor: C.sup,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_data != null) ...[
                  // Info general
                  Card(child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        CircleAvatar(
                          radius: 28, backgroundColor: C.verde.withOpacity(0.15),
                          child: Text(widget.nombre[0].toUpperCase(),
                            style: const TextStyle(color: C.verdeClaro,
                              fontSize: 22, fontWeight: FontWeight.w700))),
                        const SizedBox(width: 14),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.nombre, style: const TextStyle(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                          Text('CC ${_data!['cedula'] ?? ''}',
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
                          Text(_data!['correo'] ?? '',
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                        ])),
                      ]),
                    ]),
                  )),
                  const SizedBox(height: 12),

                  // Estadísticas globales
                  _buildStats(),
                  const SizedBox(height: 16),

                  // Historial
                  const Text('Historial de asistencias', style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  ..._buildHistorial(),
                ],
              ],
            ),
          ),
    );
  }

  Widget _buildStats() {
    final stats = _data!['estadisticas'] as Map<String, dynamic>? ?? {};
    final aT   = (stats['a_tiempo']  as int?) ?? 0;
    final tard = (stats['tardanzas'] as int?) ?? 0;
    final aus  = (stats['ausencias'] as int?) ?? 0;
    final total = aT + tard + aus;
    final pct = total > 0 ? ((aT + tard) / total * 100).round() : 0;
    final pctColor = pct >= 80 ? C.verdeClaro : pct >= 60 ? C.naranja : C.rojo;

    return Card(child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Porcentaje de asistencia', style: TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          Text('$pct%', style: TextStyle(color: pctColor,
            fontSize: 28, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct / 100, backgroundColor: C.borde,
            valueColor: AlwaysStoppedAnimation(pctColor), minHeight: 10)),
        const SizedBox(height: 14),
        Row(children: [
          _StatItem('A tiempo',  '$aT',   C.verdeClaro),
          _StatItem('Tardanzas', '$tard', C.naranja),
          _StatItem('Ausencias', '$aus',  C.rojo),
          _StatItem('Total',     '$total',C.suave),
        ]),
        if (pct < 75) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: C.rojo.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
              border: Border.all(color: C.rojo.withOpacity(0.25))),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: C.rojo, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('Asistencia por debajo del 75% mínimo',
                style: TextStyle(color: C.rojo.withOpacity(0.9), fontSize: 11))),
            ])),
        ],
      ]),
    ));
  }

  List<Widget> _buildHistorial() {
    final hist = (_data!['historial'] as List?) ?? [];
    if (hist.isEmpty) return [Card(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Text('Sin registros',
        style: TextStyle(color: Colors.white.withOpacity(0.5))))))];

    return hist.map<Widget>((a) {
      final estado = a['estado'] as String? ?? 'ausente';
      Color col; IconData ico; Color bg;
      if (estado == 'a_tiempo')  { col = C.verdeClaro; ico = Icons.check_circle_rounded; bg = C.verde.withOpacity(0.1); }
      else if (estado == 'tardanza') { col = C.naranja; ico = Icons.schedule_rounded; bg = C.naranja.withOpacity(0.1); }
      else { col = C.rojo; ico = Icons.cancel_rounded; bg = C.rojo.withOpacity(0.1); }

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(width: 38, height: 38,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: Icon(ico, color: col, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a['materia'] ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 13,
                  fontWeight: FontWeight.w600)),
              Text('${a['fecha'] ?? ''}  •  ${(a['hora_registro'] as String?)?.substring(11, 16) ?? ''}  •  ${a['salon'] ?? ''}',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
              child: Text(
                estado == 'a_tiempo' ? 'A tiempo'
                  : estado == 'tardanza' ? '+${a['minutos_tarde']}min' : 'Ausente',
                style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w700))),
          ]),
        )),
      );
    }).toList();
  }
}

class _StatItem extends StatelessWidget {
  final String label, val; final Color color;
  const _StatItem(this.label, this.val, this.color);
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(val, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
    Text(label, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 10)),
  ]));
}
