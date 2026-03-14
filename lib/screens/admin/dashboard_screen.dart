import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashState();
}

class _DashState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await Api.dashboard();
      setState(() { _data = d; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final pct = _data != null && (_data!['total_clases_hoy'] ?? 0) > 0
      ? ((_data!['presentes_hoy'] as int) /
          (_data!['total_clases_hoy'] as int) * 100).round()
      : 0;

    return RefreshIndicator(
      onRefresh: _load, color: C.verdeClaro, backgroundColor: C.sup,
      child: _loading
        ? const Center(child: CircularProgressIndicator(color: C.verde))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Resumen del día', style: TextStyle(color: Colors.white,
                fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),

              if (_data != null) ...[
                // Porcentaje general
                Card(child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Asistencia hoy', style: TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                      Text('$pct%', style: TextStyle(
                        color: pct >= 70 ? C.verdeClaro : C.rojo,
                        fontSize: 24, fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: pct / 100,
                        backgroundColor: C.borde,
                        valueColor: AlwaysStoppedAnimation(
                          pct >= 70 ? C.verdeClaro : C.rojo),
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('${_data!['total_clases_hoy']} clases programadas hoy',
                      style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12)),
                  ]),
                )),
                const SizedBox(height: 12),

                // Métricas
                Row(children: [
                  _Metric('Total\nProfesores', '${_data!['total_profesores']}',
                    Icons.people_rounded, C.verde),
                  const SizedBox(width: 10),
                  _Metric('Presentes\nhoy', '${_data!['presentes_hoy']}',
                    Icons.check_circle_rounded, C.verdeClaro),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _Metric('Tardanzas\nhoy', '${_data!['tardanzas_hoy']}',
                    Icons.schedule_rounded, C.naranja),
                  const SizedBox(width: 10),
                  _Metric('Ausentes\nhoy', '${_data!['ausentes_hoy']}',
                    Icons.cancel_rounded, C.rojo),
                ]),
              ],
            ],
          ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label, value; final IconData icon; final Color color;
  const _Metric(this.label, this.value, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Expanded(child: Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Row(children: [
      Container(width: 42, height: 42,
        decoration: BoxDecoration(color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color, size: 22)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(color: color, fontSize: 26,
          fontWeight: FontWeight.w800)),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.45),
          fontSize: 11)),
      ])),
    ]),
  )));
}
