import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/liveness_screen.dart';
import '../../core/theme.dart';
import 'login_screen.dart';

class EnrolarRostroScreen extends StatefulWidget {
  final Widget destino;
  const EnrolarRostroScreen({super.key, required this.destino});
  @override
  State<EnrolarRostroScreen> createState() => _EnrolarState();
}

class _EnrolarState extends State<EnrolarRostroScreen> {
  bool _acepto = false, _loading = false;
  String? _error;

  Future<void> _registrar() async {
    setState(() => _error = null);
    final foto = await LivenessScreen.abrir(context, titulo: 'Registro de rostro');
    if (foto == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final r = await Api.enrolarRostro(foto);
      if (!mounted) return;
      if (r['_status'] == 200) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => widget.destino));
      } else {
        setState(() => _error = r['error'] ?? 'No se pudo registrar tu rostro. Intenta de nuevo.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Error de conexión. Revisa tu internet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _salir() async {
    await Api.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Spacer(),
          Center(
            child: Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color: C.verde,
                borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.face_retouching_natural, color: Colors.white, size: 46),
            ),
          ),
          const SizedBox(height: 28),
          Text('Registra tu rostro',
              style: TextStyle(color: C.tinta, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text('Lo usaremos para confirmar que eres tú al firmar asistencia. '
              'Solo se hace una vez y tarda unos segundos.',
              style: TextStyle(color: C.tinta.withOpacity(0.6), fontSize: 14, height: 1.4)),
          const SizedBox(height: 22),
          InkWell(
            onTap: () => setState(() => _acepto = !_acepto),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(value: _acepto, activeColor: C.verde,
                  onChanged: (v) => setState(() => _acepto = v ?? false)),
              const SizedBox(width: 4),
              Expanded(child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Autorizo a la Universidad de La Guajira a tratar mis datos '
                    'biométricos faciales únicamente para el control de asistencia (Ley 1581 de 2012).',
                    style: TextStyle(color: C.tinta.withOpacity(0.7), fontSize: 12, height: 1.4)),
              )),
            ]),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: C.rojo, fontSize: 13)),
          ],
          const Spacer(),
          ElevatedButton(
            onPressed: (_acepto && !_loading) ? _registrar : null,
            child: _loading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Registrar mi rostro'),
          ),
          const SizedBox(height: 8),
          Center(child: TextButton(onPressed: _salir,
              child: Text('Cerrar sesión', style: TextStyle(color: C.suave)))),
        ]),
      ),
    ),
  );
}
