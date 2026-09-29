import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/api.dart';
import 'core/nav.dart';
import 'core/theme.dart';
import 'screens/auth/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_CO');
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
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
  }

  @override
  void dispose() { _ac.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.oscuro,
    body: FadeTransition(
      opacity: _fade,
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          ScaleTransition(
            scale: _scale,
            child: Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [C.verde, C.verdeClaro],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(
                  color: C.verde.withOpacity(0.5),
                  blurRadius: 40, offset: const Offset(0, 12),
                )],
              ),
              child: const Icon(Icons.school_rounded, color: Colors.white, size: 50),
            ),
          ),
          const SizedBox(height: 30),
          const Text('UNIVERSIDAD DE LA GUAJIRA',
            style: TextStyle(color: C.doradoClaro, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 3)),
          const SizedBox(height: 8),
          const Text('Control de Asistencia',
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 60),
          SizedBox(width: 28, height: 28,
            child: CircularProgressIndicator(strokeWidth: 2,
              color: C.verde.withOpacity(0.5))),
        ]),
      ),
    ),
  );
}
