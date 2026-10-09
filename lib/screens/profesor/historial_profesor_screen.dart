import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/offline.dart';
import '../../core/ui_kit.dart';
import 'asistencias_materia_screen.dart';

const _abrevDias = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

/// Una materia del profesor. Puede tener varios horarios (uno por día), así que
/// se guardan todos los ids para juntar la asistencia de sus estudiantes.
class _Materia {
  final String nombre;
  final List<int> ids = [];
  final Set<int> dias = {};
  Color color = C.verde;
  // Resultado (null mientras carga).
  int? estudiantes, promedio, bajo;
  bool fallo = false;

  _Materia(this.nombre);
}

/// Pestaña "Historial" del profesor: sus materias con el promedio de asistencia de
/// sus estudiantes. Al tocar una se ve la asistencia de todo el semestre y se puede
/// exportar un solo PDF con toda la información.
class HistorialProfesorScreen extends StatefulWidget {
  const HistorialProfesorScreen({super.key});
  @override
  State<HistorialProfesorScreen> createState() => _HistProfState();
}

class _HistProfState extends State<HistorialProfesorScreen> {
  List<_Materia> _materias = [];
  bool _loading = true;
  bool _error = false;
  String _msgError = 'Revisa tu conexión y desliza hacia abajo para reintentar.';

  final _paleta = [C.verde, C.azul, C.naranja, C.rojo, C.doradoClaro];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = _materias.isEmpty; _error = false; });
    try {
      final horario = await Api.horarioSemanaProfesor();
      final porNombre = <String, _Materia>{};
      for (final c in horario) {
        final n = (c['materia'] ?? '').toString();
        final m = porNombre.putIfAbsent(n, () => _Materia(n));
        final id = c['id'];
        if (id is int && !m.ids.contains(id)) m.ids.add(id);
        final d = c['dia_num'];
        if (d is int) m.dias.add(d);
      }
      final lista = porNombre.values.toList()
        ..sort((a, b) => a.nombre.compareTo(b.nombre));
      for (var i = 0; i < lista.length; i++) {
        lista[i].color = _paleta[i % _paleta.length];
      }
      if (!mounted) return;
      setState(() { _materias = lista; _loading = false; });
      _cargarPromedios(lista);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _materias.isEmpty;
        _msgError = Net.esErrorDeRed(e)
            ? 'Revisa tu conexión y desliza hacia abajo para reintentar.'
            : 'El servidor no pudo cargar tus materias. Intenta más tarde.';
      });
    }
  }

  /// Calcula el promedio de asistencia de los estudiantes de cada materia.
  Future<void> _cargarPromedios(List<_Materia> lista) async {
    await Future.wait(lista.map((m) async {
      try {
        final d = await cargarMateria(m.nombre, m.ids);
        final ests = (d['estudiantes'] as List);
        int suma = 0, bajo = 0;
        for (final e in ests) {
          final p = (e['porcentaje'] as num).toInt();
          suma += p;
          if ((e['total'] as num) > 0 && p < 75) bajo++;
        }
        m.estudiantes = ests.length;
        m.promedio = ests.isEmpty ? 0 : (suma / ests.length).round();
        m.bajo = bajo;
        m.fallo = false;
      } catch (_) {
        m.fallo = true;
      }
      if (mounted) setState(() {});
    }));
  }

  Future<void> _abrir(_Materia m) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => AsistenciasMateriaProfScreen(
        materia: m.nombre, horarioIds: m.ids)));
    if (mounted) _cargarPromedios(_materias);
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: TituloPantalla(
              titulo: 'Historial',
              sub: 'Toca una materia para ver la asistencia de tus estudiantes')),
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
                        mensaje: 'Cuando tengas materias en tu horario aparecerán aquí.')
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
    final cargado = m.estudiantes != null;
    final sinEstudiantes = cargado && m.estudiantes == 0;
    final bajoProm = cargado && !sinEstudiantes && (m.promedio ?? 0) < 75;
    final colorPct = bajoProm ? C.rojo : C.verdeClaro;
    final dias = (m.dias.toList()..sort()).map((d) => _abrevDias[d]).join(' · ');
    final bajo = m.bajo ?? 0;

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
                else if (sinEstudiantes)
                  Pastilla(texto: 'Sin estudiantes', color: C.suave)
                else
                  Text('${m.promedio}%', style: TextStyle(color: colorPct,
                    fontSize: 20, fontWeight: FontWeight.w800)),
                Icon(Icons.chevron_right_rounded, color: C.suave),
              ]),
              const SizedBox(height: 4),
              Text(dias,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: C.suave, fontSize: 12.5)),
              const SizedBox(height: 10),
              if (!cargado && !m.fallo)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 6, backgroundColor: C.borde,
                    valueColor: AlwaysStoppedAnimation(C.borde)))
              else if (cargado && !sinEstudiantes) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (m.promedio ?? 0) / 100, minHeight: 6,
                    backgroundColor: C.borde,
                    valueColor: AlwaysStoppedAnimation(colorPct))),
                const SizedBox(height: 8),
                Text(
                  '${m.estudiantes} estudiante${m.estudiantes == 1 ? '' : 's'}'
                  '  ·  promedio de asistencia'
                  '${bajo > 0 ? '  ·  $bajo por debajo del 75%' : ''}',
                  style: TextStyle(
                    color: bajo > 0 ? C.rojo : C.suave, fontSize: 12)),
              ],
            ]),
          )),
        ]),
      ),
    );
  }
}
