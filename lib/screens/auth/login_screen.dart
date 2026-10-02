import 'package:flutter/material.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/liveness_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _idCtrl   = TextEditingController();
  final _codCtrl  = TextEditingController();
  bool _loading   = false;
  bool _verCod    = false;
  String? _error;

  @override
  void dispose() {
    _idCtrl.dispose(); _codCtrl.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    setState(() { _loading = true; _error = null; });
    try {
      Map<String, dynamic> data;
      final id  = _idCtrl.text.trim();
      final cod = _codCtrl.text;
      if (id.isEmpty || cod.trim().isEmpty) {
        setState(() { _error = 'Completa todos los campos'; _loading = false; });
        return;
      }
      if (id.contains('@')) {
        // Un correo identifica a un administrador
        data = await Api.loginAdmin(id, cod);
      } else {
        data = await Api.login(id, cod.trim());
        // El servidor pide rostro si el usuario ya lo registró: se verifica antes de entrar.
        if (data['code'] == 'FACE_REQUIRED') {
          if (!mounted) return;
          final foto = await LivenessScreen.abrir(context,
              titulo: 'Verifica tu identidad para entrar');
          if (foto == null || !mounted) {
            setState(() => _error = 'Debes verificar tu rostro para iniciar sesión');
            return;
          }
          data = await Api.login(id, cod.trim(), fotoBase64: foto);
        }
      }
      if (!mounted) return;
      if (data['_status'] == 200) {
        final rol = data['rol'] as String;
        final Widget dest = destinoPorRol(rol,
            rostroRegistrado: data['rostro_registrado'] != false);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => dest));
      } else {
        setState(() => _error = data['error'] ?? 'Datos incorrectos');
      }
    } catch (_) {
      setState(() => _error = 'Error de conexión. Revisa tu internet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: C.fondo,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(children: [
              const SizedBox(height: 20),

              // Escudo de la universidad
              Image.asset('assets/logo.png', height: 110, fit: BoxFit.contain),
              const SizedBox(height: 16),
              const Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 34, height: 3, child: ColoredBox(color: C.verde)),
                SizedBox(width: 34, height: 3, child: ColoredBox(color: C.dorado)),
                SizedBox(width: 34, height: 3, child: ColoredBox(color: C.rojo)),
              ]),
              const SizedBox(height: 20),
              const Text('Control de Asistencia',
                style: TextStyle(color: C.tinta, fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Ingresa con tus credenciales institucionales',
                style: TextStyle(color: C.suave, fontSize: 13)),
              const SizedBox(height: 24),

              // Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: C.sup,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: C.borde),
                ),
                child: Column(children: [

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: C.verde.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: C.verde.withOpacity(0.2)),
                    ),
                    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline_rounded, color: C.verdeClaro, size: 16),
                      SizedBox(width: 8),
                      Expanded(child: Text(
                        'Estudiante: escribe tu usuario (sin @)\nProfesor: escribe tu cédula\n'
                        'Administrador: escribe tu correo\n'
                        'Sin internet: puedes entrar si ya iniciaste sesión antes en este celular.',
                        style: TextStyle(color: C.tinta70, fontSize: 11),
                      )),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _idCtrl,
                    style: const TextStyle(color: C.tinta),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'USUARIO, CÉDULA O CORREO',
                      prefixIcon: Icon(Icons.person_outline_rounded, color: C.suave, size: 20),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _codCtrl,
                    obscureText: !_verCod,
                    style: const TextStyle(color: C.tinta),
                    onSubmitted: (_) => _ingresar(),
                    decoration: InputDecoration(
                      labelText: 'CÓDIGO O CONTRASEÑA',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, color: C.suave, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(_verCod ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined, color: C.suave, size: 20),
                        onPressed: () => setState(() => _verCod = !_verCod),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: C.rojo.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: C.rojo.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline_rounded,
                          color: C.rojo, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_error!,
                          style: const TextStyle(color: C.rojo, fontSize: 13))),
                      ]),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // BOTÓN ÚNICO
                  ElevatedButton(
                    onPressed: _loading ? null : _ingresar,
                    child: _loading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Ingresar'),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              const Text('Universidad de La Guajira',
                style: TextStyle(color: C.suave, fontSize: 11)),
            ]),
          ),
        ),
      ),
    );
  }
}
