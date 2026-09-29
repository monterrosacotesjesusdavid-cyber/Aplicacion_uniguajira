import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'liveness_screen.dart';
import 'offline.dart';
import 'theme.dart';

// ══════════════════════════════════════════════════════════════════════
//  ENVÍO DE EVIDENCIAS: exige reconocimiento facial y sube la cola.
// ══════════════════════════════════════════════════════════════════════
class SyncResult {
  final int enviadas;
  final int descartadas;
  final List<String> avisos;
  final String? error;
  const SyncResult(this.enviadas, this.descartadas, this.avisos, this.error);
  factory SyncResult.err(String m) => SyncResult(0, 0, const [], m);

  String get resumen {
    if (error != null && enviadas == 0 && descartadas == 0) return error!;
    final p = <String>[];
    if (enviadas > 0) {
      p.add('$enviadas enviada${enviadas == 1 ? '' : 's'} — quedan pendientes de aprobación del administrador');
    }
    if (descartadas > 0) {
      p.add('$descartadas no se pudo${descartadas == 1 ? '' : 'ieron'} registrar: ${avisos.join('; ')}');
    }
    if (error != null) p.add(error!);
    return p.join('\n');
  }
}

class Sync {
  static bool _ocupado = false;

  static Future<SyncResult> enviar(BuildContext context) async {
    if (_ocupado) return SyncResult.err('Ya se están enviando');
    _ocupado = true;
    try {
      final items = await OfflineQueue.listar();
      if (items.isEmpty) return const SyncResult(0, 0, [], null);
      if (!await Net.hayInternet()) return SyncResult.err('Aún no hay conexión a internet');

      if (!await _asegurarSesion(context)) {
        return SyncResult.err('Necesitas iniciar sesión con internet para enviar');
      }
      if (!context.mounted) return SyncResult.err('Envío cancelado');

      // Identidad: selfie con prueba de vida ANTES de enviar nada.
      final selfie = await LivenessScreen.abrir(context, titulo: 'Confirma tu identidad para enviar');
      if (selfie == null) return SyncResult.err('Envío cancelado');

      var ok = 0, desc = 0;
      final avisos = <String>[];
      String? corte;
      for (final it in items) {
        final foto = await OfflineQueue.fotoBase64(it);
        if (foto == null) {
          await OfflineQueue.quitar(it['client_id']);
          continue;
        }
        Map<String, dynamic> r;
        try {
          r = await Api.sincronizarOffline({
            'client_id': it['client_id'],
            'horario_id': it['horario_id'],
            'latitud': it['lat'],
            'longitud': it['lon'],
            'hora_dispositivo': it['ts'],
            'foto_evidencia_base64': foto,
            'foto_verificacion_base64': selfie,
            'liveness': true,
          });
        } catch (_) {
          corte = 'Se perdió la conexión. Se reintentará después.';
          break;
        }
        final st = r['_status'] as int;
        if (st == 200) {
          await OfflineQueue.quitar(it['client_id']);
          ok++;
        } else if (st == 400 || st == 404 || st == 409) {
          // El servidor la rechazó de forma definitiva (fecha inválida, ya registrada…)
          await OfflineQueue.quitar(it['client_id']);
          desc++;
          avisos.add('${it['materia']}: ${r['error'] ?? 'inválida'}');
        } else {
          // Rostro no coincide, servicio caído, límite de solicitudes…: se conserva la cola.
          corte = r['error']?.toString() ?? 'No se pudo enviar';
          break;
        }
      }
      return SyncResult(ok, desc, avisos, corte);
    } finally {
      _ocupado = false;
    }
  }

  /// Si el token venció (o no existe porque entró sin internet), pide el código.
  static Future<bool> _asegurarSesion(BuildContext context) async {
    final st = await Api.probarSesion();
    if (st == 200) return true;
    if (st == -1) return false;
    final g = await OfflineAuth.perfil();
    if (g == null || !context.mounted) return false;
    final ctrl = TextEditingController();
    final codigo = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirma tu código', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'CÓDIGO'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: C.suave))),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Continuar', style: TextStyle(color: C.verdeClaro))),
        ],
      ),
    );
    if (codigo == null || codigo.isEmpty) return false;
    final d = await Api.login(g['ident'] as String, codigo);
    return d['_status'] == 200 && d['offline'] != true;
  }
}

// ══════════════════════════════════════════════════════════════════════
//  BANNER: estado de conexión + pendientes + botón de envío.
//  Vigila el internet cada 15 s (solo mientras la pantalla está abierta) y,
//  cuando vuelve, ofrece enviar con reconocimiento facial.
// ══════════════════════════════════════════════════════════════════════
class OfflineBanner extends StatefulWidget {
  /// Se llama al recuperar internet o después de enviar (para recargar datos).
  final VoidCallback onCambio;
  const OfflineBanner({super.key, required this.onCambio});
  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  Timer? _timer;
  int _pend = 0;
  List _mis = [];
  bool _enviando = false, _ofrecido = false;

  @override
  void initState() {
    super.initState();
    Net.offline.addListener(_redibujar);
    OfflineQueue.cambios.addListener(_refrescarCola);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
    _refrescarCola().then((_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    Net.offline.removeListener(_redibujar);
    OfflineQueue.cambios.removeListener(_refrescarCola);
    super.dispose();
  }

  void _redibujar() {
    if (mounted) setState(() {});
  }

  Future<void> _refrescarCola() async {
    final n = await OfflineQueue.contar();
    if (mounted) setState(() => _pend = n);
  }

  Future<void> _cargarMis() async {
    try {
      final l = await Api.misEvidencias();
      if (mounted) setState(() => _mis = l.where((e) => e['estado'] != 'aprobada').take(4).toList());
    } catch (_) {}
  }

  Future<void> _tick() async {
    if (!mounted || _enviando) return;
    if (!Net.offline.value && _pend == 0) return;
    final hay = await Net.hayInternet();
    if (!mounted) return;
    if (!hay) {
      _ofrecido = false;
      return;
    }
    if (Net.offline.value) {
      Net.offline.value = false; // volvió el internet
      widget.onCambio();
    }
    _cargarMis();
    if (_pend > 0 && !_ofrecido) {
      _ofrecido = true;
      _ofrecerEnvio();
    }
  }

  Future<void> _ofrecerEnvio() async {
    final si = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Volvió el internet', style: TextStyle(color: Colors.white)),
        content: Text(
          'Tienes $_pend asistencia${_pend == 1 ? '' : 's'} guardada${_pend == 1 ? '' : 's'} sin conexión.\n\n'
          'Para enviarla${_pend == 1 ? '' : 's'} debes confirmar tu identidad con reconocimiento facial. '
          'Después un administrador la${_pend == 1 ? '' : 's'} revisará.',
          style: const TextStyle(color: C.suave)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Después', style: TextStyle(color: C.suave))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Enviar ahora', style: TextStyle(color: C.verdeClaro))),
        ],
      ),
    );
    if (si == true && mounted) await _enviar();
  }

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    final r = await Sync.enviar(context);
    if (!mounted) return;
    setState(() => _enviando = false);
    await _refrescarCola();
    _cargarMis();
    widget.onCambio();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.resumen),
      duration: const Duration(seconds: 6),
      backgroundColor: (r.error != null && r.enviadas == 0) ? C.rojo : C.verde,
    ));
  }

  Widget _caja(Color color, IconData icono, String texto, {Widget? accion}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icono, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(texto,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
          if (accion != null) ...[const SizedBox(height: 10), accion],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final off = Net.offline.value;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (off)
        _caja(Colors.orange, Icons.cloud_off_rounded,
            'Sin conexión — mostrando datos guardados. Puedes tomar tu evidencia con foto '
            'y se enviará cuando vuelva el internet.'),
      if (_pend > 0)
        _caja(
          C.dorado, Icons.upload_file_rounded,
          '$_pend asistencia${_pend == 1 ? '' : 's'} pendiente${_pend == 1 ? '' : 's'} de envío',
          accion: ElevatedButton.icon(
            onPressed: (off || _enviando) ? null : _enviar,
            icon: _enviando
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.face_retouching_natural_rounded, size: 18),
            label: Text(off ? 'Se podrá enviar cuando haya internet'
                : _enviando ? 'Enviando...' : 'Enviar con reconocimiento facial'),
            style: ElevatedButton.styleFrom(
                backgroundColor: C.verde, disabledBackgroundColor: C.borde,
                minimumSize: const Size(0, 42)),
          ),
        ),
      if (_mis.isNotEmpty)
        _caja(
          C.azul, Icons.fact_check_rounded,
          'Tus envíos recientes\n' +
              _mis.map((e) {
                final est = e['estado'] == 'pendiente'
                    ? 'en revisión'
                    : 'rechazada${(e['motivo'] ?? '').toString().isNotEmpty ? ' (${e['motivo']})' : ''}';
                return '• ${e['materia']} ${e['fecha']}: $est';
              }).join('\n'),
        ),
    ]);
  }
}
