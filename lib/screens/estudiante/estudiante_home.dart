import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/ui_kit.dart';
import '../auth/login_screen.dart';
import 'clases_estudiante_screen.dart';
import 'horario_estudiante_screen.dart';
import 'materias_estudiante_screen.dart';

class EstudianteHome extends StatefulWidget {
  const EstudianteHome({super.key});
  @override
  State<EstudianteHome> createState() => _EstState();
}

class _EstState extends State<EstudianteHome> {
  String _nombre = '';
  int _tab = 0;

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
        title: Text('Cerrar sesión', style: TextStyle(color: C.tinta)),
        content: Text('¿Deseas salir?', style: TextStyle(color: C.suave)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: TextStyle(color: C.suave))),
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
      toolbarHeight: 64,
      title: const MarcaAppBar(sub: 'Portal Estudiantil'),
      actions: [MenuUsuario(nombre: _nombre, onSalir: _logout)],
    ),
    body: IndexedStack(index: _tab, children: const [
      ClasesEstudianteScreen(),
      HorarioEstudianteScreen(),
      MateriasEstudianteScreen(),
    ]),
    bottomNavigationBar: BarraInferior(
      indice: _tab, onTap: (i) => setState(() => _tab = i),
      destinos: const [
        NavigationDestination(
          icon: Icon(Icons.today_outlined),
          selectedIcon: Icon(Icons.today_rounded), label: 'Hoy'),
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month_rounded), label: 'Horario'),
        NavigationDestination(
          icon: Icon(Icons.fact_check_outlined),
          selectedIcon: Icon(Icons.fact_check_rounded), label: 'Materias'),
      ]),
  );
}
