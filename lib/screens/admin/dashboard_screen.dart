import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/admin_ui.dart';
import '../../core/api.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onVerTodo;
  const DashboardScreen({super.key, this.onVerTodo});
  @override
  State<DashboardScreen> createState() => _DashState();
}

class _DashState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  List _recientes = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final hoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
      // La actividad reciente es opcional: si falla, el resumen igual se muestra.
      final fut = Api.asistenciasAdmin(fecha: hoy)
          .then<List>((v) => v, onError: (_) => <dynamic>[]);
      final d = await Api.dashboard();
      final r = await fut;
      if (!mounted) return;
      setState(() { _data = d; _recientes = r; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _data = null; _loading = false; });
    }
  }

  int _n(String k) => (_data?[k] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final clases = _n('total_clases_hoy');
    final pres = _n('presentes_hoy');
    final tard = _n('tardanzas_hoy');
    final aus = _n('ausentes_hoy');
    final profs = _n('total_profesores');
    final aTiempo = math.max(0, pres - tard);
    final pend = math.max(0, clases - pres - aus);

    return RefreshIndicator(
      onRefresh: _load, color: A.oro, backgroundColor: A.card1,
      child: _loading
        ? ListView(children: const [
            SizedBox(height: 200),
            Center(child: CircularProgressIndicator(color: A.oro)),
          ])
        : _data == null
          ? ListView(children: [
              SizedBox(height: 120, child: null),
              AdmVacio(Icons.cloud_off_rounded, 'No se pudo cargar el resumen',
                sub: 'Revisa tu conexión e inténtalo de nuevo.',
                accion: TextButton(onPressed: _load,
                  child: const Text('Reintentar',
                    style: TextStyle(color: A.oro, fontWeight: FontWeight.w700)))),
            ])
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Row(children: [
                  Expanded(child: _Metrica('Profesores', '$profs',
                    Icons.groups_rounded, A.tealClaro, 'activos')),
                  const SizedBox(width: 12),
                  Expanded(child: _Metrica('Presentes hoy', '$pres',
                    Icons.check_circle_rounded, A.ok, 'de $clases clases')),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _Metrica('Tardanzas hoy', '$tard',
                    Icons.schedule_rounded, A.warn, 'llegaron tarde')),
                  const SizedBox(width: 12),
                  Expanded(child: _Metrica('Ausentes hoy', '$aus',
                    Icons.cancel_rounded, A.mal, 'sin registro')),
                ]),
                const SizedBox(height: 14),
                _distribucion(clases, aTiempo, tard, aus, pend),
                const SizedBox(height: 14),
                _actividad(),
              ],
            ),
    );
  }

  Widget _distribucion(int clases, int aT, int tard, int aus, int pend) {
    Widget fila(Color c, String t, int n) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(width: 9, height: 9,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(t, style: const TextStyle(
          color: A.suave, fontSize: 12.5))),
        Text('$n', style: const TextStyle(color: A.texto,
          fontSize: 13.5, fontWeight: FontWeight.w800)),
        SizedBox(width: 44, child: Text(
          clases > 0 ? '${(n / clases * 100).round()}%' : '–',
          textAlign: TextAlign.right,
          style: const TextStyle(color: A.suave, fontSize: 11.5))),
      ]));

    return AdmCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Distribución de hoy', style: TextStyle(
          color: A.texto, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Row(children: [
          AdmDonut(
            valores: [aT.toDouble(), tard.toDouble(), aus.toDouble(), pend.toDouble()],
            colores: const [A.ok, A.warn, A.mal, A.gris],
            tam: 124, grosor: 15,
            centro: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$clases', style: const TextStyle(color: A.texto,
                fontSize: 26, fontWeight: FontWeight.w800, height: 1)),
              const SizedBox(height: 2),
              const Text('clases', style: TextStyle(
                color: A.suave, fontSize: 11)),
            ])),
          const SizedBox(width: 18),
          Expanded(child: Column(children: [
            fila(A.ok, 'A tiempo', aT),
            fila(A.warn, 'Tardanzas', tard),
            fila(A.mal, 'Ausentes', aus),
            fila(A.gris, 'Pendientes', pend),
          ])),
        ]),
      ]),
    );
  }

  Widget _actividad() {
    final items = _recientes.take(5).toList();
    return AdmCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Actividad de hoy', style: TextStyle(
            color: A.texto, fontSize: 15, fontWeight: FontWeight.w700))),
          if (widget.onVerTodo != null && _recientes.isNotEmpty)
            GestureDetector(
              onTap: widget.onVerTodo,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: A.borde)),
                child: const Text('Ver todo', style: TextStyle(
                  color: A.oroClaro, fontSize: 11.5, fontWeight: FontWeight.w700)))),
        ]),
        const SizedBox(height: 10),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: Text('Aún no hay registros hoy',
              style: TextStyle(color: A.suave, fontSize: 12.5))))
        else
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: A.borde),
            _FilaActividad(items[i]),
          ],
      ]),
    );
  }
}

class _Metrica extends StatelessWidget {
  final String label, value, sub;
  final IconData icono;
  final Color color;
  const _Metrica(this.label, this.value, this.icono, this.color, this.sub);

  @override
  Widget build(BuildContext context) => AdmCard(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AdmIcono(icono, color, tam: 40),
      const SizedBox(height: 14),
      Text(value, style: const TextStyle(color: A.texto, fontSize: 30,
        fontWeight: FontWeight.w800, height: 1)),
      const SizedBox(height: 5),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: A.suave, fontSize: 12.5)),
      const SizedBox(height: 6),
      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 11.5,
          fontWeight: FontWeight.w600)),
    ]),
  );
}

class _FilaActividad extends StatelessWidget {
  final Map a;
  const _FilaActividad(this.a);

  @override
  Widget build(BuildContext context) {
    final e = admEstado((a['estado'] ?? '').toString());
    final hora = admHora(a['hora_registro']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(children: [
        AdmIcono(e.icono, e.color, tam: 38),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((a['profesor_nombre'] ?? '').toString(),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: A.texto, fontSize: 13,
              fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text((a['materia'] ?? '').toString(),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: A.oroClaro, fontSize: 11.5)),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          AdmPill(e.texto, e.color, size: 10),
          if (hora.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(hora, style: const TextStyle(color: A.suave, fontSize: 10.5)),
          ],
        ]),
      ]),
    );
  }
}
