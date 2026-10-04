import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  InputDecoration _campo(String etiqueta, {Widget? sufijo}) => InputDecoration(
        labelText: etiqueta,
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: C.suave, fontSize: 15),
        suffixIcon: sufijo,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: C.borde)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: C.borde)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: C.verde, width: 2)),
      );

  /// Franja con los tres colores del escudo, pegada al borde superior.
  Widget _franja() => const SizedBox(
        height: 6,
        child: Row(children: [
          Expanded(child: ColoredBox(color: C.verde)),
          Expanded(child: ColoredBox(color: C.dorado)),
          Expanded(child: ColoredBox(color: C.rojo)),
        ]));

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final anchoLogo = (mq.size.width * 0.66).clamp(200.0, 300.0).toDouble();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(fit: StackFit.expand, children: [
          // Escudo muy tenue como marca de agua, cortado por la esquina.
          Positioned(
            right: -80, bottom: -60,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.07,
                child: Image.asset('assets/escudo.png', width: 340)))),

          LayoutBuilder(builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: IntrinsicHeight(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(height: mq.padding.top),
                  _franja(),
                  const Spacer(flex: 2),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: anchoLogo,
                        child: Image.asset('assets/logo.png', fit: BoxFit.contain)),
                      const SizedBox(height: 44),
                      const Text('Control de Asistencia',
                        style: TextStyle(color: C.tinta, fontSize: 24,
                          fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text('Ingresa con tus credenciales institucionales',
                        style: TextStyle(color: C.suave, fontSize: 14.5)),
                      const SizedBox(height: 28),

                      TextField(
                        controller: _idCtrl,
                        style: const TextStyle(color: C.tinta, fontSize: 16),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: _campo('Usuario, cédula o correo'),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _codCtrl,
                        obscureText: !_verCod,
                        style: const TextStyle(color: C.tinta, fontSize: 16),
                        onSubmitted: (_) => _ingresar(),
                        decoration: _campo('Código o contraseña',
                          sufijo: IconButton(
                            icon: Icon(_verCod ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined, color: C.suave, size: 22),
                            onPressed: () => setState(() => _verCod = !_verCod))),
                      ),
                      const SizedBox(height: 22),

                      if (_error != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: C.rojo.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: C.rojo.withOpacity(0.35))),
                          child: Text(_error!,
                            style: const TextStyle(color: C.rojo, fontSize: 13.5)),
                        ),
                        const SizedBox(height: 16),
                      ],

                      ElevatedButton(
                        onPressed: _loading ? null : _ingresar,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 54)),
                        child: _loading
                          ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white))
                          : const Text('Ingresar', style: TextStyle(fontSize: 16)),
                      ),
                    ]),
                  ),

                  const Spacer(flex: 3),
                  Center(
                    child: Text('© ${DateTime.now().year} Universidad de La Guajira',
                      style: const TextStyle(color: C.suave, fontSize: 12))),
                  SizedBox(height: mq.padding.bottom + 18),
                ]),
              ),
            ),
          )),
        ]),
      ),
    );
  }
}
