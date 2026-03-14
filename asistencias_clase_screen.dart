import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/api.dart';

class AsistenciasClaseScreen extends StatefulWidget {
  final int horarioId;
  final String materia;
  const AsistenciasClaseScreen(
      {super.key, required this.horarioId, required this.materia});
  @override
  State<AsistenciasClaseScreen> createState() => _AsistClaseState();
}

class _AsistClaseState extends State<AsistenciasClaseScreen> {
  List _asistencias = [];
  bool _loading = true;
  Map<String, int>? _resumen;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await Api.asistenciasClase(widget.horarioId);
      int presentes = 0, ausentes = 0, tardanzas = 0;
      for (final a in list) {
        if (a['estado'] == 'presente') presentes++;
        else if (a['estado'] == 'tardanza') tardanzas++;
        else ausentes++;
      }
      setState(() {
        _asistencias = list;
        _resumen = {'presentes': presentes, 'tardanzas': tardanzas,
          'ausentes': ausentes, 'total': list.length};
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final pct = _resumen != null && (_resumen!['total'] ?? 0) > 0
      ? ((_resumen!['presentes']! + _resumen!['tardanzas']!) /
          _resumen!['total']! * 100).round()
      : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.materia, overflow: TextOverflow.ellipsis),
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
                // Resumen
                if (_resumen != null) ...[
                  Card(child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Mi asistencia', style: TextStyle(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: pct >= 75 ? C.verde.withOpacity(0.15)
                              : C.rojo.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20)),
                          child: Text('$pct%', style: TextStyle(
                            color: pct >= 75 ? C.verdeClaro : C.rojo,
                            fontSize: 18, fontWeight: FontWeight.w800)),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      // Barra de progreso
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: pct / 100,
                          backgroundColor: C.borde,
                          valueColor: AlwaysStoppedAnimation(
                            pct >= 75 ? C.verdeClaro : C.rojo),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        _ResumenItem('Presentes', _resumen!['presentes']!, C.verdeClaro),
                        _ResumenItem('Tardanzas', _resumen!['tardanzas']!, C.naranja),
                        _ResumenItem('Ausentes',  _resumen!['ausentes']!,  C.rojo),
                        _ResumenItem('Total',     _resumen!['total']!,     C.suave),
                      ]),
                      const SizedBox(height: 10),
                      if (pct < 75)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: C.rojo.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: C.rojo.withOpacity(0.25))),
                          child: Row(children: [
                            const Icon(Icons.warning_amber_rounded, color: C.rojo, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(
                              'Tu asistencia está por debajo del 75% mínimo requerido',
                              style: TextStyle(color: C.rojo.withOpacity(0.9), fontSize: 11))),
                          ]),
                        ),
                    ]),
                  )),
                  const SizedBox(height: 16),
                ],

                const Text('Registro de clases',
                  style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),

                if (_asistencias.isEmpty)
                  Card(child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Center(child: Text('Sin registros de asistencia',
                      style: TextStyle(color: Colors.white.withOpacity(0.5)))),
                  ))
                else
                  ..._asistencias.map((a) {
                    final estado = a['estado'] as String? ?? 'ausente';
                    Color col; IconData ico; Color bg;
                    if (estado == 'presente')  { col = C.verdeClaro; ico = Icons.check_circle_rounded; bg = C.verde.withOpacity(0.1); }
                    else if (estado == 'tardanza') { col = C.naranja; ico = Icons.schedule_rounded; bg = C.naranja.withOpacity(0.1); }
                    else { col = C.rojo; ico = Icons.cancel_rounded; bg = C.rojo.withOpacity(0.1); }
                    final fecha = a['fecha'] as String? ?? '';
                    final hora  = (a['hora_registro'] as String?)?.substring(11, 16) ?? '--:--';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          Container(width: 38, height: 38,
                            decoration: BoxDecoration(color: bg,
                              borderRadius: BorderRadius.circular(10)),
                            child: Icon(ico, color: col, size: 20)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(fecha, style: const TextStyle(
                              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                            Text('Registrado a las $hora',
                              style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11)),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: bg,
                              borderRadius: BorderRadius.circular(20)),
                            child: Text(
                              estado == 'presente' ? 'Presente'
                                : estado == 'tardanza' ? 'Tardanza' : 'Ausente',
                              style: TextStyle(color: col, fontSize: 11,
                                fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      )),
                    );
                  }),
              ],
            ),
          ),
    );
  }
}

class _ResumenItem extends StatelessWidget {
  final String label; final int val; final Color color;
  const _ResumenItem(this.label, this.val, this.color);
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text('$val', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
    Text(label, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 10)),
  ]));
}
