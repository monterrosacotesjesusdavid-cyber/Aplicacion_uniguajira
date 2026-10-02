import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import 'asistencias_clase_screen.dart';

/// Horario semanal del estudiante. Al tocar una materia ve las fechas, los días
/// y las horas en que firmó, con su porcentaje de asistencia.
class HorarioEstudianteScreen extends StatefulWidget {
  const HorarioEstudianteScreen({super.key});
  @override
  State<HorarioEstudianteScreen> createState() => _HorEstState();
}

class _HorEstState extends State<HorarioEstudianteScreen> {
  List _horario = [];
  bool _loading = true;
  bool _error = false;
  static const _dias = ['', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    try {
      final list = await Api.horarioSemanaEstudiante();
      if (mounted) setState(() { _horario = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = _horario.isEmpty; });
    }
  }

  String _hm(dynamic h) {
    final s = (h ?? '').toString();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _horario.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: C.verde));
    }
    return RefreshIndicator(
      onRefresh: _load, color: C.verdeClaro, backgroundColor: C.sup,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Mi Horario Semanal', style: TextStyle(color: C.tinta,
            fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Toca una materia para ver tus asistencias',
            style: TextStyle(color: C.suave, fontSize: 12)),
          const SizedBox(height: 12),
          if (_error)
            const Card(child: Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text('No se pudo cargar el horario. Revisa tu conexión.',
                textAlign: TextAlign.center, style: TextStyle(color: C.suave)))))
          else if (_horario.isEmpty)
            const Card(child: Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text('No tienes materias asignadas',
                style: TextStyle(color: C.suave)))))
          else
            ...List.generate(7, (i) => i + 1).map((n) {
              final clases = _horario.where((c) => c['dia_num'] == n).toList();
              if (clases.isEmpty) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 10, bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: C.verde.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6)),
                    child: Text(_dias[n], style: const TextStyle(color: C.verdeClaro,
                      fontSize: 12, fontWeight: FontWeight.w700)))),
                ...clases.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => AsistenciasClaseScreen(
                        horarioId: c['id'], materia: (c['materia'] ?? '').toString()))),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(color: C.verde,
                            borderRadius: BorderRadius.circular(8)),
                          child: Column(children: [
                            Text(_hm(c['hora_inicio']), style: const TextStyle(
                              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                            Text(_hm(c['hora_fin']), style: TextStyle(
                              color: Colors.white.withOpacity(0.75), fontSize: 10)),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text((c['materia'] ?? '').toString(), style: const TextStyle(
                            color: C.tinta, fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            [c['profesor_nombre'], c['salon']]
                              .where((e) => e != null && e.toString().isNotEmpty)
                              .join('  •  '),
                            style: const TextStyle(color: C.suave, fontSize: 12)),
                        ])),
                        const Icon(Icons.chevron_right_rounded, color: C.suave),
                      ]),
                    ),
                  )),
                )),
              ]);
            }),
        ],
      ),
    );
  }
}
