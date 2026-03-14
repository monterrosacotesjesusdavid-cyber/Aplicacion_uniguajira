import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/estudiante/estudiante_home.dart';
import 'screens/profesor/profesor_home.dart';
import 'screens/admin/admin_home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    final token = p.getString('token');
    final rol   = p.getString('rol');
    Widget dest;
    if (token != null && rol != null) {
      if (rol == 'admin')       dest = const AdminHome();
      else if (rol == 'profesor') dest = const ProfesorHome();
      else                       dest = const EstudianteHome();
    } else {
      dest = const LoginScreen();
    }
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
