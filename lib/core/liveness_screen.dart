import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'theme.dart';

enum _Reto { parpadear, sonreir, girar }

/// Verificación de vida activa: el usuario debe cumplir 2 retos aleatorios
/// (parpadear, sonreír, girar la cabeza) y luego mirar de frente. Solo entonces
/// se toma la foto. Devuelve la foto en base64 (JPEG) o null si cancela.
class LivenessScreen extends StatefulWidget {
  final CameraDescription camera;
  final String titulo;
  const LivenessScreen({super.key, required this.camera, required this.titulo});

  static Future<String?> abrir(BuildContext context,
      {String titulo = 'Verificación facial'}) async {
    final cams = await availableCameras();
    if (cams.isEmpty) return null;
    final front = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );
    if (!context.mounted) return null;
    return Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => LivenessScreen(camera: front, titulo: titulo)));
  }

  @override
  State<LivenessScreen> createState() => _LivenessState();
}

class _LivenessState extends State<LivenessScreen> {
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };
  static const _limite = Duration(seconds: 30);

  late final CameraController _ctrl;
  late final FaceDetector _detector;
  late final List<_Reto> _retos;
  Timer? _timer;

  bool _ready = false, _busy = false, _capturando = false, _expiro = false;
  int _paso = 0;            // 0..1 retos, 2 = mirar de frente y capturar
  int _frontales = 0;       // frames consecutivos válidos de frente
  bool _vioAbiertos = false, _vioCerrados = false; // máquina del parpadeo
  bool _sinRostro = true;

  @override
  void initState() {
    super.initState();
    final todos = _Reto.values.toList()..shuffle(Random.secure());
    _retos = todos.take(2).toList();
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.3,
      ),
    );
    _iniciar();
  }

  Future<void> _iniciar() async {
    _ctrl = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    try {
      await _ctrl.initialize();
      if (!mounted) return;
      await _ctrl.startImageStream(_procesar);
      setState(() => _ready = true);
      _timer = Timer(_limite, () {
        if (mounted && !_capturando) {
          _ctrl.stopImageStream().catchError((_) {});
          setState(() => _expiro = true);
        }
      });
    } catch (_) {
      if (mounted) Navigator.pop(context, null);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _detector.close();
    _ctrl.dispose();
    super.dispose();
  }

  InputImage? _aInputImage(CameraImage image) {
    final sensor = widget.camera.sensorOrientation;
    InputImageRotation? rot;
    if (Platform.isIOS) {
      rot = InputImageRotationValue.fromRawValue(sensor);
    } else {
      var comp = _orientations[_ctrl.value.deviceOrientation];
      if (comp == null) return null;
      comp = widget.camera.lensDirection == CameraLensDirection.front
          ? (sensor + comp) % 360
          : (sensor - comp + 360) % 360;
      rot = InputImageRotationValue.fromRawValue(comp);
    }
    if (rot == null) return null;
    final fmt = InputImageFormatValue.fromRawValue(image.format.raw);
    if (fmt == null ||
        (Platform.isAndroid && fmt != InputImageFormat.nv21) ||
        (Platform.isIOS && fmt != InputImageFormat.bgra8888) ||
        image.planes.length != 1) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rot,
        format: fmt,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _procesar(CameraImage img) async {
    if (_busy || _capturando || _expiro) return;
    _busy = true;
    try {
      final input = _aInputImage(img);
      if (input == null) return;
      final rostros = await _detector.processImage(input);
      if (!mounted) return;
      if (rostros.length != 1) {
        // 0 rostros o más de uno: reinicia el avance del paso actual
        setState(() => _sinRostro = rostros.isEmpty);
        _frontales = 0;
        return;
      }
      if (_sinRostro) setState(() => _sinRostro = false);
      await _evaluar(rostros.first);
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  Future<void> _evaluar(Face f) async {
    final yaw = (f.headEulerAngleY ?? 0).abs();
    final ojoI = f.leftEyeOpenProbability ?? 1;
    final ojoD = f.rightEyeOpenProbability ?? 1;
    final sonrisa = f.smilingProbability ?? 0;

    if (_paso < 2) {
      bool ok = false;
      switch (_retos[_paso]) {
        case _Reto.parpadear:
          if (ojoI > 0.7 && ojoD > 0.7) {
            if (_vioCerrados) ok = true; else _vioAbiertos = true;
          } else if (_vioAbiertos && ojoI < 0.25 && ojoD < 0.25) {
            _vioCerrados = true;
          }
          break;
        case _Reto.sonreir:
          ok = sonrisa > 0.8;
          break;
        case _Reto.girar:
          ok = yaw > 25;
          break;
      }
      if (ok) {
        HapticFeedback.lightImpact();
        setState(() { _paso++; _vioAbiertos = false; _vioCerrados = false; _frontales = 0; });
      }
      return;
    }

    // Paso final: de frente, ojos abiertos, sin sonreír exagerado, varios frames seguidos
    final bien = yaw < 10 && ojoI > 0.6 && ojoD > 0.6 && sonrisa < 0.6;
    _frontales = bien ? _frontales + 1 : 0;
    if (_frontales >= 4) await _capturar();
  }

  Future<void> _capturar() async {
    if (_capturando) return;
    setState(() => _capturando = true);
    try {
      await _ctrl.stopImageStream();
      final xf = await _ctrl.takePicture();
      final bytes = await File(xf.path).readAsBytes();
      try { await File(xf.path).delete(); } catch (_) {}
      if (mounted) Navigator.pop(context, base64Encode(bytes));
    } catch (_) {
      if (mounted) Navigator.pop(context, null);
    }
  }

  String get _instruccion {
    if (_expiro) return 'Se acabó el tiempo';
    if (_sinRostro) return 'Coloca tu rostro dentro del círculo';
    if (_paso >= 2) return 'Mira de frente y quédate quieto';
    switch (_retos[_paso]) {
      case _Reto.parpadear: return 'Parpadea una vez';
      case _Reto.sonreir:   return 'Sonríe';
      case _Reto.girar:     return 'Gira la cabeza hacia un lado';
    }
  }

  void _reintentar() {
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => LivenessScreen(camera: widget.camera, titulo: widget.titulo)));
  }

  @override
  Widget build(BuildContext context) {
    final color = _expiro ? C.rojo : (_paso >= 2 ? C.verdeClaro : C.dorado);
    return Scaffold(
      backgroundColor: C.oscuro,
      appBar: AppBar(
        title: Text(widget.titulo),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, null)),
      ),
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 3; i++) ...[
              Container(
                width: 34, height: 6,
                decoration: BoxDecoration(
                  color: i < _paso || (_paso >= 2 && i == 2 && _capturando) ? C.verdeClaro : C.borde,
                  borderRadius: BorderRadius.circular(3)),
              ),
              if (i < 2) const SizedBox(width: 8),
            ],
          ]),
          const Spacer(),
          Container(
            width: 300, height: 300,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 4)),
            child: ClipOval(
              child: _ready
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _ctrl.value.previewSize!.height,
                        height: _ctrl.value.previewSize!.width,
                        child: CameraPreview(_ctrl),
                      ))
                  : const Center(child: CircularProgressIndicator(color: C.verde)),
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_instruccion, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Text('Paso ${_paso >= 2 ? 3 : _paso + 1} de 3',
              style: TextStyle(color: C.suave, fontSize: 12)),
          const Spacer(),
          if (_expiro)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: ElevatedButton(onPressed: _reintentar, child: const Text('Intentar de nuevo')),
            )
          else
            Padding(
              padding: EdgeInsets.fromLTRB(32, 0, 32, 24),
              child: Text('Buena luz, sin gorra ni gafas oscuras.',
                  textAlign: TextAlign.center, style: TextStyle(color: C.suave, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}
