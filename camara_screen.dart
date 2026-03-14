import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'theme.dart';

class CamaraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CamaraScreen({super.key, required this.camera});

  static Future<String?> abrir(BuildContext context) async {
    final cams = await availableCameras();
    final front = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );
    if (!context.mounted) return null;
    return Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => CamaraScreen(camera: front)),
    );
  }

  @override
  State<CamaraScreen> createState() => _CamaraState();
}

class _CamaraState extends State<CamaraScreen> {
  late CameraController _ctrl;
  bool _ready = false;
  File? _foto;

  @override
  void initState() {
    super.initState();
    _ctrl = CameraController(widget.camera, ResolutionPreset.medium, enableAudio: false);
    _ctrl.initialize().then((_) { if (mounted) setState(() => _ready = true); });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _tomar() async {
    try {
      final xf = await _ctrl.takePicture();
      setState(() => _foto = File(xf.path));
    } catch (_) {}
  }

  Future<void> _confirmar() async {
    if (_foto == null) return;
    final bytes = await _foto!.readAsBytes();
    if (mounted) Navigator.pop(context, base64Encode(bytes));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      title: const Text('Foto de verificación'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context, null),
      ),
    ),
    body: Column(children: [
      Expanded(
        child: _foto != null
          ? Image.file(_foto!, fit: BoxFit.cover, width: double.infinity)
          : (_ready
              ? CameraPreview(_ctrl)
              : const Center(child: CircularProgressIndicator(color: C.verde))),
      ),
      Container(
        color: C.oscuro, padding: const EdgeInsets.all(20),
        child: _foto == null
          ? ElevatedButton.icon(
              onPressed: _tomar,
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Tomar foto'),
            )
          : Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => setState(() => _foto = null),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: C.borde),
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Repetir'),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: _confirmar,
                child: const Text('Confirmar'),
              )),
            ]),
      ),
    ]),
  );
}
