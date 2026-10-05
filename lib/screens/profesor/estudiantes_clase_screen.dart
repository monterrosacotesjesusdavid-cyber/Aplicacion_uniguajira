import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/planilla_pdf.dart';
import 'lista_virtual_screen.dart';

/// El profesor toca una de sus clases y ve cada estudiante con sus asistencias
/// y su porcentaje. Desde aquí descarga la planilla completa en PDF.
class EstudiantesClaseScreen extends StatefulWidget {
  final int horarioId;
  final String materia;
  const EstudiantesClaseScreen(
      {super.key, required this.horarioId, required this.materia});
  @override
  State<EstudiantesClaseScreen> createState() => _EstClaseState();
}

class _EstClaseState extends State<EstudiantesClaseScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _generando = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await Api.estudiantesClase(widget.horarioId);
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_data == null) _error = 'No se pudo cargar la planilla. Revisa tu conexión.';
        });
      }
    }
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

  bool get _virtual => (_data?['clase'] as Map?)?['modalidad'] == 'virtual';

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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.materia, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            tooltip: 'Descargar PDF',
            onPressed: (_data == null || _generando) ? null : _pdf,
            icon: _generando
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf_rounded)),
        ],
      ),
      body: _loading && _data == null
        ? const Center(child: CircularProgressIndicator(color: C.verde))
        : _error != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, textAlign: TextAlign.center,
                  style: TextStyle(color: C.tinta.withOpacity(0.6))),
                const SizedBox(height: 14),
                ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
              ])))
          : RefreshIndicator(
              onRefresh: _load, color: C.verdeClaro, backgroundColor: C.sup,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(children: [
                      Row(children: [
                        _Dato('Estudiantes', '${ests.length}', C.suave),
                        _Dato('Promedio', '$promedio%',
                          promedio >= 75 ? C.verdeClaro : C.rojo),
                        _Dato('Bajo 75%', '$bajo', bajo > 0 ? C.rojo : C.verdeClaro),
                      ]),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: (ests.isEmpty || _generando) ? null : _pdf,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(_generando ? 'Generando PDF...' : 'Descargar planilla en PDF'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44))),
                      if (_virtual) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ListaVirtualScreen(
                              horarioId: widget.horarioId, materia: widget.materia)))
                            .then((_) => _load()),
                          icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                          label: const Text('Pasar lista / corregir (virtual)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: C.tinta,
                            side: BorderSide(color: C.borde),
                            minimumSize: const Size(double.infinity, 44))),
                      ],
                    ]),
                  )),
                  const SizedBox(height: 16),
                  Text('Estudiantes',
                    style: TextStyle(color: C.tinta, fontSize: 16,
                      fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  if (ests.isEmpty)
                    Card(child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Center(child: Text('No hay estudiantes inscritos',
                        style: TextStyle(color: C.tinta.withOpacity(0.5)))),
                    ))
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
  final String label, valor; final Color color;
  const _Dato(this.label, this.valor, this.color);
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(valor, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
    Text(label, style: TextStyle(color: C.tinta.withOpacity(0.45), fontSize: 10)),
  ]));
}

class _EstudianteCard extends StatelessWidget {
  final Map<String, dynamic> e;
  const _EstudianteCard({required this.e});

  @override
  Widget build(BuildContext context) {
    final pct = (e['porcentaje'] as num).toInt();
    final total = (e['total'] as num).toInt();
    final ok = pct >= 75;
    final col = ok ? C.verdeClaro : C.rojo;
    final regs = (e['registros'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();

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
            style: TextStyle(color: C.tinta, fontSize: 13,
              fontWeight: FontWeight.w600)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Presentes ${e['presentes']}  •  Tardanzas ${e['tardanzas']}  •  Ausentes ${e['ausentes']}',
              style: TextStyle(color: C.tinta.withOpacity(0.45), fontSize: 11)),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: col.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
              child: Text(total == 0 ? '--' : '$pct%',
                style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, color: C.suave),
          ]),
          children: [
            if (regs.isEmpty)
              Text('Aún no hay clases registradas',
                style: TextStyle(color: C.tinta.withOpacity(0.45), fontSize: 12))
            else
              ...regs.map((r) {
                final estado = (r['estado'] ?? 'ausente').toString();
                final Color c = estado == 'presente' ? C.verdeClaro
                    : estado == 'tardanza' ? C.naranja : C.rojo;
                final IconData ico = estado == 'presente' ? Icons.check_circle_rounded
                    : estado == 'tardanza' ? Icons.schedule_rounded : Icons.cancel_rounded;
                final txt = estado == 'presente' ? 'Presente'
                    : estado == 'tardanza' ? 'Tardanza' : 'Ausente';
                final h = r['hora_registro']?.toString();
                final hora = (h != null && h.length >= 16) ? h.substring(11, 16) : '';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Icon(ico, color: c, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text((r['fecha'] ?? '').toString(),
                      style: TextStyle(color: C.tinta, fontSize: 12))),
                    if (hora.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(hora, style: TextStyle(
                          color: C.tinta.withOpacity(0.45), fontSize: 11))),
                    Text(txt, style: TextStyle(color: c, fontSize: 12,
                      fontWeight: FontWeight.w700)),
                  ]),
                );
              }),
          ],
        ),
      ),
    );
  }
}
