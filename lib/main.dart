import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/actualizador.dart';
import 'core/api.dart';
import 'core/nav.dart';
import 'core/theme.dart';
import 'screens/auth/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_CO');
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver a la app (sin cerrarla del todo) también se busca una versión nueva.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Actualizador.revisar();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'UniGuajira',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    navigatorKey: navKey,
    // Respeta el tamaño de letra del sistema, pero sin pasarse (evita desbordes en las tarjetas).
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3)),
        child: child ?? const SizedBox.shrink());
    },
    home: const Splash(),
  );
}

class Splash extends StatefulWidget {
  const Splash({super.key});
  @override
  State<Splash> createState() => _SplashState();
}

/// Arranque: el escudo se "arma" por tiras, luego aparece el texto y la franja
/// tricolor; al terminar, el logo viaja (Hero) hasta su lugar en el login mientras
/// la pantalla entra con un zoom suave.
class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  static const double _w = 260;                 // ancho del logo en pantalla
  static const double _h = _w * 308 / 554;      // alto (proporción de logo.png)
  static const double _corte = 0.41;            // dónde termina el escudo y empieza el texto
  static const int _tiras = 9;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
    _arrancar();
  }

  Future<Widget> _destino() async {
    try {
      final p = await SharedPreferences.getInstance();
      final token = await Api.getToken();
      final rol   = p.getString('rol');
      // Entrar sin internet deja la sesión sin token: también cuenta como sesión abierta.
      final abierta = token != null || p.getBool('sesion_offline') == true;
      if (abierta && rol != null) {
        return destinoPorRol(rol, rostroRegistrado: await Api.rostroRegistrado());
      }
    } catch (_) {}
    return const LoginScreen();
  }

  Future<void> _arrancar() async {
    final destino = _destino();            // se resuelve mientras corre la animación
    await _ac.forward();
    await Future.delayed(const Duration(milliseconds: 250));
    final dest = await destino;
    if (!mounted) return;
    Navigator.pushReplacement(context, PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 900),
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => dest,
      transitionsBuilder: (_, a, __, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeInOutCubic);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.08, end: 1.0).animate(c),
            child: child));
      },
    ));
    Actualizador.revisar();
  }

  @override
  void dispose() { _ac.dispose(); super.dispose(); }

  /// Progreso (0..1) de un tramo de la animación, entre [a] y [b] del total.
  double _t(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((_ac.value - a) / (b - a)).clamp(0.0, 1.0));

  /// Un trozo rectangular del logo (x0,y0,ancho,alto) tomado de la imagen completa.
  Widget _recorte(double x0, double y0, double w, double h) => SizedBox(
    width: w, height: h,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: _w, maxWidth: _w, minHeight: _h, maxHeight: _h,
        child: Transform.translate(
          offset: Offset(-x0, -y0),
          child: Image.asset('assets/logo.png',
            width: _w, height: _h, fit: BoxFit.fill)),
      ),
    ),
  );

  Widget _escudo(double ew) {
    final sh = _h / _tiras;
    return SizedBox(
      width: ew, height: _h,
      child: Stack(clipBehavior: Clip.none, children: [
        for (int i = 0; i < _tiras; i++)
          Positioned(
            top: i * sh, left: 0,
            child: Builder(builder: (_) {
              final ini = 0.02 + i * 0.045;
              final e = _t(ini, ini + 0.22);
              final dx = (i.isEven ? -1 : 1) * 70 * (1 - e);
              return Transform.translate(
                offset: Offset(dx, 0),
                child: Opacity(
                  opacity: e,
                  child: _recorte(0, i * sh, ew, sh + 0.6)));
            }),
          ),
      ]),
    );
  }

  Widget _logo() {
    // Al terminar se muestra la imagen completa (sin costuras) para el Hero.
    if (_ac.value >= 1) {
      return Image.asset('assets/logo.png', width: _w, height: _h, fit: BoxFit.fill);
    }
    final ew = _w * _corte;
    final t = _t(0.50, 0.88);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _escudo(ew),
      ClipRect(
        clipper: _Revela(t),
        child: Opacity(opacity: t, child: _recorte(ew, 0, _w - ew, _h))),
    ]);
  }

  Widget _franja() {
    final cols = [C.verde, C.dorado, C.rojo];
    final t = _t(0.82, 1.0, Curves.easeOut);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (int i = 0; i < 3; i++)
        Transform.scale(
          scaleX: ((t * 3 - i)).clamp(0.0, 1.0),
          child: SizedBox(width: 34, height: 3, child: ColoredBox(color: cols[i]))),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: AnimatedBuilder(
        animation: _ac,
        builder: (_, __) => Column(mainAxisSize: MainAxisSize.min, children: [
          Hero(tag: 'logo', child: _logo()),
          const SizedBox(height: 22),
          _franja(),
        ]),
      ),
    ),
  );
}

/// Muestra el texto del logo de izquierda a derecha.
class _Revela extends CustomClipper<Rect> {
  final double t;
  const _Revela(this.t);
  @override
  Rect getClip(Size s) => Rect.fromLTWH(0, 0, s.width * t, s.height);
  @override
  bool shouldReclip(_Revela o) => o.t != t;
}
