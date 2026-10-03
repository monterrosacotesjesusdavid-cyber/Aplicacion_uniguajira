import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

// ══════════════════════════════════════════════════════════════════════
//  RED: detecta si REALMENTE hay internet (no solo si hay WiFi conectado).
//  En la universidad el WiFi suele estar "conectado" sin salida a internet,
//  por eso se hace una petición corta al servidor en vez de mirar la señal.
// ══════════════════════════════════════════════════════════════════════
class Net {
  /// true cuando la app está mostrando datos guardados por falta de conexión.
  static final ValueNotifier<bool> offline = ValueNotifier(false);

  static Future<bool> hayInternet() async {
    try {
      final r = await http
          .get(Uri.parse(kBase.replaceFirst(RegExp(r'/api$'), '/health')))
          .timeout(const Duration(seconds: 4));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static bool esErrorDeRed(Object e) =>
      e is SocketException || e is TimeoutException || e is http.ClientException;
}

// ══════════════════════════════════════════════════════════════════════
//  CACHÉ por usuario (clases, horario, historial)
// ══════════════════════════════════════════════════════════════════════
class Cache {
  static Future<String> _k(String name) async {
    final p = await SharedPreferences.getInstance();
    return 'cache:${p.getString('rol')}:${p.getInt('userId')}:$name';
  }

  static Future<void> put(String name, Object data) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(await _k(name), jsonEncode(data));
  }

  static Future<dynamic> get(String name) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(await _k(name));
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════
//  VENTANA LOCAL (sin servidor, con la hora del celular)
// ══════════════════════════════════════════════════════════════════════
class VentanaLocal {
  final bool disponible;
  final String mensaje;
  const VentanaLocal(this.disponible, this.mensaje);

  static int _min(String t) {
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  static String _hhmm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  /// Sin conexión se permite tomar evidencia desde 15 min antes hasta el fin
  /// de la clase. La decisión final (a tiempo / tardanza) la toma el servidor
  /// y el administrador al revisar.
  static VentanaLocal calcular(String ini, String fin, {DateTime? ahora}) {
    final n = ahora ?? DateTime.now();
    final m = n.hour * 60 + n.minute;
    final i = _min(ini), f = _min(fin);
    if (m < i - 15) return VentanaLocal(false, 'Disponible a las ${_hhmm(i - 15)}');
    if (m <= f) return const VentanaLocal(true, 'Sin conexión: quedará pendiente de revisión');
    return const VentanaLocal(false, 'Tiempo expirado — Ausente');
  }
}

// ══════════════════════════════════════════════════════════════════════
//  LOGIN OFFLINE
//  Al iniciar sesión con internet se guarda (en el almacenamiento cifrado
//  del celular) un verificador del código: NUNCA el código en claro.
//  Solo sirve para abrir la app en ESTE celular y ver las clases guardadas;
//  no genera ningún token del servidor.
// ══════════════════════════════════════════════════════════════════════
String _derive(List a) {
  final pw = utf8.encode(a[0] as String);
  final salt = base64Decode(a[1] as String);
  final iter = a[2] as int;
  final h = Hmac(sha256, pw);
  var u = h.convert([...salt, 0, 0, 0, 1]).bytes;
  final t = List<int>.from(u);
  for (var i = 1; i < iter; i++) {
    u = h.convert(u).bytes;
    for (var j = 0; j < t.length; j++) {
      t[j] ^= u[j];
    }
  }
  return base64Encode(t);
}

class OfflineLogin {
  final bool ok;
  final int status;
  final String mensaje;
  final Map<String, dynamic>? perfil;
  const OfflineLogin(this.ok, this.status, this.mensaje, [this.perfil]);
}

class OfflineAuth {
  static const _ss = FlutterSecureStorage();
  static const _key = 'off_auth';
  static const _iter = 20000;
  static const _maxFallos = 5;
  static const _bloqueo = Duration(minutes: 10);

  static Future<void> guardar(
      String ident, String codigo, Map d, String rol) async {
    final r = Random.secure();
    final salt = base64Encode(List.generate(16, (_) => r.nextInt(256)));
    final hash = await compute(_derive, [codigo, salt, _iter]);
    await _ss.write(
      key: _key,
      value: jsonEncode({
        'ident': ident.trim().toLowerCase(),
        'rol': rol,
        'id': d['id'],
        'nombre': d['nombre'] ?? '',
        'rostro': d['rostro_registrado'] != false,
        'salt': salt,
        'iter': _iter,
        'hash': hash,
      }),
    );
  }

  static Future<Map<String, dynamic>?> perfil() async {
    final s = await _ss.read(key: _key);
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<OfflineLogin> verificar(String ident, String codigo) async {
    final p = await SharedPreferences.getInstance();
    final bloqueoHasta = p.getInt('off:bloqueo') ?? 0;
    final ahora = DateTime.now().millisecondsSinceEpoch;
    if (bloqueoHasta > ahora) {
      final min = ((bloqueoHasta - ahora) / 60000).ceil();
      return OfflineLogin(false, 429, 'Demasiados intentos. Espera $min min.');
    }
    final g = await perfil();
    if (g == null) {
      return const OfflineLogin(false, 503,
          'Sin internet. Debes iniciar sesión al menos una vez con conexión en este celular.');
    }
    if (g['rostro'] != true) {
      return const OfflineLogin(false, 503,
          'Sin internet. Primero registra tu rostro con conexión.');
    }
    final hash = await compute(_derive, [codigo, g['salt'], g['iter']]);
    final igual = g['ident'] == ident.trim().toLowerCase() &&
        _constante(hash, g['hash'] as String);
    if (!igual) {
      final f = (p.getInt('off:fallos') ?? 0) + 1;
      if (f >= _maxFallos) {
        await p.setInt('off:fallos', 0);
        await p.setInt('off:bloqueo', ahora + _bloqueo.inMilliseconds);
      } else {
        await p.setInt('off:fallos', f);
      }
      return const OfflineLogin(false, 401, 'Datos incorrectos');
    }
    await p.setInt('off:fallos', 0);
    return OfflineLogin(true, 200, '', g);
  }

  static bool _constante(String a, String b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return r == 0;
  }
}

// ══════════════════════════════════════════════════════════════════════
//  COLA DE EVIDENCIAS (fotos + GPS + hora) guardadas sin internet
//  Las fotos se guardan como archivos; el índice en cola.json.
// ══════════════════════════════════════════════════════════════════════
class OfflineQueue {
  /// Se incrementa cada vez que cambia la cola (para refrescar la interfaz).
  static final ValueNotifier<int> cambios = ValueNotifier(0);

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/evidencias');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> _idx() async => File('${(await _dir()).path}/cola.json');

  static Future<List<Map<String, dynamic>>> _todos() async {
    try {
      final f = await _idx();
      if (!await f.exists()) return [];
      final l = jsonDecode(await f.readAsString()) as List;
      return l.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _escribir(List<Map<String, dynamic>> l) async {
    await (await _idx()).writeAsString(jsonEncode(l), flush: true);
    cambios.value++;
  }

  static Future<(String, int)> _yo() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString('rol') ?? '', p.getInt('userId') ?? 0);
  }

  static String hoy() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Pendientes del usuario actual.
  static Future<List<Map<String, dynamic>>> listar() async {
    final (rol, id) = await _yo();
    return (await _todos()).where((e) => e['rol'] == rol && e['uid'] == id).toList();
  }

  static Future<int> contar() async => (await listar()).length;

  /// ¿Ya hay una evidencia guardada para esa clase hoy?
  static Future<bool> existe(int horarioId, [String? fecha]) async {
    final f = fecha ?? hoy();
    return (await listar()).any((e) => e['horario_id'] == horarioId && e['fecha'] == f);
  }

  static Future<String> agregar({
    required int horarioId,
    required String materia,
    required double? lat,
    required double? lon,
    required String fotoBase64,
  }) async {
    final (rol, id) = await _yo();
    final r = Random.secure();
    final cid = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final path = '${(await _dir()).path}/$cid.jpg';
    await File(path).writeAsBytes(base64Decode(fotoBase64), flush: true);
    final todos = await _todos();
    todos.add({
      'client_id': cid,
      'rol': rol,
      'uid': id,
      'horario_id': horarioId,
      'materia': materia,
      'fecha': hoy(),
      // Hora del celular en UTC: el servidor la marca como "no verificada".
      'ts': DateTime.now().toUtc().toIso8601String(),
      'lat': lat,
      'lon': lon,
      'foto': path,
    });
    await _escribir(todos);
    return cid;
  }

  static Future<String?> fotoBase64(Map<String, dynamic> it) async {
    try {
      final Uint8List b = await File(it['foto'] as String).readAsBytes();
      return base64Encode(b);
    } catch (_) {
      return null;
    }
  }

  static Future<void> quitar(String clientId) async {
    final todos = await _todos();
    final it = todos.where((e) => e['client_id'] == clientId).toList();
    for (final e in it) {
      try {
        await File(e['foto'] as String).delete();
      } catch (_) {}
    }
    todos.removeWhere((e) => e['client_id'] == clientId);
    await _escribir(todos);
  }
}

// ══════════════════════════════════════════════════════════════════════
//  FOTO DEL SALÓN guardada sin internet
//  Si al tomar la foto del salón no hay conexión, queda en el celular y se
//  envía sola cuando vuelve el internet (o justo antes de cerrar la asistencia).
// ══════════════════════════════════════════════════════════════════════
class FotoSalonPendiente {
  static bool _ocupado = false;

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/fotos_salon');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> _idx() async => File('${(await _dir()).path}/cola.json');

  static Future<List<Map<String, dynamic>>> _todos() async {
    try {
      final f = await _idx();
      if (!await f.exists()) return [];
      final l = jsonDecode(await f.readAsString()) as List;
      return l.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _escribir(List<Map<String, dynamic>> l) async =>
      (await _idx()).writeAsString(jsonEncode(l), flush: true);

  static Future<(String, int)> _yo() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString('rol') ?? '', p.getInt('userId') ?? 0);
  }

  static Future<List<Map<String, dynamic>>> _mias() async {
    final (rol, id) = await _yo();
    return (await _todos()).where((e) => e['rol'] == rol && e['uid'] == id).toList();
  }

  /// ¿Hay una foto de salón guardada en el celular para esa clase hoy?
  static Future<bool> existe(int horarioId) async {
    final hoy = OfflineQueue.hoy();
    return (await _mias()).any((e) => e['horario_id'] == horarioId && e['fecha'] == hoy);
  }

  static Future<void> guardar(int horarioId, String fotoBase64) async {
    final (rol, id) = await _yo();
    final fecha = OfflineQueue.hoy();
    final path = '${(await _dir()).path}/${rol}_${id}_${horarioId}_$fecha.jpg';
    await File(path).writeAsBytes(base64Decode(fotoBase64), flush: true);
    final todos = await _todos();
    todos.removeWhere((e) =>
        e['rol'] == rol && e['uid'] == id && e['horario_id'] == horarioId && e['fecha'] == fecha);
    todos.add({
      'rol': rol,
      'uid': id,
      'horario_id': horarioId,
      'fecha': fecha,
      // Hora del celular en UTC: cuándo se tomó la foto.
      'ts': DateTime.now().toUtc().toIso8601String(),
      'foto': path,
    });
    await _escribir(todos);
  }

  static Future<void> _quitar(Map<String, dynamic> it) async {
    try { await File(it['foto'] as String).delete(); } catch (_) {}
    final todos = await _todos();
    todos.removeWhere((e) => e['foto'] == it['foto']);
    await _escribir(todos);
  }

  /// Envía las fotos guardadas. Devuelve cuántas se enviaron.
  static Future<int> enviarPendientes() async {
    if (_ocupado) return 0;
    _ocupado = true;
    var enviadas = 0;
    try {
      for (final it in await _mias()) {
        final f = File(it['foto'] as String);
        if (!await f.exists()) {
          await _quitar(it);
          continue;
        }
        final b64 = base64Encode(await f.readAsBytes());
        Map<String, dynamic> r;
        try {
          r = await Api.subirFotoSalon(it['horario_id'] as int, b64, ts: it['ts'] as String?);
        } catch (_) {
          break; // sin conexión: se reintenta luego
        }
        final st = r['_status'] as int;
        if (st == 200) {
          await _quitar(it);
          enviadas++;
        } else if (st == 409 || st == 400 || st == 404) {
          await _quitar(it); // ya enviada o rechazada de forma definitiva
        } else {
          break; // sesión vencida, asistencia aún sin registrar, servidor caído…
        }
      }
    } finally {
      _ocupado = false;
    }
    return enviadas;
  }
}
