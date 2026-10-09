import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/admin_ui.dart';
import '../../core/api.dart';
import '../auth/login_screen.dart';
import 'dashboard_screen.dart';
import 'profesores_stats_screen.dart';
import 'offline_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _idx = 0;
  String _nombre = '';
  int _pendientes = 0;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _nombre = p.getString('nombre') ?? '');
    });
    _contarPendientes();
  }

  Future<void> _contarPendientes() async {
    try {
      final d = await Api.offlineAdmin(estado: 'pendiente');
      if (!mounted) return;
      setState(() => _pendientes = (d['total'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  void _ir(int i) {
    if (i == _idx) return;
    setState(() => _idx = i);
    if (i != 2) _contarPendientes();
  }

  Future<void> _logout(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Cerrar sesión',
          style: TextStyle(color: A.texto, fontWeight: FontWeight.w700)),
        content: const Text('¿Deseas salir?', style: TextStyle(color: A.suave)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancelar', style: TextStyle(color: A.suave))),
          TextButton(onPressed: () => Navigator.pop(d, true),
            child: const Text('Salir', style: TextStyle(color: A.mal))),
        ],
      ),
    );
    if (ok == true) {
      await Api.logout();
      if (mounted) {
        Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      }
    }
  }

  Widget _cabecera(BuildContext ctx) {
    final titulos = ['Administración', 'Profesores', 'Por aprobar'];
    final subs = [
      _nombre.isEmpty ? 'Panel de control' : 'Bienvenido, ${admTitulo(_nombre)}',
      'Estadísticas de asistencia',
      'Asistencias tomadas sin internet',
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, MediaQuery.of(ctx).padding.top + 14, 16, 8),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            gradient: A.gradOro,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [BoxShadow(color: A.oro.withOpacity(0.35),
              blurRadius: 16, offset: const Offset(0, 6))]),
          child: const Icon(Icons.admin_panel_settings_rounded,
            color: A.sobreOro, size: 24)),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_idx == 0 ? '${titulos[0]} 👋' : titulos[_idx],
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: A.texto, fontSize: 22,
              fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: 2),
          Text(subs[_idx], maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: A.suave, fontSize: 12.5)),
        ])),
        AdmBotonIcono(Icons.logout_rounded, () => _logout(ctx),
          tooltip: 'Cerrar sesión'),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: admTheme(),
      child: Builder(builder: (ctx) {
        final screens = <Widget>[
          const DashboardScreen(),
          const ProfesoresStatsScreen(),
          OfflineAdminScreen(onPendientes: (n) {
            if (mounted && n != _pendientes) setState(() => _pendientes = n);
          }),
        ];
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: A.bg,
            systemNavigationBarIconBrightness: Brightness.light),
          child: Scaffold(
            backgroundColor: A.bg,
            body: Stack(children: [
              // Resplandor sutil de fondo
              Positioned.fill(child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(1, -1), radius: 1.1,
                    colors: [A.teal.withOpacity(0.22), A.bg])))),
              Column(children: [
                _cabecera(ctx),
                Expanded(child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: KeyedSubtree(
                    key: ValueKey(_idx), child: screens[_idx]))),
              ]),
            ]),
            bottomNavigationBar: _Nav(
              idx: _idx, pendientes: _pendientes, onTap: _ir),
          ),
        );
      }),
    );
  }
}

class _Nav extends StatelessWidget {
  final int idx, pendientes;
  final ValueChanged<int> onTap;
  const _Nav({required this.idx, required this.pendientes, required this.onTap});

  static const _items = <(IconData, String)>[
    (Icons.space_dashboard_rounded, 'Resumen'),
    (Icons.people_alt_rounded, 'Profesores'),
    (Icons.pending_actions_rounded, 'Por aprobar'),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          gradient: A.gradCard,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: A.borde),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45),
            blurRadius: 24, offset: const Offset(0, 10))]),
        child: Row(children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(child: _Item(
              icono: _items[i].$1, texto: _items[i].$2,
              activo: i == idx,
              badge: i == 2 ? pendientes : 0,
              onTap: () => onTap(i))),
        ]),
      ),
    ),
  );
}

class _Item extends StatelessWidget {
  final IconData icono;
  final String texto;
  final bool activo;
  final int badge;
  final VoidCallback onTap;
  const _Item({required this.icono, required this.texto,
    required this.activo, required this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        gradient: activo ? A.gradOro : null,
        borderRadius: BorderRadius.circular(21),
        boxShadow: activo
          ? [BoxShadow(color: A.oro.withOpacity(0.3),
              blurRadius: 14, offset: const Offset(0, 4))]
          : null),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          Icon(icono, size: 22, color: activo ? A.sobreOro : A.suave),
          if (badge > 0)
            Positioned(right: -9, top: -5, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: A.mal, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: A.card1, width: 1.5)),
              child: Text(badge > 99 ? '99+' : '$badge',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 9,
                  fontWeight: FontWeight.w800)))),
        ]),
        const SizedBox(height: 3),
        Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10.5,
            fontWeight: activo ? FontWeight.w800 : FontWeight.w500,
            color: activo ? A.sobreOro : A.suave)),
      ]),
    ),
  );
}
