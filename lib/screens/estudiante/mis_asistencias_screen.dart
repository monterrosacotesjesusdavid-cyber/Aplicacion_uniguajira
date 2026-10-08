import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/ui_kit.dart';
import 'asistencias_clase_screen.dart';

/// Pestaña "Asistencias" del estudiante: resumen general y porcentaje por materia.
/// Al tocar una materia se abre el detalle día por día.
class MisAsistenciasScreen extends StatefulWidget {
  const MisAsistenciasScreen({super.key});
  @override
  State<MisAsistenciasScreen> createState() => _MisAsistState();
}

class _MisAsistState extends State<MisAsistenciasScreen> {
  List _materias = [];
  bool _loading = true, _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    try {
      final l = await Api.misAsistenciasEstudiante();
      if (mounted) setState(() { _materias = l; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = _materias.isEmpty; });
    }
  }

  int _n(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;
  int _total(Map m) => _n(m, 'presentes') + _n(m, 'tardanzas') + _n(m, 'ausentes');
  int _pct(int pres, int tard, int total) =>
      total == 0 ? 0 : ((pres + tard) / total * 100).round();

  @override
  Widget build(BuildContext context) {
    if (_loading && _materias.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: C.verde));
    }
    int pres = 0, tard = 0, aus = 0;
    for (final m in _materias) {
      pres += _n(m, 'presentes');
      tard += _n(m, 'tardanzas');
      aus += _n(m, 'ausentes');
    }
    final total = pres + tard + aus;
    final pct = _pct(pres, tard, total);

    return RefreshIndicator(
      onRefresh: _load, color: C.verdeClaro, backgroundColor: C.sup,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          const TituloPantalla(
              titulo: 'Mis asistencias',
              sub: 'Toca una materia para ver el detalle'),
          const SizedBox(height: 16),
          if (_error)
            const EstadoVacio(
                icono: Icons.wifi_off_rounded,
                titulo: 'No se pudo cargar',
                mensaje: 'Revisa tu conexión y desliza hacia abajo para reintentar.')
          else if (_materias.isEmpty)
            const EstadoVacio(
                titulo: 'Sin materias',
                mensaje: 'Cuando te inscriban en materias aparecerán aquí.')
          else ...[
            _ResumenGeneral(pct: pct, pres: pres, tard: tard, aus: aus, total: total),
            const SizedBox(height: 20),
            const TituloSeccion('Por materia'),
            const SizedBox(height: 10),
            for (final m in _materias)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TarjetaMateria(
                  materia: m['materia'] as String? ?? '',
                  profesor: m['profesor'] as String? ?? '',
                  virtual: m['modalidad'] == 'virtual',
                  pres: _n(m, 'presentes'),
                  tard: _n(m, 'tardanzas'),
                  aus: _n(m, 'ausentes'),
                  pct: _pct(_n(m, 'presentes'), _n(m, 'tardanzas'), _total(m)),
                  total: _total(m),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => AsistenciasClaseScreen(
                          horarioId: (m['id'] as num).toInt(),
                          materia: m['materia'] as String? ?? ''))),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ResumenGeneral extends StatelessWidget {
  final int pct, pres, tard, aus, total;
  const _ResumenGeneral({required this.pct, required this.pres,
      required this.tard, required this.aus, required this.total});

  @override
  Widget build(BuildContext context) {
    final ok = total == 0 || pct >= 75;
    final col = ok ? C.verdeClaro : C.rojo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Row(children: [
            Text('Asistencia general', style: TextStyle(
                color: C.tinta, fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(total == 0 ? '—' : '$pct%', style: TextStyle(
                color: col, fontSize: 24, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : pct / 100, minHeight: 8,
              backgroundColor: C.borde, valueColor: AlwaysStoppedAnimation(col)),
          ),
          const SizedBox(height: 14),
          Row(children: [
            _Dato('Presentes', pres, C.verdeClaro),
            _Dato('Tardanzas', tard, C.naranja),
            _Dato('Ausentes', aus, C.rojo),
          ]),
          if (total > 0 && pct < 75) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: C.rojo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: C.rojo.withOpacity(0.25))),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: C.rojo, size: 16),
                const SizedBox(width: 8),
                const Expanded(child: Text(
                    'Tu asistencia general está por debajo del 75%',
                    style: TextStyle(color: C.rojo, fontSize: 12))),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  final String label; final int v; final Color c;
  const _Dato(this.label, this.v, this.c);
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
        Text('$v', style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label, style: TextStyle(color: C.suave, fontSize: 11)),
      ]));
}

class _TarjetaMateria extends StatelessWidget {
  final String materia, profesor;
  final bool virtual;
  final int pres, tard, aus, pct, total;
  final VoidCallback onTap;
  const _TarjetaMateria({required this.materia, required this.profesor,
      required this.virtual, required this.pres, required this.tard,
      required this.aus, required this.pct, required this.total,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bajo = total > 0 && pct < 75;
    final col = bajo ? C.rojo : C.verdeClaro;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(materia, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: C.tinta, fontSize: 15,
                      fontWeight: FontWeight.w700))),
              const SizedBox(width: 8),
              Text(total == 0 ? '—' : '$pct%', style: TextStyle(
                  color: col, fontSize: 18, fontWeight: FontWeight.w800)),
              Icon(Icons.chevron_right_rounded, color: C.suave),
            ]),
            const SizedBox(height: 2),
            Text('$profesor${virtual ? ' · Virtual' : ''}', maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: C.suave, fontSize: 12.5)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : pct / 100, minHeight: 6,
                backgroundColor: C.borde, valueColor: AlwaysStoppedAnimation(col)),
            ),
            const SizedBox(height: 10),
            Text(total == 0
                ? 'Aún no hay clases registradas'
                : '$pres presentes · $tard tardanzas · $aus ausentes',
                style: TextStyle(color: C.tinta70, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
