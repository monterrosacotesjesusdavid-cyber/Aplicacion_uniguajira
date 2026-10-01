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

class _FotoSalonState extends State<FotoSalonScreen> {
  CameraController? _ctrl;
  XFile? _foto;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      final c = CameraController(widget.camera, ResolutionPreset.medium,
          enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _ctrl = c);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo abrir la cámara');
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _tomar() async {
    if (_ctrl == null || _busy) return;
    setState(() => _busy = true);
    try {
      final f = await _ctrl!.takePicture();
      if (mounted) setState(() => _foto = f);
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
              child: _error != null
                  ? Text(_error!,
                      style: const TextStyle(color: Colors.redAccent))
                  : foto != null
                      ? Image.file(File(foto.path))
                      : (_ctrl == null
                          ? const CircularProgressIndicator()
                          : CameraPreview(_ctrl!)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: foto == null
                ? SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_ctrl == null || _busy) ? null : _tomar,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Tomar foto'),
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
