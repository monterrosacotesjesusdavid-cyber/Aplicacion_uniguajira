import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/admin_ui.dart';
import '../../core/api.dart';

class DetalleProfesorScreen extends StatefulWidget {
  final int profesorId;
  final String nombre;
  const DetalleProfesorScreen(
      {super.key, required this.profesorId, required this.nombre});
  @override
  State<DetalleProfesorScreen> createState() => _DetState();
}

class _DetState extends State<DetalleProfesorScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await Api.detalleProfesor(widget.profesorId);
      if (!mounted) return;
      setState(() { _data = d; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inicial = widget.nombre.isEmpty ? '?' : widget.nombre[0].toUpperCase();
    return Theme(
      data: admTheme(),
      child: Scaffold(
        backgroundColor: A.bg,
        appBar: AppBar(
          backgroundColor: A.bg, foregroundColor: A.texto, elevation: 0,
          scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent),
          titleSpacing: 0,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Center(child: AdmBotonIcono(
              Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)))),
          leadingWidth: 56,
          title: Text(widget.nombre, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: A.texto, fontSize: 17,
              fontWeight: FontWeight.w700)),
        ),
        body: _loading
          ? const Center(child: CircularProgressIndicator(color: A.oro))
          : RefreshIndicator(
              onRefresh: _load, color: A.oro, backgroundColor: A.card1,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (_data == null)
                    const Padding(padding: EdgeInsets.only(top: 80),
                      child: AdmVacio(Icons.cloud_off_rounded,
                        'No se pudo cargar',
                        sub: 'Desliza hacia abajo para reintentar.'))
                  else ...[
                    _perfil(inicial),
                    const SizedBox(height: 14),
                    _buildStats(),
                    const SizedBox(height: 22),
                    const Text('Historial de asistencias', style: TextStyle(
                      color: A.texto, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    ..._buildHistorial(),
                  ],
                ],
              ),
            ),
      ),
    );
  }

  Widget _perfil(String inicial) => AdmCard(
    padding: const EdgeInsets.all(18),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(
          shape: BoxShape.circle, gradient: A.gradOro),
        child: CircleAvatar(
          radius: 30, backgroundColor: A.card2,
          child: Text(inicial, style: const TextStyle(color: A.oroClaro,
            fontSize: 24, fontWeight: FontWeight.w800)))),
      const SizedBox(width: 16),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.nombre, style: const TextStyle(color: A.texto,
          fontSize: 16.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('CC ${_data!['cedula'] ?? ''}',
          style: const TextStyle(color: A.oroClaro, fontSize: 12.5,
            fontWeight: FontWeight.w600)),
        if ((_data!['correo'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(_data!['correo'].toString(), maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: A.suave, fontSize: 11.5)),
        ],
      ])),
    ]),
  );

  Widget _buildStats() {
    final stats = _data!['estadisticas'] as Map<String, dynamic>? ?? {};
    final aT   = (stats['a_tiempo']  as int?) ?? 0;
    final tard = (stats['tardanzas'] as int?) ?? 0;
    final aus  = (stats['ausencias'] as int?) ?? 0;
    final total = aT + tard + aus;
    final pct = total > 0 ? ((aT + tard) / total * 100).round() : 0;
    final pctColor = pct >= 80 ? A.ok : pct >= 60 ? A.warn : A.mal;

    return AdmCard(
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        Row(children: [
          AdmRing(
            valor: pct / 100, tam: 104, grosor: 11,
            color: pctColor, pista: Colors.white.withOpacity(0.08),
            centro: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$pct%', style: TextStyle(color: pctColor, fontSize: 24,
                fontWeight: FontWeight.w800, height: 1)),
              const SizedBox(height: 2),
              const Text('asistencia', style: TextStyle(
                color: A.suave, fontSize: 10)),
            ])),
          const SizedBox(width: 20),
          Expanded(child: Column(children: [
            _StatFila('A tiempo', aT, A.ok),
            _StatFila('Tardanzas', tard, A.warn),
            _StatFila('Ausencias', aus, A.mal),
            const Divider(color: A.borde, height: 14),
            _StatFila('Total clases', total, A.suave),
          ])),
        ]),
        if (pct < 75 && total > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: A.mal.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: A.mal.withOpacity(0.28))),
            child: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: A.mal, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Asistencia por debajo del 75% mínimo',
                style: TextStyle(color: A.mal, fontSize: 12,
                  fontWeight: FontWeight.w600))),
            ])),
        ],
      ]),
    );
  }

  List<Widget> _buildHistorial() {
    final hist = (_data!['historial'] as List?) ?? [];
    if (hist.isEmpty) {
      return const [AdmVacio(Icons.history_rounded, 'Sin registros')];
    }

    return hist.map<Widget>((a) {
      final e = admEstado((a['estado'] ?? 'ausente').toString());
      final hora = admHora(a['hora_registro']);
      final partes = <String>[
        (a['fecha'] ?? '').toString(),
        if (hora.isNotEmpty) hora,
        if ((a['salon'] ?? '').toString().isNotEmpty) a['salon'].toString(),
      ].where((s) => s.isNotEmpty).toList();
      final etiqueta = a['estado'] == 'tardanza'
          ? '+${a['minutos_tarde']} min' : e.texto;

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AdmCard(
          padding: const EdgeInsets.all(13),
          child: Row(children: [
            AdmIcono(e.icono, e.color, tam: 40),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((a['materia'] ?? '').toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: A.texto, fontSize: 13.5,
                  fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(partes.join('  ·  '), maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: A.suave, fontSize: 11.5)),
            ])),
            const SizedBox(width: 8),
            AdmPill(etiqueta, e.color, size: 10.5),
          ]),
        ),
      );
    }).toList();
  }
}

class _StatFila extends StatelessWidget {
  final String label;
  final int val;
  final Color color;
  const _StatFila(this.label, this.val, this.color);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Container(width: 8, height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: const TextStyle(
        color: A.suave, fontSize: 12.5))),
      Text('$val', style: const TextStyle(color: A.texto,
        fontSize: 14, fontWeight: FontWeight.w800)),
    ]),
  );
}
