import 'package:flutter/material.dart';
import '../../core/theme.dart';
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
      setState(() {
        if (reset) {
          _profs = list;
          _page = 2;
        } else {
          _profs.addAll(list);
          _page++;
        }
        _hayMas = _profs.length < total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      setState(() { _loading = false; _loadingMore = false; });
    }
  }

  void _buscar(String v) {
    _busqueda = v;
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Búsqueda
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          controller: _searchCtrl,
          onChanged: _buscar,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Buscar por nombre o cédula...',
            prefixIcon: const Icon(Icons.search, color: C.suave, size: 20),
            suffixIcon: _busqueda.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: C.suave, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    _buscar('');
                  })
              : null,
          ),
        ),
      ),

      // Lista
      Expanded(
        child: _loading
          ? const Center(child: CircularProgressIndicator(color: C.verde))
          : _profs.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.search_off_rounded, size: 48, color: C.suave),
                const SizedBox(height: 12),
                Text(_busqueda.isEmpty ? 'Sin profesores' : 'Sin resultados para "$_busqueda"',
                  style: const TextStyle(color: Colors.white)),
              ]))
            : ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: _profs.length + (_loadingMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  if (i == _profs.length) {
                    return const Center(child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(color: C.verde, strokeWidth: 2)));
                  }
                  final p = _profs[i];
                  final aT = p['a_tiempo'] as int? ?? 0;
                  final tard = p['tardanzas'] as int? ?? 0;
                  final aus = p['ausencias'] as int? ?? 0;
                  final total = aT + tard + aus;
                  final pct = total > 0 ? ((aT + tard) / total * 100).round() : 0;
                  Color pctColor;
                  if (pct >= 80)      pctColor = C.verdeClaro;
                  else if (pct >= 60) pctColor = C.naranja;
                  else                pctColor = C.rojo;

                  return Card(child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => DetalleProfesorScreen(
                        profesorId: p['id'], nombre: p['nombre']))),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: C.verde.withOpacity(0.15),
                          child: Text(
                            (p['nombre'] as String? ?? 'X')[0].toUpperCase(),
                            style: const TextStyle(color: C.verdeClaro,
                              fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p['nombre'] ?? '', style: const TextStyle(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          Text('CC ${p['cedula']}',
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                          const SizedBox(height: 6),
                          // Mini barra
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct / 100,
                              backgroundColor: C.borde,
                              valueColor: AlwaysStoppedAnimation(pctColor),
                              minHeight: 4,
                            )),
                        ])),
                        const SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('$pct%', style: TextStyle(
                            color: pctColor, fontSize: 20, fontWeight: FontWeight.w800)),
                          Text('asistencia', style: TextStyle(
                            color: Colors.white.withOpacity(0.4), fontSize: 10)),
                          const SizedBox(height: 4),
                          Row(children: [
                            _Mini('$aT', C.verdeClaro),
                            const SizedBox(width: 4),
                            _Mini('$tard', C.naranja),
                            const SizedBox(width: 4),
                            _Mini('$aus', C.rojo),
                          ]),
                        ]),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded, color: C.suave, size: 18),
                      ]),
                    ),
                  ));
                },
              ),
      ),
    ]);
  }
}

class _Mini extends StatelessWidget {
  final String val; final Color color;
  const _Mini(this.val, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
    child: Text(val, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
  );
}
