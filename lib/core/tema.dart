import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'actualizador.dart' show navKey;

/// Modo claro / oscuro. `oscuro` es el estado global; la app se reconstruye al cambiarlo.
class Tema {
  static final ValueNotifier<bool> oscuro = ValueNotifier<bool>(false);

  /// Se coloca en un RepaintBoundary que envuelve toda la app (ver main.dart).
  static final GlobalKey fotoKey = GlobalKey();

  static bool _animando = false;

  /// Lee la preferencia guardada (por defecto: modo claro).
  static Future<void> cargar() async {
    try {
      final p = await SharedPreferences.getInstance();
      oscuro.value = p.getBool('tema_oscuro') ?? false;
    } catch (_) {}
  }

  static Future<void> _guardar(bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('tema_oscuro', v);
    } catch (_) {}
  }

  /// Fuerza que TODOS los widgets vuelvan a leer los colores de [C].
  static void _reconstruirTodo() {
    void visitar(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visitar);
    }
    WidgetsBinding.instance.rootElement?.visitChildren(visitar);
  }

  /// Cambia de tema con una onda circular que sale desde [origen]
  /// (centro del interruptor). Si algo falla, cambia sin animación.
  static Future<void> alternar(BuildContext context, {Offset? origen}) async {
    if (_animando) return;
    _animando = true;
    final nuevo = !oscuro.value;
    final overlay = navKey.currentState?.overlay;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    ui.Image? foto;
    try {
      final b = fotoKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (b != null && overlay != null) foto = await b.toImage(pixelRatio: dpr);
    } catch (_) {
      foto = null;
    }

    oscuro.value = nuevo;
    _guardar(nuevo);
    _reconstruirTodo();

    if (foto == null || overlay == null) {
      _animando = false;
      return;
    }
    final caja = overlay.context.findRenderObject() as RenderBox?;
    final tam = caja?.size ?? MediaQuery.of(context).size;
    final centro = origen ?? Offset(tam.width - 40, 60);
    final img = foto;

    late OverlayEntry entrada;
    entrada = OverlayEntry(
      builder: (_) => _Onda(
        foto: img, tam: tam, centro: centro, haciaOscuro: nuevo,
        alTerminar: () {
          entrada.remove();
          img.dispose();
          _animando = false;
        }),
    );
    overlay.insert(entrada);
  }
}

/// Muestra la captura del tema anterior con un "hueco" circular que crece
/// y deja ver el tema nuevo; un aro de luz marca el borde de la onda.
class _Onda extends StatefulWidget {
  final ui.Image foto;
  final Size tam;
  final Offset centro;
  final bool haciaOscuro;
  final VoidCallback alTerminar;
  const _Onda({required this.foto, required this.tam, required this.centro,
    required this.haciaOscuro, required this.alTerminar});
  @override
  State<_Onda> createState() => _OndaState();
}

class _OndaState extends State<_Onda> with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  late final double _rMax;

  @override
  void initState() {
    super.initState();
    final c = widget.centro, s = widget.tam;
    _rMax = [
      c.distance,
      (c - Offset(s.width, 0)).distance,
      (c - Offset(0, s.height)).distance,
      (c - Offset(s.width, s.height)).distance,
    ].reduce(math.max);
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 750))
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed) widget.alTerminar();
      })
      ..forward();
  }

  @override
  void dispose() { _ac.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final t = Curves.easeInOutCubic.transform(_ac.value);
        final r = _rMax * t;
        return SizedBox(
          width: widget.tam.width, height: widget.tam.height,
          child: Stack(children: [
            ClipPath(
              clipper: _Hueco(widget.centro, r),
              child: RawImage(image: widget.foto, fit: BoxFit.fill,
                width: widget.tam.width, height: widget.tam.height)),
            CustomPaint(
              size: widget.tam,
              painter: _Aro(widget.centro, r, 1 - _ac.value,
                widget.haciaOscuro ? const Color(0xFFB9C8FF) : const Color(0xFFFFC53D))),
          ]),
        );
      }),
  );
}

class _Hueco extends CustomClipper<Path> {
  final Offset c; final double r;
  const _Hueco(this.c, this.r);
  @override
  Path getClip(Size s) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & s)
    ..addOval(Rect.fromCircle(center: c, radius: r));
  @override
  bool shouldReclip(_Hueco o) => o.r != r || o.c != c;
}

class _Aro extends CustomPainter {
  final Offset c; final double r; final double op; final Color color;
  const _Aro(this.c, this.r, this.op, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    if (r <= 0) return;
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..color = color.withOpacity(0.18 * op)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = color.withOpacity(0.85 * op));
  }
  @override
  bool shouldRepaint(_Aro o) => o.r != r || o.op != op;
}
