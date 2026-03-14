import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../auth/login_screen.dart';
import 'clases_estudiante_screen.dart';

class EstudianteHome extends StatefulWidget {
  const EstudianteHome({super.key});
  @override
  State<EstudianteHome> createState() => _EstState();
}

class _EstState extends State<EstudianteHome> {
  String _nombre = '';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance()
        .then((p) => setState(() => _nombre = p.getString('nombre') ?? ''));
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión', style: TextStyle(color: Colors.white)),
        content: const Text('¿Deseas salir?', style: TextStyle(color: C.suave)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: C.suave))),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir', style: TextStyle(color: C.rojo))),
        ],
      ),
    );
    if (ok == true) {
      await Api.logout();
      if (mounted) Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: _AppBarLogo(sub: 'Portal Estudiantil'),
      actions: [
        Padding(padding: const EdgeInsets.only(right: 4),
          child: Center(child: Text(_nombre,
            style: const TextStyle(color: C.doradoClaro, fontSize: 12,
              fontWeight: FontWeight.w600)))),
        IconButton(
          icon: const Icon(Icons.logout_rounded, size: 20, color: Colors.white38),
          onPressed: _logout),
      ],
    ),
    body: const ClasesEstudianteScreen(),
  );
}

class _AppBarLogo extends StatelessWidget {
  final String sub;
  const _AppBarLogo({required this.sub});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 30, height: 30,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [C.azul, Color(0xFF3498DB)]),
        borderRadius: BorderRadius.circular(8)),
      child: const Icon(Icons.school_rounded, color: Colors.white, size: 16)),
    const SizedBox(width: 10),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('UniGuajira', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      Text(sub, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.4),
        fontWeight: FontWeight.w400)),
    ]),
  ]);
}
