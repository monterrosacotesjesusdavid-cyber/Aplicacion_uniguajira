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

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'UniGuajira',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    navigatorKey: navKey,
    home: const Splash(),
  );
}

class Splash extends StatefulWidget {
  const Splash({super.key});
  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fade  = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _scale = Tween(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.elasticOut));
    _ac.forward();
    _route();
  }

  Future<void> _route() async {
    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    final p = await SharedPreferences.getInstance();
    final token = await Api.getToken();
    final rol   = p.getString('rol');
    // Entrar sin internet deja la sesión sin token: también cuenta como sesión abierta.
    final abierta = token != null || p.getBool('sesion_offline') == true;
    final Widget dest = (abierta && rol != null)
        ? destinoPorRol(rol, rostroRegistrado: await Api.rostroRegistrado())
        : const LoginScreen();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => dest));
    Actualizador.revisar();
  }

  @override
  void dispose() { _ac.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: FadeTransition(
      opacity: _fade,
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          ScaleTransition(
            scale: _scale,
            child: Image.asset('assets/logo.png', width: 260, fit: BoxFit.contain),
          ),
          const SizedBox(height: 22),
          const _Franja(),
          const SizedBox(height: 22),
          const Text('Control de Asistencia',
            style: TextStyle(color: C.tinta, fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 48),
          const SizedBox(width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: C.verde)),
        ]),
      ),
    ),
  );
}

/// Tres franjas con los colores del escudo (teal, dorado y rojo).
class _Franja extends StatelessWidget {
  const _Franja();
  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 34, height: 3, child: ColoredBox(color: C.verde)),
      SizedBox(width: 34, height: 3, child: ColoredBox(color: C.dorado)),
      SizedBox(width: 34, height: 3, child: ColoredBox(color: C.rojo)),
    ],
  );
}
