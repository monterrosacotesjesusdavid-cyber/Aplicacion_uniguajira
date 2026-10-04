import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/liveness_screen.dart';
import '../../core/ui_kit.dart';

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

  Widget _cabecera(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          24, MediaQuery.of(context).padding.top + 36, 24, 84),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [C.verde, Color(0xFF005D6E)]),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
        ),
        child: Column(children: [
          // Escudo de la universidad sobre una pieza blanca
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(color: Color(0x30000000), blurRadius: 26, offset: Offset(0, 10)),
              ],
            ),
            child: Image.asset('assets/logo.png', height: 100, fit: BoxFit.contain),
          ),
          const SizedBox(height: 24),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 24, height: 3,
              decoration: BoxDecoration(
                color: C.dorado, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Text('CONTROL DE ASISTENCIA',
              style: TextStyle(color: Colors.white.withOpacity(0.88),
                fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
          ]),
        ]),
      );

  InputDecoration _campo(String etiqueta, IconData icono, {Widget? sufijo}) =>
      InputDecoration(
        labelText: etiqueta,
        filled: true,
        fillColor: C.fondo,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: const TextStyle(color: C.suave, fontSize: 14),
        prefixIcon: Icon(icono, color: C.verdeClaro, size: 21),
        suffixIcon: sufijo,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
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

  Widget _formulario() => Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        decoration: BoxDecoration(
          color: C.sup,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: C.borde),
          boxShadow: const [
            BoxShadow(color: Color(0x1A06222A), blurRadius: 28, offset: Offset(0, 12)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Bienvenido',
            style: TextStyle(color: C.tinta, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Ingresa con tus credenciales institucionales',
            style: TextStyle(color: C.suave, fontSize: 13.5)),
          const SizedBox(height: 22),

          TextField(
            controller: _idCtrl,
            style: const TextStyle(color: C.tinta, fontSize: 15.5),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: _campo('Usuario, cédula o correo', Icons.person_outline_rounded),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _codCtrl,
            obscureText: !_verCod,
            style: const TextStyle(color: C.tinta, fontSize: 15.5),
            onSubmitted: (_) => _ingresar(),
            decoration: _campo('Código o contraseña', Icons.lock_outline_rounded,
              sufijo: IconButton(
                icon: Icon(_verCod ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined, color: C.suave, size: 21),
                onPressed: () => setState(() => _verCod = !_verCod))),
          ),
          const SizedBox(height: 20),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: C.rojo.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.rojo.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded, color: C.rojo, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(_error!,
                  style: const TextStyle(color: C.rojo, fontSize: 13))),
              ]),
            ),
            const SizedBox(height: 14),
          ],

          ElevatedButton(
            onPressed: _loading ? null : _ingresar,
            style: estiloBoton(alto: 54),
            child: _loading
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Ingresar', style: TextStyle(fontSize: 15.5,
                    fontWeight: FontWeight.w600, color: Colors.white)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 19, color: Colors.white),
                ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: C.fondo,
        body: SingleChildScrollView(
          child: Column(children: [
            _cabecera(context),
            // El formulario se monta sobre el borde inferior de la cabecera.
            Transform.translate(
              offset: const Offset(0, -48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 550),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, child) => Opacity(
                    opacity: v,
                    child: Transform.translate(
                      offset: Offset(0, (1 - v) * 24), child: child)),
                  child: _formulario(),
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -24),
              child: Column(children: [
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 28, height: 3, child: ColoredBox(color: C.verde)),
                  SizedBox(width: 28, height: 3, child: ColoredBox(color: C.dorado)),
                  SizedBox(width: 28, height: 3, child: ColoredBox(color: C.rojo)),
                ]),
                const SizedBox(height: 12),
                const Text('Universidad de La Guajira',
                  style: TextStyle(color: C.suave, fontSize: 12)),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
