import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../auth/login_screen.dart';
import 'dashboard_screen.dart';
import 'profesores_stats_screen.dart';
import 'asistencias_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _idx = 0;
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
  Widget build(BuildContext context) {
    final screens = const [
      DashboardScreen(),
      ProfesoresStatsScreen(),
      AdminAsistenciasScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(width: 30, height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [C.dorado, C.doradoClaro]),
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.admin_panel_settings_rounded,
              color: Colors.white, size: 16)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('UniGuajira', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            Text('Panel Admin', style: TextStyle(fontSize: 10,
              color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w400)),
          ]),
        ]),
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
      body: screens[_idx],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.borde))),
        child: BottomNavigationBar(
          currentIndex: _idx,
          onTap: (i) => setState(() => _idx = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_rounded), label: 'Profesores'),
            BottomNavigationBarItem(
              icon: Icon(Icons.fact_check_rounded), label: 'Asistencias'),
          ],
        ),
      ),
    );
  }
}
