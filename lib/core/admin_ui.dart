import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Paleta del panel de administrador: siempre oscura, con acentos dorados
/// (no depende del modo claro/oscuro del resto de la app).
class A {
  static const bg      = Color(0xFF0A0E10);
  static const card1   = Color(0xFF1A2124);
  static const card2   = Color(0xFF12181A);
  static const borde   = Color(0x1FFFFFFF);
  static const texto   = Color(0xFFF2F6F7);
  static const suave   = Color(0xFF8C9DA3);
  static const oro     = Color(0xFFE0A020);
  static const oroClaro = Color(0xFFF5CC6B);
  static const sobreOro = Color(0xFF1A1200); // texto sobre fondo dorado
  static const teal    = Color(0xFF00788C);
  static const tealClaro = Color(0xFF4FC3D6);
  static const ok      = Color(0xFF34D399);
  static const warn    = Color(0xFFFB923C);
  static const mal     = Color(0xFFF87171);
  static const malFuerte = Color(0xFFB4342A);
  static const azul    = Color(0xFF60A5FA);
  static const gris    = Color(0xFF5B6B72);

  static const gradOro = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFF2BC3F), Color(0xFFB9800F)]);
  static const gradCard = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [card1, card2]);
}

/// Tema oscuro para envolver las pantallas del admin (diálogos, campos, selector de fecha…).
ThemeData admTheme() {
  OutlineInputBorder borde(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: w));
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: A.bg,
    colorScheme: const ColorScheme.dark(
      primary: A.oro, secondary: A.teal, surface: A.card1,
      error: A.mal, onSurface: A.texto),
    dialogTheme: DialogThemeData(
      backgroundColor: A.card1, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: A.card1, behavior: SnackBarBehavior.floating,
      contentTextStyle: const TextStyle(color: A.texto),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: A.card1,
      border: borde(A.borde), enabledBorder: borde(A.borde),
      focusedBorder: borde(A.oro, 1.4),
      hintStyle: const TextStyle(color: A.suave),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15)),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: A.oro),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: A.oro),
    dividerColor: A.borde,
  );
}

// ── Utilidades ──────────────────────────────────────────────────────

String admTitulo(String s) => s.trim().split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

/// "2026-10-08T14:05:00…" → "14:05" (o '' si no hay hora).
String admHora(dynamic iso) {
  final s = (iso ?? '').toString();
  return s.length >= 16 ? s.substring(11, 16) : '';
}

({Color color, IconData icono, String texto}) admEstado(String e) {
  switch (e) {
    case 'a_tiempo':
      return (color: A.ok, icono: Icons.check_circle_rounded, texto: 'A tiempo');
    case 'tardanza':
      return (color: A.warn, icono: Icons.schedule_rounded, texto: 'Tardanza');
    default:
      return (color: A.mal, icono: Icons.cancel_rounded, texto: 'Ausente');
  }
}

// ── Widgets ─────────────────────────────────────────────────────────

class AdmCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? borde;
  final double radius;
  const AdmCard({super.key, required this.child,
    this.padding = const EdgeInsets.all(16), this.onTap,
    this.gradient, this.borde, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        gradient: gradient ?? A.gradCard,
        borderRadius: r,
        border: Border.all(color: borde ?? A.borde),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25),
          blurRadius: 18, offset: const Offset(0, 8))]),
      child: Material(
        color: Colors.transparent, borderRadius: r, clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, borderRadius: r,
          child: Padding(padding: padding, child: child))),
    );
  }
}

class AdmPill extends StatelessWidget {
  final String texto;
  final Color color;
  final IconData? icono;
  final double size;
  const AdmPill(this.texto, this.color, {super.key, this.icono, this.size = 11});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icono != null) ...[
        Icon(icono, size: size + 2, color: color), const SizedBox(width: 4)],
      Text(texto, style: TextStyle(color: color, fontSize: size,
        fontWeight: FontWeight.w700)),
    ]),
  );
}

class AdmIcono extends StatelessWidget {
  final IconData icono;
  final Color color;
  final double tam;
  const AdmIcono(this.icono, this.color, {super.key, this.tam = 44});

  @override
  Widget build(BuildContext context) => Container(
    width: tam, height: tam,
    decoration: BoxDecoration(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(tam * 0.32),
      border: Border.all(color: color.withOpacity(0.25))),
    child: Icon(icono, color: color, size: tam * 0.5),
  );
}

/// Barra de progreso con degradado y animación de entrada.
class AdmBarra extends StatelessWidget {
  final double valor; // 0..1
  final Color color;
  final double alto;
  const AdmBarra(this.valor, this.color, {super.key, this.alto = 6});

  @override
  Widget build(BuildContext context) {
    final v = valor.clamp(0.0, 1.0).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: v),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (_, t, __) => Container(
        height: alto,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(alto)),
        child: Align(alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: t <= 0 ? 0 : math.max(t, 0.02),
            child: Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.65), color]),
              borderRadius: BorderRadius.circular(alto))))),
      ),
    );
  }
}

/// Anillo de progreso animado.
class AdmRing extends StatelessWidget {
  final double valor; // 0..1
  final double tam, grosor;
  final Color color, pista;
  final Widget? centro;
  const AdmRing({super.key, required this.valor, this.tam = 80,
    this.grosor = 9, required this.color, required this.pista, this.centro});

  @override
  Widget build(BuildContext context) {
    final v = valor.clamp(0.0, 1.0).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: v),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, t, __) => SizedBox(width: tam, height: tam,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(size: Size(tam, tam),
            painter: _RingP(t, color, pista, grosor)),
          if (centro != null) centro!,
        ])),
    );
  }
}

class _RingP extends CustomPainter {
  final double v, g;
  final Color color, pista;
  const _RingP(this.v, this.color, this.pista, this.g);

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Rect.fromLTWH(g / 2, g / 2, s.width - g, s.height - g);
    canvas.drawArc(rect, 0, 2 * math.pi, false, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = g..color = pista);
    if (v <= 0) return;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * v, false, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = g
      ..strokeCap = StrokeCap.round..color = color);
  }

  @override
  bool shouldRepaint(_RingP o) => o.v != v || o.color != color || o.pista != pista;
}

/// Gráfico de dona animado.
class AdmDonut extends StatelessWidget {
  final List<double> valores;
  final List<Color> colores;
  final double tam, grosor;
  final Widget? centro;
  const AdmDonut({super.key, required this.valores, required this.colores,
    this.tam = 128, this.grosor = 16, this.centro});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: 1),
    duration: const Duration(milliseconds: 900),
    curve: Curves.easeOutCubic,
    builder: (_, t, __) => SizedBox(width: tam, height: tam,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: Size(tam, tam),
          painter: _DonutP(valores, colores, t, grosor)),
        if (centro != null) centro!,
      ])),
  );
}

class _DonutP extends CustomPainter {
  final List<double> v;
  final List<Color> c;
  final double prog, g;
  const _DonutP(this.v, this.c, this.prog, this.g);

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Rect.fromLTWH(g / 2, g / 2, s.width - g, s.height - g);
    canvas.drawCircle(rect.center, rect.width / 2, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = g
      ..color = Colors.white.withOpacity(0.07));
    final total = v.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final n = v.where((x) => x > 0).length;
    final gap = n > 1 ? 0.06 : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < v.length; i++) {
      if (v[i] <= 0) continue;
      final full = v[i] / total * 2 * math.pi;
      final sweep = math.max(0.0, full - gap) * prog;
      canvas.drawArc(rect, start + gap / 2, sweep, false, Paint()
        ..style = PaintingStyle.stroke..strokeWidth = g
        ..strokeCap = StrokeCap.butt..color = c[i]);
      start += full;
    }
  }

  @override
  bool shouldRepaint(_DonutP o) => o.prog != prog || o.v != v;
}

/// Estado vacío / de error.
class AdmVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? sub;
  final Widget? accion;
  const AdmVacio(this.icono, this.titulo, {super.key, this.sub, this.accion});

  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      AdmIcono(icono, A.suave, tam: 64),
      const SizedBox(height: 16),
      Text(titulo, textAlign: TextAlign.center, style: const TextStyle(
        color: A.texto, fontSize: 15, fontWeight: FontWeight.w700)),
      if (sub != null) ...[
        const SizedBox(height: 6),
        Text(sub!, textAlign: TextAlign.center,
          style: const TextStyle(color: A.suave, fontSize: 12.5))],
      if (accion != null) ...[const SizedBox(height: 14), accion!],
    ])));
}

/// Botón cuadrado con ícono (cerrar sesión, volver…).
class AdmBotonIcono extends StatelessWidget {
  final IconData icono;
  final VoidCallback onTap;
  final String? tooltip;
  const AdmBotonIcono(this.icono, this.onTap, {super.key, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final boton = Material(
      color: A.card1, borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14), onTap: onTap,
        child: Container(width: 44, height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: A.borde)),
          child: Icon(icono, color: A.texto, size: 20))));
    return tooltip == null ? boton : Tooltip(message: tooltip!, child: boton);
  }
}
