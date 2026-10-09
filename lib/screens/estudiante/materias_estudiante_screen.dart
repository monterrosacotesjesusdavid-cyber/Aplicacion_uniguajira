import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/offline.dart';
import '../../core/ui_kit.dart';
import 'asistencias_clase_screen.dart';

const _abrevDias = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

/// Una materia del estudiante. Puede tener varios horarios (uno por día),
/// así que se guardan todos los ids para juntar su historial.
class _Materia {
  final String nombre;
  final String? profesor;
  final List<int> ids = [];
  final Set<int> dias = {};
  Color color = C.verde;
  // Resultado del historial (null mientras carga).
  int? presentes, tardanzas, total;
  bool fallo = false;

  _Materia(this.nombre, this.profesor);

  int get pct => (total == null || total == 0)
      ? 0
      : (((presentes ?? 0) + (tardanzas ?? 0)) / total! * 100).round();
}

/// Pestaña "Materias": todas las materias del estudiante con su porcentaje de
/// asistencia. Al tocar una se abre el historial de fechas, días y horas.
class MateriasEstudianteScreen extends StatefulWidget {
  const MateriasEstudianteScreen({super.key});
  @override
  State<MateriasEstudianteScreen> createState() => _MateriasEstState();
}

class _MateriasEstState extends State<MateriasEstudianteScreen> {
  List<_Materia> _materias = [];
  bool _loading = true;
  bool _error = false;
  String _msgError = 'Revisa tu conexión y desliza hacia abajo para reintentar.';

  final _paleta = [C.verde, C.azul, C.naranja, C.rojo, C.doradoClaro];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = _materias.isEmpty; _error = false; });
    try {
      final horario = await Api.horarioSemanaEstudiante();
      final porNombre = <String, _Materia>{};
      for (final c in horario) {
        final n = (c['materia'] ?? '').toString();
        final m = porNombre.putIfAbsent(
            n, () => _Materia(n, c['profesor_nombre']?.toString()));
        final id = c['id'];
        if (id is int && !m.ids.contains(id)) m.ids.add(id);
        final d = c['dia_num'];
        if (d is int) m.dias.add(d);
      }
      final lista = porNombre.values.toList()
        ..sort((a, b) => a.nombre.compareTo(b.nombre));
      // Mismo color por materia que en la pantalla de Horario (orden alfabético).
      for (var i = 0; i < lista.length; i++) {
        lista[i].color = _paleta[i % _paleta.length];
      }
      if (!mounted) return;
      setState(() { _materias = lista; _loading = false; });
      _cargarPorcentajes(lista);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _materias.isEmpty;
        _msgError = Net.esErrorDeRed(e)
            ? 'Revisa tu conexión y desliza hacia abajo para reintentar.'
            : 'El servidor no pudo cargar los datos. Intenta más tarde.';
      });
    }
  }

  /// Calcula el porcentaje de cada materia sumando todos sus horarios.
  Future<void> _cargarPorcentajes(List<_Materia> lista) async {
    await Future.wait(lista.map((m) async {
      try {
        final listas = await Future.wait(m.ids.map(Api.asistenciasClase));
        int p = 0, t = 0, tot = 0;
        for (final l in listas) {
          for (final a in l) {
            tot++;
            if (a['estado'] == 'presente') p++;
            else if (a['estado'] == 'tardanza') t++;
          }
        }
        m.presentes = p; m.tardanzas = t; m.total = tot; m.fallo = false;
      } catch (_) {
        m.fallo = true;
      }
      if (mounted) setState(() {});
    }));
  }

  Future<void> _abrir(_Materia m) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => AsistenciasClaseScreen(
        horarioId: m.ids.first, horarioIds: m.ids, materia: m.nombre)));
    // Al volver se refresca por si cambió algo.
    if (mounted) _cargarPorcentajes(_materias);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: C.verde));
    }
    final n = _materias.length;
    return RefreshIndicator(
      onRefresh: _load, color: C.verdeClaro, backgroundColor: C.sup,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: TituloPantalla(
              titulo: 'Mis materias',
              sub: n == 0
                  ? 'Toca una materia para ver tu historial'
                  : 'Toca una materia para ver tu historial de asistencia')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _error
                ? EstadoVacio(
                    icono: Icons.wifi_off_rounded,
                    titulo: 'No se pudieron cargar las materias',
                    mensaje: _msgError)
                : n == 0
                    ? const EstadoVacio(
                        titulo: 'Sin materias asignadas',
                        mensaje: 'Cuando te inscriban en materias aparecerán aquí.')
                    : Column(children: [
                        for (final m in _materias)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _MateriaCard(materia: m, onTap: () => _abrir(m))),
                      ])),
        ],
      ),
    );
  }
}

class _MateriaCard extends StatelessWidget {
  final _Materia materia;
  final VoidCallback onTap;
  const _MateriaCard({required this.materia, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = materia;
    final cargado = m.total != null;
    final sinRegistros = cargado && m.total == 0;
    final bajo = cargado && !sinRegistros && m.pct < 75;
    final colorPct = bajo ? C.rojo : C.verdeClaro;
    final dias = (m.dias.toList()..sort()).map((d) => _abrevDias[d]).join(' · ');

    return Tarjeta(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: m.color),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(m.nombre,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: C.tinta, fontSize: 16,
                    fontWeight: FontWeight.w700))),
                const SizedBox(width: 8),
                if (!cargado)
                  Text(m.fallo ? '—' : '',
                    style: TextStyle(color: C.suave, fontSize: 18))
                else if (sinRegistros)
                  Pastilla(texto: 'Sin clases aún', color: C.suave)
                else
                  Text('${m.pct}%', style: TextStyle(color: colorPct,
                    fontSize: 20, fontWeight: FontWeight.w800)),
                Icon(Icons.chevron_right_rounded, color: C.suave),
              ]),
              const SizedBox(height: 4),
              Text(
                [if ((m.profesor ?? '').isNotEmpty) m.profesor!, if (dias.isNotEmpty) dias]
                    .join('  ·  '),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: C.suave, fontSize: 12.5)),
              const SizedBox(height: 10),
              if (!cargado && !m.fallo)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 6, backgroundColor: C.borde,
                    valueColor: AlwaysStoppedAnimation(C.borde)))
              else if (cargado && !sinRegistros) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: m.pct / 100, minHeight: 6, backgroundColor: C.borde,
                    valueColor: AlwaysStoppedAnimation(colorPct))),
                const SizedBox(height: 8),
                Text(
                  '${(m.presentes ?? 0) + (m.tardanzas ?? 0)} de ${m.total} clases asistidas'
                  '${bajo ? '  ·  por debajo del 75%' : ''}',
                  style: TextStyle(
                    color: bajo ? C.rojo : C.suave, fontSize: 12)),
              ],
            ]),
          )),
        ]),
      ),
    );
  }
}
