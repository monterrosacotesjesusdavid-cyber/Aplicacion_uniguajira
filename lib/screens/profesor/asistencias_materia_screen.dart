import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/offline.dart';
import '../../core/planilla_pdf.dart';
import '../../core/ui_kit.dart';

const _diasAbrev = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

String _hm(dynamic h) {
  final s = (h ?? '').toString();
  return s.length >= 5 ? s.substring(0, 5) : s;
}

/// Junta las planillas de todos los horarios (días) de una materia en una sola:
/// cada estudiante con todas sus fechas del semestre y sus totales.
Map<String, dynamic> unirPlanillas(String materia, List<Map> planillas) {
  String profesor = '';
  final salones = <String>[];
  final horarios = <String>[];
  final porId = <int, Map<String, dynamic>>{};

  for (final p in planillas) {
    final c = Map<String, dynamic>.from(p['clase'] as Map);
    if (profesor.isEmpty) profesor = (c['profesor'] ?? '').toString();
    final salon = (c['salon'] ?? '').toString();
    if (salon.isNotEmpty && !salones.contains(salon)) salones.add(salon);
    horarios.add('${c['dia'] ?? ''} ${_hm(c['hora_inicio'])}-${_hm(c['hora_fin'])}');

    for (final raw in (p['estudiantes'] as List)) {
      final e = Map<String, dynamic>.from(raw as Map);
      final id = (e['id'] as num).toInt();
      final acc = porId.putIfAbsent(id, () => {
            'id': id,
            'nombre': e['nombre'],
            'usuario': e['usuario'],
            'presentes': 0,
            'tardanzas': 0,
            'ausentes': 0,
            'total': 0,
            'registros': <Map<String, dynamic>>[],
          });
      acc['presentes'] = (acc['presentes'] as int) + (e['presentes'] as num).toInt();
      acc['tardanzas'] = (acc['tardanzas'] as int) + (e['tardanzas'] as num).toInt();
      acc['ausentes'] = (acc['ausentes'] as int) + (e['ausentes'] as num).toInt();
      acc['total'] = (acc['total'] as int) + (e['total'] as num).toInt();
      for (final r in (e['registros'] as List)) {
        (acc['registros'] as List).add(Map<String, dynamic>.from(r as Map));
      }
    }
  }

  final ests = porId.values.toList();
  for (final e in ests) {
    final regs = e['registros'] as List<Map<String, dynamic>>;
    regs.sort((a, b) => (b['fecha'] as String).compareTo(a['fecha'] as String));
    final total = e['total'] as int;
    e['porcentaje'] = total == 0
        ? 0
        : (((e['presentes'] as int) + (e['tardanzas'] as int)) / total * 100).round();
  }
  ests.sort((a, b) => (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString()));

  return {
    'clase': {
      'materia': materia,
      'profesor': profesor,
      'salon': salones.join(', '),
      'horario_texto': horarios.join('   ·   '),
    },
    'estudiantes': ests,
  };
}

/// Carga y une las planillas de todos los horarios de una materia.
Future<Map<String, dynamic>> cargarMateria(String materia, List<int> ids) async {
  final listas = await Future.wait(ids.map(Api.estudiantesClase));
  return unirPlanillas(materia, listas);
}

/// El profesor toca una materia y ve la asistencia de TODOS sus estudiantes en el
/// semestre (todas las fechas y todos los días de la materia). Desde aquí exporta
/// UN solo PDF con toda la información.
class AsistenciasMateriaProfScreen extends StatefulWidget {
  final String materia;
  final List<int> horarioIds;
  const AsistenciasMateriaProfScreen(
      {super.key, required this.materia, required this.horarioIds});
  @override
  State<AsistenciasMateriaProfScreen> createState() => _AsistMateriaState();
}

class _AsistMateriaState extends State<AsistenciasMateriaProfScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _generando = false;
  String? _error;
  // Cumplimiento propio del profesor en esta materia (sus firmas).
  int _aTiempo = 0, _tarde = 0, _aus = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = _data == null; _error = null; });
    try {
      final d = await cargarMateria(widget.materia, widget.horarioIds);
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_data == null) {
            _error = Net.esErrorDeRed(e)
                ? 'No se pudo cargar la asistencia. Revisa tu conexión.'
                : 'No se pudo cargar la asistencia. Intenta más tarde.';
          }
        });
      }
    }
    _cargarMisFirmas();
  }

  Future<void> _cargarMisFirmas() async {
    try {
      final l = await Api.historialProfesor();
      int a = 0, t = 0, x = 0;
      for (final r in l) {
        if (r['materia'] != widget.materia) continue;
        final e = r['estado'];
        if (e == 'a_tiempo') { a++; }
        else if (e == 'tardanza') { t++; }
        else { x++; }
      }
      if (mounted) setState(() { _aTiempo = a; _tarde = t; _aus = x; });
    } catch (_) {}
  }

  Future<void> _pdf() async {
    if (_data == null || _generando) return;
    setState(() => _generando = true);
    try {
      await PlanillaPdf.compartir(_data!);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo generar el PDF')));
      }
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  List<Map<String, dynamic>> get _ests => ((_data?['estudiantes'] ?? []) as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  @override
  Widget build(BuildContext context) {
    final ests = _ests;
    final sumaPct = ests.fold<int>(0, (a, e) => a + (e['porcentaje'] as num).toInt());
    final promedio = ests.isEmpty ? 0 : (sumaPct / ests.length).round();
    final bajo = ests.where((e) =>
        (e['total'] as num) > 0 && (e['porcentaje'] as num) < 75).length;
    final misTotal = _aTiempo + _tarde + _aus;
    final miPct = misTotal == 0 ? 0 : ((_aTiempo + _tarde) / misTotal * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.materia, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            tooltip: 'Exportar PDF',
            onPressed: (_data == null || ests.isEmpty || _generando) ? null : _pdf,
            icon: _generando
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.verde))
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: C.tinta.withOpacity(0.6))),
                    const SizedBox(height: 14),
                    ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
                  ])))
              : RefreshIndicator(
                  onRefresh: _load, color: C.verdeClaro, backgroundColor: C.sup,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(children: [
                            Row(children: [
                              _Dato('Estudiantes', '${ests.length}', C.suave),
                              _Dato('Promedio', ests.isEmpty ? '—' : '$promedio%',
                                  promedio >= 75 ? C.verdeClaro : C.rojo),
                              _Dato('Bajo 75%', '$bajo',
                                  bajo > 0 ? C.rojo : C.verdeClaro),
                            ]),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: (ests.isEmpty || _generando) ? null : _pdf,
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: Text(_generando
                                  ? 'Generando PDF...'
                                  : 'Exportar asistencia completa (PDF)'),
                              style: estiloBoton(fondo: C.verde)),
                          ]),
                        ),
                      ),
                      if (misTotal > 0) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(children: [
                              Row(children: [
                                Text('Tu cumplimiento',
                                    style: TextStyle(
                                        color: C.tinta,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                                const Spacer(),
                                Text('$miPct%',
                                    style: TextStyle(
                                        color: miPct >= 90 ? C.verdeClaro : C.naranja,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800)),
                              ]),
                              const SizedBox(height: 10),
                              Row(children: [
                                _Dato('A tiempo', '$_aTiempo', C.verdeClaro),
                                _Dato('Tardanzas', '$_tarde', C.naranja),
                                _Dato('Ausentes', '$_aus', C.rojo),
                              ]),
                            ]),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text('Asistencia de los estudiantes',
                          style: TextStyle(
                              color: C.tinta, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Toca un estudiante para ver todas sus fechas',
                          style: TextStyle(color: C.suave, fontSize: 12.5)),
                      const SizedBox(height: 10),
                      if (ests.isEmpty)
                        const EstadoVacio(
                            titulo: 'Sin estudiantes',
                            mensaje: 'No hay estudiantes inscritos en esta materia.')
                      else
                        ...ests.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _EstudianteCard(e: e),
                            )),
                    ],
                  ),
                ),
    );
  }
}

class _Dato extends StatelessWidget {
  final String label, valor;
  final Color color;
  const _Dato(this.label, this.valor, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Column(children: [
        Text(valor,
            style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label, style: TextStyle(color: C.suave, fontSize: 11)),
      ]));
}

class _EstudianteCard extends StatelessWidget {
  final Map<String, dynamic> e;
  const _EstudianteCard({required this.e});

  @override
  Widget build(BuildContext context) {
    final pct = (e['porcentaje'] as num).toInt();
    final total = (e['total'] as num).toInt();
    final col = pct >= 75 ? C.verdeClaro : C.rojo;
    final regs = (e['registros'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          iconColor: C.tinta70,
          collapsedIconColor: C.suave,
          title: Text((e['nombre'] ?? '').toString(),
              style: TextStyle(
                  color: C.tinta, fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                'Presentes ${e['presentes']}  •  Tardanzas ${e['tardanzas']}  •  Ausentes ${e['ausentes']}',
                style: TextStyle(color: C.suave, fontSize: 11)),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: col.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(total == 0 ? '--' : '$pct%',
                  style: TextStyle(
                      color: col, fontSize: 13, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, color: C.suave),
          ]),
          children: [
            if (regs.isEmpty)
              Text('Aún no hay clases registradas',
                  style: TextStyle(color: C.suave, fontSize: 12))
            else
              ...regs.map((r) {
                final estado = (r['estado'] ?? 'ausente').toString();
                final Color c = estado == 'presente'
                    ? C.verdeClaro
                    : estado == 'tardanza' ? C.naranja : C.rojo;
                final IconData ico = estado == 'presente'
                    ? Icons.check_circle_rounded
                    : estado == 'tardanza'
                        ? Icons.schedule_rounded
                        : Icons.cancel_rounded;
                final txt = estado == 'presente'
                    ? 'Presente'
                    : estado == 'tardanza' ? 'Tardanza' : 'Ausente';
                final h = r['hora_registro']?.toString();
                final hora = (h != null && h.length >= 16) ? h.substring(11, 16) : '';
                final f = (r['fecha'] ?? '').toString();
                final d = DateTime.tryParse(f);
                final dia = d == null ? '' : '${_diasAbrev[d.weekday]} ';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Icon(ico, color: c, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text('$dia$f',
                            style: TextStyle(color: C.tinta, fontSize: 12))),
                    if (hora.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(hora,
                              style: TextStyle(color: C.suave, fontSize: 11))),
                    Text(txt,
                        style: TextStyle(
                            color: c, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                );
              }),
          ],
        ),
      ),
    );
  }
}
