import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/admin_ui.dart';
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

  DateTime get _hoy {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool get _esHoy => _fecha != null && DateTime.parse(_fecha!) == _hoy;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await Api.asistenciasAdmin(fecha: _fecha);
      if (!mounted) return;
      setState(() { _lista = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _mover(int dias) {
    final d = DateTime.parse(_fecha!);
    final nueva = DateTime(d.year, d.month, d.day + dias);
    if (nueva.isAfter(_hoy)) return;
    setState(() => _fecha = DateFormat('yyyy-MM-dd').format(nueva));
    _load();
  }

  Future<void> _pickFecha() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fecha != null ? DateTime.parse(_fecha!) : DateTime.now(),
      firstDate: DateTime(2024), lastDate: DateTime.now(),
    );
    if (d != null) {
      setState(() => _fecha = DateFormat('yyyy-MM-dd').format(d));
      _load();
    }
  }

  Widget _flecha(IconData i, bool activa, VoidCallback onTap) => Material(
    color: A.card1, borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: activa ? onTap : null,
      child: Container(width: 46, height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: A.borde)),
        child: Icon(i, color: activa ? A.texto : A.suave.withOpacity(0.35)))));

  @override
  Widget build(BuildContext context) {
    final aT = _lista.where((a) => a['estado'] == 'a_tiempo').length;
    final tard = _lista.where((a) => a['estado'] == 'tardanza').length;
    final aus = _lista.length - aT - tard;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [
          _flecha(Icons.chevron_left_rounded, true, () => _mover(-1)),
          const SizedBox(width: 8),
          Expanded(child: GestureDetector(
            onTap: _pickFecha,
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                gradient: A.gradCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: A.borde)),
              child: Row(children: [
                const Icon(Icons.calendar_month_rounded, color: A.oro, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  _fecha != null
                    ? admTitulo(DateFormat("EEEE d 'de' MMMM", 'es_CO')
                        .format(DateTime.parse(_fecha!)))
                        .replaceAll(' De ', ' de ')
                    : 'Seleccionar fecha',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: A.texto, fontSize: 13.5,
                    fontWeight: FontWeight.w600))),
                if (_esHoy) const AdmPill('Hoy', A.oro, size: 10),
              ]),
            ),
          )),
          const SizedBox(width: 8),
          _flecha(Icons.chevron_right_rounded, !_esHoy, () => _mover(1)),
        ]),
      ),

      if (!_loading && _lista.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(child: _Resumen('A tiempo', aT, A.ok)),
            const SizedBox(width: 10),
            Expanded(child: _Resumen('Tardanzas', tard, A.warn)),
            const SizedBox(width: 10),
            Expanded(child: _Resumen('Ausentes', aus, A.mal)),
          ]),
        ),

      Expanded(
        child: _loading
          ? const Center(child: CircularProgressIndicator(color: A.oro))
          : _lista.isEmpty
            ? AdmVacio(Icons.event_busy_rounded, 'Sin registros para esta fecha',
                accion: TextButton(
                  onPressed: _pickFecha,
                  child: const Text('Cambiar fecha', style: TextStyle(
                    color: A.oro, fontWeight: FontWeight.w700))))
            : RefreshIndicator(
                onRefresh: _load, color: A.oro, backgroundColor: A.card1,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                  itemCount: _lista.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final a = _lista[i];
                    final virtual = a['modalidad'] == 'virtual';
                    final e = admEstado((a['estado'] ?? '').toString());
                    final hora = admHora(a['hora_registro']);
                    final tarde = (a['minutos_tarde'] as int? ?? 0);
                    final partes = <String>[
                      if (hora.isNotEmpty) hora,
                      if (virtual) 'Toca para ver la lista'
                      else if ((a['salon'] ?? '').toString().isNotEmpty)
                        a['salon'].toString(),
                    ];
                    return AdmCard(
                      padding: const EdgeInsets.all(14),
                      onTap: !virtual ? null : () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ListaVirtualScreen(
                          horarioId: a['horario_id'],
                          materia: (a['materia'] ?? '').toString(),
                          admin: true,
                          fecha: _fecha))),
                      child: Row(children: [
                        AdmIcono(e.icono, e.color, tam: 42),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text((a['profesor_nombre'] ?? '').toString(),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: A.texto, fontSize: 13.5,
                              fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text((a['materia'] ?? '').toString(),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: A.oroClaro, fontSize: 12)),
                          if (partes.isNotEmpty || virtual) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              if (virtual) ...[
                                const Icon(Icons.videocam_rounded,
                                  size: 13, color: A.azul),
                                const SizedBox(width: 4),
                              ],
                              Expanded(child: Text(partes.join('  ·  '),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: A.suave, fontSize: 11.5))),
                            ]),
                          ],
                        ])),
                        const SizedBox(width: 8),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          AdmPill(e.texto, e.color, size: 10.5),
                          if (tarde > 0) ...[
                            const SizedBox(height: 4),
                            Text('+$tarde min', style: const TextStyle(
                              color: A.suave, fontSize: 10.5)),
                          ],
                        ]),
                        if (virtual) ...[
                          const SizedBox(width: 2),
                          const Icon(Icons.chevron_right_rounded,
                            color: A.suave, size: 20),
                        ],
                      ]),
                    );
                  },
                ),
              ),
      ),
    ]);
  }
}

class _Resumen extends StatelessWidget {
  final String label;
  final int n;
  final Color color;
  const _Resumen(this.label, this.n, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(0.25))),
    child: Column(children: [
      Text('$n', style: TextStyle(color: color, fontSize: 20,
        fontWeight: FontWeight.w800, height: 1)),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(color: A.suave, fontSize: 10.5)),
    ]),
  );
}
