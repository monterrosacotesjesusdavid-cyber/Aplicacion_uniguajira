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
  final _idFocus  = FocusNode();
  final _codFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Para que el icono y el borde reaccionen al enfocar el campo.
    _idFocus.addListener(() => setState(() {}));
    _codFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _idCtrl.dispose(); _codCtrl.dispose();
    _idFocus.dispose(); _codFocus.dispose();
    super.dispose();
  }

  InputDecoration _campo(String etiqueta, IconData icono, FocusNode foco,
      {Widget? sufijo}) {
    final activo = foco.hasFocus;
    return InputDecoration(
      labelText: etiqueta,
      filled: true,
      fillColor: activo ? Colors.white : C.fondo,
      labelStyle: TextStyle(
        color: activo ? C.verde : C.suave, fontSize: 15),
      prefixIcon: Icon(icono, color: activo ? C.verde : C.suave, size: 21),
      suffixIcon: sufijo,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: C.borde)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: C.borde)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: C.verde, width: 1.8)),
    );
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
        color: Colors.white,
        child: SafeArea(
          child: Center(child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(children: [
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
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
                builder: (_, v, child) => Opacity(
                  opacity: v,
                  child: Transform.translate(
                    offset: Offset(0, (1 - v) * 16), child: child)),
                child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: C.borde),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14062A33), blurRadius: 24, offset: Offset(0, 10)),
                  ],
                ),
                child: Column(children: [
                  // Franja con los colores del escudo en el borde de la tarjeta
                  const SizedBox(height: 4, child: Row(children: [
                    Expanded(child: ColoredBox(color: C.verde)),
                    Expanded(child: ColoredBox(color: C.dorado)),
                    Expanded(child: ColoredBox(color: C.rojo)),
                  ])),
                  Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [

                  TextField(
                    focusNode: _idFocus,
                    controller: _idCtrl,
                    style: const TextStyle(color: C.tinta),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: _campo('Usuario, cédula o correo',
                      Icons.person_outline_rounded, _idFocus),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    focusNode: _codFocus,
                    controller: _codCtrl,
                    obscureText: !_verCod,
                    style: const TextStyle(color: C.tinta),
                    onSubmitted: (_) => _ingresar(),
                    decoration: _campo('Código o contraseña',
                      Icons.lock_outline_rounded, _codFocus,
                      sufijo: IconButton(
                        icon: Icon(_verCod ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined, color: C.suave, size: 20),
                        onPressed: () => setState(() => _verCod = !_verCod),
                      )),
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
                      : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('Ingresar'),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 19),
                        ]),
                  ),
                ]),
                  ),
                ]),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Universidad de La Guajira',
                style: TextStyle(color: C.suave, fontSize: 11)),
            ]),
          )),
        ),
      ),
    );
  }
}
