import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/ui_kit.dart';

/// Pestaña "Historial" del profesor: sus firmas por clase (a tiempo, tardanza o
/// ausente), con filtro por mes y por materia.
class HistorialProfesorScreen extends StatefulWidget {
  const HistorialProfesorScreen({super.key});
  @override
  State<HistorialProfesorScreen> createState() => _HistProfState();
}

class _HistProfState extends State<HistorialProfesorScreen> {
  List _todo = [];
  bool _loading = true, _error = false;
  String? _mes;      // 'YYYY-MM' o null = todos
  String? _materia;  // nombre o null = todas

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    try {
      final l = await Api.historialProfesor();
      if (mounted) setState(() { _todo = l; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = _todo.isEmpty; });
    }
  }

  String _mesDe(Map r) => ((r['fecha'] as String?) ?? '').padRight(7).substring(0, 7).trim();

  List get _filtrado => _todo.where((r) {
        if (_mes != null && _mesDe(r) != _mes) return false;
        if (_materia != null && r['materia'] != _materia) return false;
        return true;
      }).toList();

  @override
  Widget build(BuildContext context) {
    if (_loading && _todo.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: C.verde));
    }
    final meses = <String>[];
    final materias = <String>[];
    for (final r in _todo) {
      final m = _mesDe(r);
      if (m.length == 7 && !meses.contains(m)) meses.add(m);
      final mat = r['materia'] as String? ?? '';
      if (mat.isNotEmpty && !materias.contains(mat)) materias.add(mat);
    }
    materias.sort();

    final lista = _filtrado;
    int aTiempo = 0, tarde = 0, aus = 0;
    for (final r in lista) {
      final e = r['estado'];
      if (e == 'a_tiempo') aTiempo++;
      else if (e == 'tardanza') tarde++;
      else aus++;
    }
    final total = aTiempo + tarde + aus;
    final pct = total == 0 ? 0 : ((aTiempo + tarde) / total * 100).round();

    final filas = <Widget>[];
    String? fechaActual;
    for (final r in lista) {
      final f = r['fecha'] as String? ?? '';
      if (f != fechaActual) {
        fechaActual = f;
        filas.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: TituloSeccion(_fechaCorta(f)),
        ));
      }
      filas.add(Padding(
          padding: const EdgeInsets.only(bottom: 8), child: _FilaClase(r)));
    }

    return RefreshIndicator(
      onRefresh: _load, color: C.verdeClaro, backgroundColor: C.sup,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          const TituloPantalla(
              titulo: 'Historial', sub: 'Tus firmas de los últimos 90 días'),
          const SizedBox(height: 14),
          if (_error)
            const EstadoVacio(
                icono: Icons.wifi_off_rounded,
                titulo: 'No se pudo cargar',
                mensaje: 'Revisa tu conexión y desliza hacia abajo para reintentar.')
          else if (_todo.isEmpty)
            const EstadoVacio(
                titulo: 'Aún no hay clases registradas',
                mensaje: 'Tus firmas aparecerán aquí después de tu primera clase.')
          else ...[
            if (meses.length > 1)
              _Chips(
                opciones: {for (final m in meses) m: _mesLargo(m)},
                valor: _mes,
                todos: 'Todos los meses',
                onChanged: (v) => setState(() => _mes = v)),
            if (materias.length > 1) ...[
              const SizedBox(height: 8),
              _Chips(
                  opciones: {for (final m in materias) m: m},
                  valor: _materia,
                  todos: 'Todas las materias',
                  onChanged: (v) => setState(() => _materia = v)),
            ],
            const SizedBox(height: 14),
            _Resumen(pct: pct, aTiempo: aTiempo, tarde: tarde, aus: aus, total: total),
            if (lista.isEmpty)
              const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: EstadoVacio(
                      titulo: 'Sin resultados',
                      mensaje: 'No hay clases con ese filtro.'))
            else
              ...filas,
          ],
        ],
      ),
    );
  }
}

String _cap(String t) => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);

String _mesLargo(String ym) {
  final d = DateTime.tryParse('$ym-01');
  return d == null ? ym : _cap(DateFormat('MMMM y', 'es_CO').format(d));
}

String _fechaCorta(String f) {
  final d = DateTime.tryParse(f);
  return d == null ? f : _cap(DateFormat("EEEE d 'de' MMMM", 'es_CO').format(d));
}

class _Chips extends StatelessWidget {
  final Map<String, String> opciones; // valor -> etiqueta
  final String? valor;
  final String todos;
  final ValueChanged<String?> onChanged;
  const _Chips({required this.opciones, required this.valor,
      required this.todos, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String etiqueta, bool sel, VoidCallback f) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(etiqueta, style: TextStyle(
                fontSize: 12.5,
                color: sel ? Colors.white : C.tinta70)),
            selected: sel,
            showCheckmark: false,
            selectedColor: C.verde,
            backgroundColor: C.sup,
            side: BorderSide(color: sel ? C.verde : C.borde),
            onSelected: (_) => f(),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip(todos, valor == null, () => onChanged(null)),
        for (final e in opciones.entries)
          chip(e.value, valor == e.key, () => onChanged(e.key)),
      ]),
    );
  }
}

class _Resumen extends StatelessWidget {
  final int pct, aTiempo, tarde, aus, total;
  const _Resumen({required this.pct, required this.aTiempo, required this.tarde,
      required this.aus, required this.total});

  Widget _d(String l, int v, Color c) => Expanded(child: Column(children: [
        Text('$v', style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w800)),
        Text(l, style: TextStyle(color: C.suave, fontSize: 11)),
      ]));

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              Text('Cumplimiento', style: TextStyle(
                  color: C.tinta, fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(total == 0 ? '—' : '$pct%', style: TextStyle(
                  color: pct >= 90 || total == 0 ? C.verdeClaro : C.naranja,
                  fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _d('A tiempo', aTiempo, C.verdeClaro),
              _d('Tardanzas', tarde, C.naranja),
              _d('Ausentes', aus, C.rojo),
            ]),
          ]),
        ),
      );
}

class _FilaClase extends StatelessWidget {
  final Map r;
  const _FilaClase(this.r);

  @override
  Widget build(BuildContext context) {
    final estado = r['estado'] as String? ?? 'ausente';
    final minTarde = (r['minutos_tarde'] as num?)?.toInt() ?? 0;
    late Color col; late IconData ico; late String etiqueta;
    if (estado == 'a_tiempo') {
      col = C.verdeClaro; ico = Icons.check_circle_rounded; etiqueta = 'A tiempo';
    } else if (estado == 'tardanza') {
      col = C.naranja; ico = Icons.schedule_rounded;
      etiqueta = minTarde > 0 ? 'Tardanza +$minTarde min' : 'Tardanza';
    } else {
      col = C.rojo; ico = Icons.cancel_rounded; etiqueta = 'Ausente';
    }
    String cut(String? h) => (h != null && h.length >= 5) ? h.substring(0, 5) : (h ?? '');
    final hr = r['hora_registro'] as String?;
    final firmo = (hr != null && hr.length >= 16) ? 'Firmó a las ${hr.substring(11, 16)}' : 'No firmó';
    final salon = (r['salon'] as String?) ?? '';
    final lugar = r['modalidad'] == 'virtual' ? 'Virtual' : salon;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: col.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(ico, color: col, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['materia'] as String? ?? '', maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: C.tinta, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${cut(r['hora_inicio'] as String?)} – ${cut(r['hora_fin'] as String?)}'
                '${lugar.isNotEmpty ? ' · $lugar' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: C.suave, fontSize: 12)),
            Text(firmo, style: TextStyle(color: C.suave, fontSize: 12)),
          ])),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
                color: col.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(etiqueta, style: TextStyle(
                color: col, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}
