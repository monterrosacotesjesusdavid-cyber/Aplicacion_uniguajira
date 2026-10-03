import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/ui_kit.dart';
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

  @override
  Widget build(BuildContext context) {
    if (_loading && _horario.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: C.verde));
    }
    return RefreshIndicator(
      onRefresh: _load, color: C.verdeClaro, backgroundColor: C.sup,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          const TituloPantalla(
            titulo: 'Mi horario',
            sub: 'Toca una materia para ver tus asistencias'),
          if (_error)
            const EstadoVacio(
              icono: Icons.wifi_off_rounded,
              titulo: 'No se pudo cargar el horario',
              mensaje: 'Revisa tu conexión y desliza hacia abajo para reintentar.')
          else if (_horario.isEmpty)
            const EstadoVacio(
              titulo: 'Sin materias asignadas',
              mensaje: 'Cuando te inscriban en materias aparecerán aquí.')
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
                  persona: c['profesor_nombre']?.toString(),
                  lugar: lugarDe(c),
                  virtual: c['modalidad'] == 'virtual',
                  esHoy: esHoy,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AsistenciasClaseScreen(
                      horarioId: c['id'], materia: (c['materia'] ?? '').toString()))),
                )),
              ]);
            }),
        ],
      ),
    );
  }
}
