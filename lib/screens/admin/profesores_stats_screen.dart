import 'package:flutter/material.dart';
import '../../core/admin_ui.dart';
import '../../core/api.dart';
import 'detalle_profesor_screen.dart';

class ProfesoresStatsScreen extends StatefulWidget {
  const ProfesoresStatsScreen({super.key});
  @override
  State<ProfesoresStatsScreen> createState() => _ProfStatsState();
}

class _ProfStatsState extends State<ProfesoresStatsScreen> {
  List _profs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hayMas = true;
  int _page = 1;
  int _total = 0;
  String _busqueda = '';
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() { _scroll.dispose(); _searchCtrl.dispose(); super.dispose(); }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200
        && !_loadingMore && _hayMas) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() { _loading = true; _page = 1; _profs = []; _hayMas = true; });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final r = await Api.estadisticasProfesores(
        busqueda: _busqueda, page: reset ? 1 : _page);
      final list = (r['profesores'] as List?) ?? [];
      final total = r['total'] as int? ?? 0;
      if (!mounted) return;
      setState(() {
        if (reset) {
          _profs = list;
          _page = 2;
        } else {
          _profs.addAll(list);
          _page++;
        }
        _total = total;
        _hayMas = _profs.length < total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadingMore = false; });
    }
  }

  void _buscar(String v) {
    _busqueda = v;
    _load(reset: true);
  }

  Widget _leyenda(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(t, style: const TextStyle(color: A.suave, fontSize: 11)),
  ]);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        child: TextField(
          controller: _searchCtrl,
          onChanged: _buscar,
          style: const TextStyle(color: A.texto),
          decoration: InputDecoration(
            hintText: 'Buscar por nombre o cédula...',
            prefixIcon: const Icon(Icons.search_rounded, color: A.suave, size: 20),
            suffixIcon: _busqueda.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, color: A.suave, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    _buscar('');
                  })
              : null,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
        child: Row(children: [
          Text(_loading ? ' ' : '$_total profesores',
            style: const TextStyle(color: A.suave, fontSize: 12)),
          const Spacer(),
          _leyenda(A.ok, 'A tiempo'), const SizedBox(width: 10),
          _leyenda(A.warn, 'Tarde'), const SizedBox(width: 10),
          _leyenda(A.mal, 'Ausente'),
        ]),
      ),
      Expanded(
        child: _loading
          ? const Center(child: CircularProgressIndicator(color: A.oro))
          : _profs.isEmpty
            ? AdmVacio(Icons.search_off_rounded,
                _busqueda.isEmpty ? 'Sin profesores' : 'Sin resultados',
                sub: _busqueda.isEmpty ? null : 'No hay coincidencias para "$_busqueda"')
            : ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                itemCount: _profs.length + (_loadingMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  if (i == _profs.length) {
                    return const Center(child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        color: A.oro, strokeWidth: 2)));
                  }
                  final p = _profs[i];
                  final aT = p['a_tiempo'] as int? ?? 0;
                  final tard = p['tardanzas'] as int? ?? 0;
                  final aus = p['ausencias'] as int? ?? 0;
                  final total = aT + tard + aus;
                  final pct = total > 0 ? ((aT + tard) / total * 100).round() : 0;
                  final pctColor = pct >= 80 ? A.ok : pct >= 60 ? A.warn : A.mal;
                  final nombre = (p['nombre'] as String?) ?? '';

                  return AdmCard(
                    padding: const EdgeInsets.all(14),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => DetalleProfesorScreen(
                        profesorId: p['id'], nombre: nombre))),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle, gradient: A.gradOro),
                        child: CircleAvatar(
                          radius: 22, backgroundColor: A.card2,
                          child: Text(
                            nombre.isEmpty ? '?' : nombre[0].toUpperCase(),
                            style: const TextStyle(color: A.oroClaro,
                              fontSize: 17, fontWeight: FontWeight.w800)))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: A.texto,
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('CC ${p['cedula']}',
                          style: const TextStyle(color: A.suave, fontSize: 11.5)),
                        const SizedBox(height: 9),
                        AdmBarra(pct / 100, pctColor),
                      ])),
                      const SizedBox(width: 14),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('$pct%', style: TextStyle(color: pctColor,
                          fontSize: 21, fontWeight: FontWeight.w800, height: 1)),
                        const SizedBox(height: 2),
                        const Text('asistencia', style: TextStyle(
                          color: A.suave, fontSize: 10)),
                        const SizedBox(height: 6),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          _Mini('$aT', A.ok),
                          const SizedBox(width: 4),
                          _Mini('$tard', A.warn),
                          const SizedBox(width: 4),
                          _Mini('$aus', A.mal),
                        ]),
                      ]),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right_rounded,
                        color: A.suave, size: 20),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}

class _Mini extends StatelessWidget {
  final String val;
  final Color color;
  const _Mini(this.val, this.color);

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 24),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.28))),
    child: Text(val, textAlign: TextAlign.center, style: TextStyle(
      color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
  );
}
