import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Foto con la cámara trasera: prueba de que el profesor está en el salón.
/// Devuelve la foto en base64 (JPEG) o null si cancela.
class FotoSalonScreen extends StatefulWidget {
  final CameraDescription camera;
  const FotoSalonScreen({super.key, required this.camera});

  static Future<String?> abrir(BuildContext context) async {
    final cams = await availableCameras();
    if (cams.isEmpty) return null;
    final back = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );
    if (!context.mounted) return null;
    return Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => FotoSalonScreen(camera: back)),
    );
  }

  @override
  State<FotoSalonScreen> createState() => _FotoSalonState();
}

class _FotoSalonState extends State<FotoSalonScreen> with WidgetsBindingObserver {
  CameraController? _ctrl;
  XFile? _foto;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _iniciar();
  }

  /// Libera la cámara actual antes de abrir otra (evita conflictos entre cámaras).
  Future<void> _liberar() async {
    final c = _ctrl;
    _ctrl = null;
    if (c != null) {
      try { await c.dispose(); } catch (_) {}
    }
  }

  Future<void> _iniciar() async {
    await _liberar();
    if (mounted) setState(() => _error = null);
    // Pequeña pausa: da tiempo a que Android suelte la cámara anterior.
    await Future.delayed(const Duration(milliseconds: 250));
    try {
      final c = CameraController(
        widget.camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await c.initialize();
      try { await c.setFlashMode(FlashMode.off); } catch (_) {}
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _ctrl = c);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = 'No se pudo abrir la cámara (${e.code})');
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo abrir la cámara');
    }
  }

  // Si la app pasa a segundo plano se suelta la cámara; al volver se reabre.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _liberar();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _ctrl == null && _foto == null) {
      _iniciar();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _tomar() async {
    if (_ctrl == null || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      XFile f;
      try {
        f = await _ctrl!.takePicture();
      } catch (_) {
        // Algunos celulares fallan la primera vez: se reabre la cámara y se reintenta.
        await _iniciar();
        if (_ctrl == null) rethrow;
        await Future.delayed(const Duration(milliseconds: 300));
        f = await _ctrl!.takePicture();
      }
      if (mounted) setState(() => _foto = f);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = 'No se pudo tomar la foto (${e.code})');
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo tomar la foto');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _usar() async {
    final f = _foto;
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    Navigator.pop(context, base64Encode(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final foto = _foto;
    final ctrl = _ctrl;
    final sinCamara = ctrl == null && foto == null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Foto del salón'),
      ),
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Toma una foto a los estudiantes en el salón, con la cámara trasera, como prueba de que estás en clase.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
          Expanded(
            child: Center(
              child: foto != null
                  ? Image.file(File(foto.path))
                  : (ctrl != null && ctrl.value.isInitialized)
                      ? CameraPreview(ctrl)
                      : (_error != null
                          ? const SizedBox.shrink()
                          : const CircularProgressIndicator()),
            ),
          ),
          // El error no oculta la cámara: se muestra aparte y se puede reintentar.
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: foto == null
                ? SizedBox(
                    width: double.infinity,
                    child: sinCamara
                        ? FilledButton.icon(
                            onPressed: _iniciar,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                          )
                        : FilledButton.icon(
                            onPressed: _busy ? null : _tomar,
                            icon: const Icon(Icons.camera_alt),
                            label: Text(_busy ? 'Tomando...' : 'Tomar foto'),
                          ),
                  )
                : Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _foto = null),
                        child: const Text('Repetir'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _usar,
                        child: const Text('Usar esta foto'),
                      ),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }
}
