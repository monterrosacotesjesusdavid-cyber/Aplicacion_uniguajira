import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../estudiante/estudiante_home.dart';
import '../profesor/profesor_home.dart';
import '../admin/admin_home.dart';

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

  // Modo: 'usuario' (estudiante+profesor) o 'admin'
  bool _modoAdmin = false;

  // Para admin
  final _correoCtrl = TextEditingController();
  final _passCtrl   = TextEditingController();
  bool _verPass     = false;

  @override
  void dispose() {
    _idCtrl.dispose(); _codCtrl.dispose();
    _correoCtrl.dispose(); _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    setState(() { _loading = true; _error = null; });
    try {
      Map<String, dynamic> data;
      if (_modoAdmin) {
        if (_correoCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
          setState(() { _error = 'Completa todos los campos'; _loading = false; });
          return;
        }
        data = await Api.loginAdmin(_correoCtrl.text.trim(), _passCtrl.text);
      } else {
        if (_idCtrl.text.trim().isEmpty || _codCtrl.text.trim().isEmpty) {
          setState(() { _error = 'Completa todos los campos'; _loading = false; });
          return;
        }
        data = await Api.login(_idCtrl.text.trim(), _codCtrl.text.trim());
      }
      if (!mounted) return;
      if (data['_status'] == 200) {
        final rol = data['rol'] as String;
        Widget dest;
        if (rol == 'admin')        dest = const AdminHome();
        else if (rol == 'profesor') dest = const ProfesorHome();
        else                        dest = const EstudianteHome();
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
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.4, -0.3), radius: 1.5,
            colors: [Color(0xFF003D28), C.oscuro, Color(0xFF000D08)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(children: [
              const SizedBox(height: 36),

              // Logo
              Container(
                width: 84, height: 84,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [C.verde, C.verdeClaro],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: C.verdeClaro.withOpacity(0.3),
                    blurRadius: 32, spreadRadius: 6,
                  )],
                ),
                child: const Icon(Icons.school_rounded, color: Colors.white, size: 42),
              ),
              const SizedBox(height: 20),
              const Text('UNIVERSIDAD DE LA GUAJIRA',
                style: TextStyle(color: C.doradoClaro, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 3)),
              const SizedBox(height: 6),
              const Text('Control de Asistencia',
                style: TextStyle(color: Colors.white, fontSize: 24,
                  fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Sistema institucional de registro',
                style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12)),
              const SizedBox(height: 36),

              // Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: C.dorado.withOpacity(0.2)),
                ),
                child: Column(children: [

                  // Toggle Admin
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('Soy administrador',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                    const SizedBox(width: 8),
                    Switch(
                      value: _modoAdmin,
                      activeColor: C.dorado,
                      onChanged: (v) => setState(() { _modoAdmin = v; _error = null; }),
                    ),
                  ]),
                  const SizedBox(height: 8),

                  if (!_modoAdmin) ...[
                    // Modo estudiante / profesor
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: C.verde.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: C.verde.withOpacity(0.2)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded, color: C.verdeClaro, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          'Estudiante: escribe tu usuario (sin @)\nProfesor: escribe tu cédula',
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                        )),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _idCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        labelText: 'USUARIO O CÉDULA',
                        hintText: 'jdavidmonterrosa  ó  1234567890',
                        prefixIcon: Icon(Icons.person_outline_rounded, color: C.suave, size: 20),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _codCtrl,
                      obscureText: !_verCod,
                      style: const TextStyle(color: Colors.white),
                      onSubmitted: (_) => _ingresar(),
                      decoration: InputDecoration(
                        labelText: 'CÓDIGO',
                        hintText: '••••••',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, color: C.suave, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(_verCod ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined, color: C.suave, size: 20),
                          onPressed: () => setState(() => _verCod = !_verCod),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Modo admin
                    TextField(
                      controller: _correoCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'CORREO ADMIN',
                        prefixIcon: Icon(Icons.email_outlined, color: C.suave, size: 20),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passCtrl,
                      obscureText: !_verPass,
                      style: const TextStyle(color: Colors.white),
                      onSubmitted: (_) => _ingresar(),
                      decoration: InputDecoration(
                        labelText: 'CONTRASEÑA',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, color: C.suave, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(_verPass ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined, color: C.suave, size: 20),
                          onPressed: () => setState(() => _verPass = !_verPass),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: C.rojo.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: C.rojo.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline_rounded,
                          color: Color(0xFFFF6B6B), size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_error!,
                          style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13))),
                      ]),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // BOTÓN ÚNICO
                  ElevatedButton(
                    onPressed: _loading ? null : _ingresar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _modoAdmin ? C.dorado : C.verde,
                    ),
                    child: _loading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_modoAdmin ? 'Ingresar como Admin' : 'Ingresar'),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              Text('© 2024 Universidad de La Guajira',
                style: TextStyle(color: Colors.white.withOpacity(0.18),
                  fontSize: 11, letterSpacing: 1)),
            ]),
          ),
        ),
      ),
    );
  }
}
