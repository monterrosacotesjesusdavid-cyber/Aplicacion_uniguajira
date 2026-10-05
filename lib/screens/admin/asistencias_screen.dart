import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../profesor/lista_virtual_screen.dart';

class AdminAsistenciasScreen extends StatefulWidget {
  const AdminAsistenciasScreen({super.key});
  @override
  State<AdminAsistenciasScreen> createState() => _AdminAsistState();
}

class _AdminAsistState extends State<AdminAsistenciasScreen> {
  List _lista = [];
  bool _loading = true;
  String? _fecha;

  @override
  void initState() {
    super.initState();
    _fecha = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await Api.asistenciasAdmin(fecha: _fecha);
      setState(() { _lista = list; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _pickFecha() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fecha != null ? DateTime.parse(_fecha!) : DateTime.now(),
      firstDate: DateTime(2024), lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: C.verde, surface: C.sup)),
        child: child!),
    );
    if (d != null) {
      setState(() => _fecha = DateFormat('yyyy-MM-dd').format(d));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Filtro fecha
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: GestureDetector(
          onTap: _pickFecha,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: C.sup2, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: C.borde)),
            child: Row(children: [
              Icon(Icons.calendar_today_rounded, color: C.suave, size: 18),
              const SizedBox(width: 10),
              Text(
                _fecha != null
                  ? DateFormat("EEEE d 'de' MMMM yyyy", 'es_CO')
                      .format(DateTime.parse(_fecha!))
                  : 'Seleccionar fecha',
                style: TextStyle(color: C.tinta, fontSize: 13)),
              const Spacer(),
              Icon(Icons.arrow_drop_down_rounded, color: C.suave),
            ]),
          ),
        ),
      ),

      // Contador
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Text('${_lista.length} registros',
            style: TextStyle(color: C.tinta.withOpacity(0.4), fontSize: 12)),
        ]),
      ),

      // Lista
      Expanded(
        child: _loading
          ? const Center(child: CircularProgressIndicator(color: C.verde))
          : _lista.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.assignment_outlined, size: 48, color: C.suave),
                const SizedBox(height: 12),
                Text('Sin registros para esta fecha',
                  style: TextStyle(color: C.tinta)),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _pickFecha,
                  child: Text('Cambiar fecha',
                    style: TextStyle(color: C.verdeClaro))),
              ]))
            : RefreshIndicator(
                onRefresh: _load, color: C.verdeClaro, backgroundColor: C.sup,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: _lista.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final a = _lista[i];
                    final virtual = a['modalidad'] == 'virtual';
                    final estado = a['estado'] as String? ?? '';
                    Color col, bg; IconData ico;
                    switch (estado) {
                      case 'a_tiempo': col = C.verdeClaro; bg = C.verde.withOpacity(0.1);
                        ico = Icons.check_circle_rounded; break;
                      case 'tardanza': col = C.naranja; bg = C.naranja.withOpacity(0.1);
                        ico = Icons.schedule_rounded; break;
                      default: col = C.rojo; bg = C.rojo.withOpacity(0.1);
                        ico = Icons.cancel_rounded;
                    }
                    final tarjeta = Card(child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(width: 40, height: 40,
                          decoration: BoxDecoration(color: bg,
                            borderRadius: BorderRadius.circular(8)),
                          child: Icon(ico, color: col, size: 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a['profesor_nombre'] ?? '', style: TextStyle(
                            color: C.tinta, fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(a['materia'] ?? '',
                            style: TextStyle(color: C.doradoClaro, fontSize: 12)),
                          Text('${(a['hora_registro'] as String?)?.substring(11, 16) ?? ''}  •  ${virtual ? 'Virtual • toca para ver la lista' : (a['salon'] ?? '')}',
                            style: TextStyle(color: C.tinta.withOpacity(0.4),
                              fontSize: 11)),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: bg,
                              borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              estado == 'a_tiempo' ? 'A tiempo'
                                : estado == 'tardanza' ? 'Tardanza' : 'Ausente',
                              style: TextStyle(color: col, fontSize: 11,
                                fontWeight: FontWeight.w700))),
                          if ((a['minutos_tarde'] as int? ?? 0) > 0) ...[
                            const SizedBox(height: 3),
                            Text('+${a['minutos_tarde']}min',
                              style: TextStyle(color: C.tinta.withOpacity(0.35),
                                fontSize: 10)),
                          ],
                        ]),
                      ]),
                    ));
                    if (!virtual) return tarjeta;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ListaVirtualScreen(
                          horarioId: a['horario_id'],
                          materia: (a['materia'] ?? '').toString(),
                          admin: true,
                          fecha: _fecha))),
                      child: tarjeta,
                    );
                  },
                ),
              ),
      ),
    ]);
  }
}
