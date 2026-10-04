import 'dart:async';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'ui_kit.dart';

/// Horario semanal compartido por el portal docente y el estudiantil.
/// Resumen de la semana + selector de día + línea de tiempo del día elegido.

const _kAbrev = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _kPaleta = [C.verde, C.azul, C.naranja, C.rojo, C.doradoClaro];

enum _Estado { normal, pasada, enCurso, siguiente }

/// "07:30" -> minutos desde medianoche.
int _min(dynamic h) {
  final p = hm(h).split(':');
  if (p.length < 2) return 0;
  return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
}

int _duracion(dynamic c) {
  final d = _min(c['hora_fin']) - _min(c['hora_inicio']);
  return d > 0 ? d : 0;
}

/// 90 -> "1 h 30 min"
String _dur(int m) {
  if (m <= 0) return '';
  final h = m ~/ 60, r = m % 60;
  if (h == 0) return '$r min';
  if (r == 0) return '$h h';
  return '$h h $r min';
}

class VistaHorario extends StatefulWidget {
  final List horario;
  final void Function(dynamic clase) onClase;
  final bool mostrarProfesor;
  const VistaHorario({
    super.key, required this.horario, required this.onClase,
    this.mostrarProfesor = false,
  });

  @override
  State<VistaHorario> createState() => _VistaHorarioState();
}

class _VistaHorarioState extends State<VistaHorario> {
  late int _dia;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _dia = DateTime.now().weekday;
    // Refresca "en curso" / "siguiente" mientras la pantalla está abierta.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List _delDia(int n) {
    final l = widget.horario.where((c) => c['dia_num'] == n).toList();
    l.sort((a, b) => _min(a['hora_inicio']).compareTo(_min(b['hora_inicio'])));
    return l;
  }

  /// Cada materia conserva el mismo color en toda la semana.
  Map<String, Color> get _colores {
    final nombres = widget.horario
        .map((c) => (c['materia'] ?? '').toString())
        .toSet()
        .toList()
      ..sort();
    return {
      for (var i = 0; i < nombres.length; i++)
        nombres[i]: _kPaleta[i % _kPaleta.length]
    };
  }

  @override
  Widget build(BuildContext context) {
    final colores = _colores;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      _resumen(),
      const SizedBox(height: 16),
      _tira(colores),
      const SizedBox(height: 22),
      _contenidoDia(colores),
    ]);
  }

  // ── Resumen de la semana ────────────────────────────────────────────
  Widget _resumen() {
    var mins = 0;
    final materias = <String>{};
    for (final c in widget.horario) {
      mins += _duracion(c);
      materias.add((c['materia'] ?? '').toString());
    }
    final horas = mins % 60 == 0
        ? '${mins ~/ 60}'
        : (mins / 60).toStringAsFixed(1);

    Widget dato(String valor, String etiqueta) => Expanded(
          child: Column(children: [
            Text(valor, style: const TextStyle(color: Colors.white,
              fontSize: 25, fontWeight: FontWeight.w700, height: 1.1)),
            const SizedBox(height: 2),
            Text(etiqueta, style: TextStyle(
              color: Colors.white.withOpacity(0.78), fontSize: 12)),
          ]));
    Widget sep() =>
        Container(width: 1, height: 36, color: Colors.white.withOpacity(0.2));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [C.verde, Color(0xFF005468)]),
        borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 22, height: 3, decoration: BoxDecoration(
            color: C.dorado, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text('ESTA SEMANA', style: TextStyle(
            color: Colors.white.withOpacity(0.85), fontSize: 11.5,
            fontWeight: FontWeight.w600, letterSpacing: 1.2)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          dato('${widget.horario.length}', 'clases'),
          sep(),
          dato(horas, 'horas'),
          sep(),
          dato('${materias.length}', materias.length == 1 ? 'materia' : 'materias'),
        ]),
      ]),
    );
  }

  // ── Selector de día ─────────────────────────────────────────────────
  Widget _tira(Map<String, Color> colores) {
    final hoy = DateTime.now().weekday;
    final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    return Row(children: List.generate(7, (i) {
      final n = i + 1;
      final clases = _delDia(n);
      final sel = n == _dia;
      final esHoy = n == hoy;

      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
          child: Material(
            color: sel ? C.verde : C.sup,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: sel ? C.verde : (esHoy ? C.dorado : C.borde),
                width: (esHoy && !sel) ? 1.8 : 1)),
            child: InkWell(
              customBorder: forma,
              onTap: () => setState(() => _dia = n),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_kAbrev[n], style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : (clases.isEmpty ? C.suave : C.tinta))),
                  const SizedBox(height: 9),
                  SizedBox(
                    height: 6,
                    child: clases.isEmpty
                      ? Center(child: Container(width: 8, height: 2,
                          color: sel ? Colors.white.withOpacity(0.5) : C.borde))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: clases.take(4).map<Widget>((c) => Container(
                            width: 6, height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: sel ? Colors.white
                                  : (colores[(c['materia'] ?? '').toString()] ?? C.verde)),
                          )).toList()),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    }));
  }

  // ── Línea de tiempo del día ─────────────────────────────────────────
  Widget _contenidoDia(Map<String, Color> colores) {
    final clases = _delDia(_dia);
    final ahoraDt = DateTime.now();
    final esHoy = _dia == ahoraDt.weekday;
    final ahora = ahoraDt.hour * 60 + ahoraDt.minute;

    var total = 0;
    for (final c in clases) {
      total += _duracion(c);
    }

    final cabecera = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        Text(kDias[_dia], style: const TextStyle(
          color: C.tinta, fontSize: 19, fontWeight: FontWeight.w700)),
        if (esHoy) ...[
          const SizedBox(width: 8),
          const Pastilla(texto: 'Hoy', color: C.verdeClaro),
        ],
        const Spacer(),
        if (clases.isNotEmpty)
          Text(
            '${clases.length} ${clases.length == 1 ? 'clase' : 'clases'} · ${_dur(total)}',
            style: const TextStyle(color: C.suave, fontSize: 12.5)),
      ]),
    );

    if (clases.isEmpty) {
      int? prox;
      for (var k = 1; k <= 7; k++) {
        final n = ((_dia - 1 + k) % 7) + 1;
        if (_delDia(n).isNotEmpty) { prox = n; break; }
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        cabecera,
        Tarjeta(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: Center(child: Column(children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: C.verde.withOpacity(0.10), shape: BoxShape.circle),
                child: const Icon(Icons.wb_sunny_outlined,
                  size: 28, color: C.verdeClaro)),
              const SizedBox(height: 14),
              Text('Sin clases el ${kDias[_dia].toLowerCase()}',
                style: const TextStyle(color: C.tinta, fontSize: 16,
                  fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(esHoy ? 'Hoy es tu día libre.' : 'Día libre.',
                style: const TextStyle(color: C.suave, fontSize: 13.5)),
              if (prox != null && prox != _dia) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => setState(() => _dia = prox!),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text('Ir al ${kDias[prox].toLowerCase()}'),
                  style: TextButton.styleFrom(foregroundColor: C.verdeClaro)),
              ],
            ])),
          ),
        ),
      ]);
    }

    final siguiente = esHoy
        ? clases.indexWhere((c) => ahora < _min(c['hora_inicio']))
        : -1;

    final filas = <Widget>[];
    for (var i = 0; i < clases.length; i++) {
      final c = clases[i];
      final ini = _min(c['hora_inicio']);
      final fin = _min(c['hora_fin']);

      var estado = _Estado.normal;
      if (esHoy) {
        if (ahora >= fin) {
          estado = _Estado.pasada;
        } else if (ahora >= ini) {
          estado = _Estado.enCurso;
        } else if (i == siguiente) {
          estado = _Estado.siguiente;
        }
      }

      filas.add(_FilaHorario(
        clase: c,
        color: colores[(c['materia'] ?? '').toString()] ?? C.verde,
        estado: estado,
        ahora: ahora,
        ultimo: i == clases.length - 1,
        mostrarProfesor: widget.mostrarProfesor,
        onTap: () => widget.onClase(c),
      ));

      if (i < clases.length - 1) {
        final hueco = _min(clases[i + 1]['hora_inicio']) - fin;
        if (hueco >= 30) filas.add(_Hueco(minutos: hueco));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [cabecera, ...filas]);
  }
}

// ── Una clase dentro de la línea de tiempo ────────────────────────────
class _FilaHorario extends StatelessWidget {
  final dynamic clase;
  final Color color;
  final _Estado estado;
  final int ahora;
  final bool ultimo, mostrarProfesor;
  final VoidCallback onTap;
  const _FilaHorario({
    required this.clase, required this.color, required this.estado,
    required this.ahora, required this.ultimo, required this.mostrarProfesor,
    required this.onTap,
  });

  Widget _detalle(IconData icono, String texto) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Icon(icono, size: 15, color: C.suave),
          const SizedBox(width: 6),
          Expanded(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: C.tinta70, fontSize: 13))),
        ]));

  @override
  Widget build(BuildContext context) {
    final virtual = clase['modalidad'] == 'virtual';
    final ini = _min(clase['hora_inicio']);
    final fin = _min(clase['hora_fin']);
    final materia = (clase['materia'] ?? '').toString();
    final salon = lugarDe(clase);
    final profesor = (clase['profesor_nombre'] ?? '').toString();
    final pasada = estado == _Estado.pasada;
    final enCurso = estado == _Estado.enCurso;
    final acento = pasada ? C.suave.withOpacity(0.45) : color;

    Widget? pastilla;
    if (enCurso) {
      pastilla = const Pastilla(texto: 'En curso', color: C.verdeClaro);
    } else if (estado == _Estado.siguiente) {
      pastilla = Pastilla(
        texto: 'Siguiente · en ${_dur(ini - ahora)}', color: C.doradoClaro);
    } else if (pasada) {
      pastilla = const Pastilla(texto: 'Finalizada', color: C.suave);
    }

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Horas
        SizedBox(
          width: 46,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(hm(clase['hora_inicio']), style: TextStyle(
              color: pasada ? C.suave : C.tinta, fontSize: 14,
              fontWeight: FontWeight.w700)),
            Text(hm(clase['hora_fin']),
              style: const TextStyle(color: C.suave, fontSize: 11.5)),
          ]),
        ),
        // Riel con punto
        SizedBox(
          width: 26,
          child: Column(children: [
            const SizedBox(height: 4),
            Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: acento,
                boxShadow: enCurso
                  ? [BoxShadow(color: color.withOpacity(0.28), spreadRadius: 4)]
                  : null)),
            if (!ultimo)
              Expanded(child: Container(
                width: 2, margin: const EdgeInsets.only(top: 4), color: C.borde)),
          ]),
        ),
        // Tarjeta
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: ultimo ? 0 : 12),
            child: Opacity(
              opacity: pasada ? 0.62 : 1,
              child: Tarjeta(
                onTap: onTap,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: acento, width: 5))),
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                  child: Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (pastilla != null) ...[
                          pastilla, const SizedBox(height: 8),
                        ],
                        Text(materia, style: const TextStyle(color: C.tinta,
                          fontSize: 16, fontWeight: FontWeight.w700, height: 1.2)),
                        if (!virtual && salon.isNotEmpty)
                          _detalle(Icons.place_outlined, salon),
                        if (mostrarProfesor && profesor.isNotEmpty)
                          _detalle(Icons.person_outline_rounded, profesor),
                        const SizedBox(height: 10),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          if (_dur(fin - ini).isNotEmpty)
                            _Dato(icono: Icons.schedule_rounded, texto: _dur(fin - ini)),
                          _Dato(
                            icono: virtual ? Icons.videocam_outlined : Icons.apartment_rounded,
                            texto: virtual ? 'Virtual · Meet' : 'Presencial'),
                        ]),
                        if (enCurso && fin > ini) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: ((ahora - ini) / (fin - ini)).clamp(0.0, 1.0).toDouble(),
                              minHeight: 5,
                              backgroundColor: color.withOpacity(0.15),
                              valueColor: AlwaysStoppedAnimation(color))),
                          const SizedBox(height: 6),
                          Text('Termina en ${_dur(fin - ahora)}',
                            style: TextStyle(color: color, fontSize: 12,
                              fontWeight: FontWeight.w600)),
                        ],
                      ])),
                    const Icon(Icons.chevron_right_rounded, color: C.suave),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Pequeña etiqueta con icono (duración, modalidad).
class _Dato extends StatelessWidget {
  final IconData icono;
  final String texto;
  const _Dato({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: C.sup2, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icono, size: 14, color: C.suave),
          const SizedBox(width: 5),
          Text(texto, style: const TextStyle(color: C.tinta70, fontSize: 12)),
        ]),
      );
}

/// Espacio libre entre dos clases del mismo día.
class _Hueco extends StatelessWidget {
  final int minutos;
  const _Hueco({required this.minutos});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 38,
        child: Row(children: [
          const SizedBox(width: 46),
          SizedBox(
            width: 26,
            child: Center(child: Container(width: 2, color: C.borde))),
          const SizedBox(width: 4),
          Expanded(child: Text('Libre ${_dur(minutos)}',
            style: const TextStyle(color: C.suave, fontSize: 12,
              fontStyle: FontStyle.italic))),
        ]),
      );
}
