import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'offline.dart';
//url del servidor
const String kBase = 'https://aplicacionuniguajira-production.up.railway.app/api';

class Api {
  // ── SESIÓN ────────────────────────────────────────────────────────
  // El token vive en almacenamiento cifrado (Keystore); el resto en prefs.
  static const _ss = FlutterSecureStorage();

  static Future<String?> getToken() => _ss.read(key: 'token');

  // ID estable por instalación (device binding: el servidor lo asocia al usuario)
  static Future<String> deviceId() async {
    var id = await _ss.read(key: 'device_id');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _ss.write(key: 'device_id', value: id);
    }
    return id;
  }

  static const _t = Duration(seconds: 12);
  static const _tFoto = Duration(seconds: 40);

  static Future<http.Response> _get(String path, [Map<String, String>? q]) async =>
      http.get(Uri.parse('$kBase$path').replace(queryParameters: q),
          headers: await _h()).timeout(_t);

  static Future<http.Response> _post(String path, Object body,
          {bool foto = false}) async =>
      http.post(Uri.parse('$kBase$path'),
          headers: await _h(), body: jsonEncode(body)).timeout(foto ? _tFoto : _t);

  static Map<String, dynamic> _dec(String body) {
    try {
      final d = jsonDecode(body);
      return d is Map<String, dynamic> ? d : {'error': 'Respuesta inesperada'};
    } catch (_) {
      return {'error': 'Error del servidor, intenta de nuevo'};
    }
  }

  static Future<Map<String, String>> _h() async {
    final t = await getToken();
    return {
      'Content-Type': 'application/json',
      'X-Device-Id': await deviceId(),
      if (t != null) 'Authorization': 'Bearer $t',
    };
  }

  static Future<void> saveSession(Map d, String rol) async {
    final p = await SharedPreferences.getInstance();
    await _ss.write(key: 'token', value: d['token']);
    await p.setString('nombre', d['nombre'] ?? '');
    await p.setString('rol', rol);
    await p.setBool('sesion_offline', false);
    // Si el backend aún no envía este campo, no bloqueamos al usuario.
    await p.setBool('rostro', d['rostro_registrado'] != false);
    if (d['id'] != null) await p.setInt('userId', d['id']);
  }

  static Future<void> logout() async {
    await _ss.delete(key: 'token');
    // Se conserva la caché ('cache:*') y los datos offline ('off:*') del celular.
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys().toList()) {
      if (!k.startsWith('cache:') && !k.startsWith('off:')) await p.remove(k);
    }
  }

  static Future<Map<String, String>> getSession() async {
    final p = await SharedPreferences.getInstance();
    return {
      'token': await getToken() ?? '',
      'nombre': p.getString('nombre') ?? '',
      'rol': p.getString('rol') ?? '',
    };
  }

  static Future<bool> rostroRegistrado() async =>
      (await SharedPreferences.getInstance()).getBool('rostro') ?? true;

  // ── ROSTRO ────────────────────────────────────────────────────────
  // POST /face/enroll  { foto_base64 }  ->  200 { success: true }
  static Future<Map<String, dynamic>> enrolarRostro(String fotoBase64) async {
    final r = await _post('/face/enroll',
        {'foto_base64': fotoBase64, 'liveness': true}, foto: true);
    final d = _dec(r.body);
    if (r.statusCode == 200) {
      await (await SharedPreferences.getInstance()).setBool('rostro', true);
    }
    return {'_status': r.statusCode, ...d};
  }

  // ── AUTH UNIFICADO ────────────────────────────────────────────────
  // El backend detecta si es estudiante o profesor por el identificador
  // Estudiante: username sin @ (ej: jdavidmonterrosa) + código
  // Profesor: cédula + código
  static Future<Map<String, dynamic>> login(
      String identificador, String codigo) async {
    http.Response r;
    try {
      r = await _post('/auth/login', {'identificador': identificador, 'codigo': codigo});
    } catch (e) {
      if (!Net.esErrorDeRed(e)) rethrow;
      return _loginOffline(identificador, codigo);
    }
    final d = _dec(r.body);
    if (r.statusCode == 200) {
      await saveSession(d, d['rol']);
      Net.offline.value = false;
      // Guarda el verificador para poder entrar después sin internet.
      await OfflineAuth.guardar(identificador, codigo, d, d['rol']);
    }
    return {'_status': r.statusCode, ...d};
  }

  static Future<Map<String, dynamic>> _loginOffline(
      String identificador, String codigo) async {
    final o = await OfflineAuth.verificar(identificador, codigo);
    if (!o.ok) return {'_status': o.status, 'error': o.mensaje};
    final g = o.perfil!;
    final p = await SharedPreferences.getInstance();
    await p.setString('nombre', g['nombre'] ?? '');
    await p.setString('rol', g['rol']);
    await p.setBool('rostro', true);
    await p.setBool('sesion_offline', true);
    if (g['id'] != null) await p.setInt('userId', g['id']);
    Net.offline.value = true;
    return {
      '_status': 200, 'rol': g['rol'], 'nombre': g['nombre'],
      'id': g['id'], 'rostro_registrado': true, 'offline': true,
    };
  }

  static Future<Map<String, dynamic>> loginAdmin(
      String correo, String password) async {
    final r = await _post('/auth/admin/login', {'correo': correo, 'password': password});
    final d = _dec(r.body);
    if (r.statusCode == 200) await saveSession(d, 'admin');
    return {'_status': r.statusCode, ...d};
  }

  // ── CLASES (con respaldo sin conexión) ───────────────────────────
  static Future<List> _clasesConRespaldo(String rol, String path) async {
    try {
      final r = await _get(path);
      if (r.statusCode != 200) throw r.body;
      Net.offline.value = false;
      unawaited(_cacheSemana(rol));
      return _anotar(jsonDecode(r.body) as List);
    } catch (e) {
      if (Net.esErrorDeRed(e)) {
        final c = await _clasesOffline();
        if (c != null) {
          Net.offline.value = true;
          return c;
        }
      }
      rethrow;
    }
  }

  static Future<void> _cacheSemana(String rol) async {
    try {
      final r = await _get(rol == 'profesor' ? '/profesor/horario-semana' : '/estudiante/horario-semana');
      if (r.statusCode == 200) await Cache.put('semana', jsonDecode(r.body));
    } catch (_) {}
  }

  /// Marca las clases que ya tienen una evidencia guardada esperando envío.
  static Future<List> _anotar(List l) async {
    final out = [];
    for (final c in l) {
      final m = Map<String, dynamic>.from(c as Map);
      final pend = await OfflineQueue.existe(m['id'] as int);
      m['pendiente_offline'] = pend;
      if (pend) m['disponible'] = false;
      out.add(m);
    }
    return out;
  }

  /// Clases de hoy armadas con el horario semanal guardado y la hora del celular.
  static Future<List?> _clasesOffline() async {
    final semana = await Cache.get('semana');
    if (semana is! List) return null;
    final hoy = DateTime.now().weekday; // 1=lunes … 7=domingo
    final l = semana
        .where((c) => c['dia_num'] == hoy)
        .map((c) => Map<String, dynamic>.from(c as Map))
        .toList()
      ..sort((a, b) => (a['hora_inicio'] as String).compareTo(b['hora_inicio'] as String));
    for (final c in l) {
      final v = VentanaLocal.calcular(c['hora_inicio'], c['hora_fin']);
      c['disponible'] = v.disponible;
      c['mensaje'] = v.mensaje;
      c['offline'] = true;
      c['ya_firmo'] = false;
    }
    return _anotar(l);
  }

  // ── ESTUDIANTE ────────────────────────────────────────────────────
  static Future<List> misClasesEstudiante() =>
      _clasesConRespaldo('estudiante', '/estudiante/clases');

  static Future<List> asistenciasClase(int horarioId) async {
    final key = 'asist_$horarioId';
    try {
      final r = await _get('/estudiante/asistencias/$horarioId');
      if (r.statusCode != 200) throw r.body;
      final d = jsonDecode(r.body) as List;
      await Cache.put(key, d);
      return d;
    } catch (e) {
      if (Net.esErrorDeRed(e)) {
        final c = await Cache.get(key);
        if (c is List) return c;
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> firmarAsistenciaEstudiante({
    required int horarioId,
    required double lat,
    required double lon,
    required String fotoBase64,
  }) async {
    final r = await _post('/estudiante/firmar', {
      'horario_id': horarioId,
      'latitud': lat,
      'longitud': lon,
      'foto_base64': fotoBase64,
      'liveness': true,
    }, foto: true);
    return {'_status': r.statusCode, ..._dec(r.body)};
  }

  // ── PROFESOR ──────────────────────────────────────────────────────
  static Future<List> misClasesProfesor() =>
      _clasesConRespaldo('profesor', '/profesor/clases-hoy');

  static Future<List> horarioSemanaProfesor() async {
    try {
      final r = await _get('/profesor/horario-semana');
      if (r.statusCode != 200) throw r.body;
      final d = jsonDecode(r.body) as List;
      await Cache.put('semana', d);
      return d;
    } catch (e) {
      if (Net.esErrorDeRed(e)) {
        final c = await Cache.get('semana');
        if (c is List) return c;
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> firmarAsistenciaProfesor({
    required int horarioId,
    required double lat,
    required double lon,
    required String fotoBase64,
  }) async {
    final r = await _post('/profesor/registrar-asistencia', {
      'horario_id': horarioId,
      'latitud': lat,
      'longitud': lon,
      'foto_base64': fotoBase64,
      'liveness': true,
    }, foto: true);
    return {'_status': r.statusCode, ..._dec(r.body)};
  }

  /// El profesor habilita (abrir=true) o cierra la firma de sus estudiantes.
  static Future<Map<String, dynamic>> sesionClase(int horarioId, bool abrir) async {
    final r = await _post('/profesor/sesion', {'horario_id': horarioId, 'abrir': abrir});
    return {'_status': r.statusCode, ..._dec(r.body)};
  }

  // ── OFFLINE: envío de evidencias ──────────────────────────────────
  /// 200 = sesión válida, 401/403 = hay que volver a iniciar sesión, -1 = sin red.
  static Future<int> probarSesion() async {
    if (await getToken() == null) return 401;
    try {
      return (await _get('/offline/mis')).statusCode;
    } catch (_) {
      return -1;
    }
  }

  static Future<List> misEvidencias() async {
    final r = await _get('/offline/mis');
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  static Future<Map<String, dynamic>> sincronizarOffline(Map<String, dynamic> body) async {
    final r = await _post('/offline/sincronizar', body, foto: true);
    return {'_status': r.statusCode, ..._dec(r.body)};
  }

  // ── ADMIN ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> dashboard() async {
    final r = await _get('/admin/dashboard');
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  // Lista paginada de profesores (para manejar 5000+)
  static Future<Map<String, dynamic>> profesoresPaginados({
    int page = 1, int limit = 30, String busqueda = '',
  }) async {
    final q = {'page': '$page', 'limit': '$limit',
      if (busqueda.isNotEmpty) 'q': busqueda};
    final r = await _get('/admin/profesores', q);
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  static Future<Map<String, dynamic>> estadisticasProfesores({
    String busqueda = '', int page = 1,
  }) async {
    final q = {'page': '$page', 'limit': '30',
      if (busqueda.isNotEmpty) 'q': busqueda};
    final r = await _get('/admin/estadisticas', q);
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  static Future<List> asistenciasAdmin({String? fecha, int? profId}) async {
    final q = {if (fecha != null) 'fecha': fecha,
      if (profId != null) 'profesor_id': '$profId'};
    final r = await _get('/admin/asistencias', q);
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  static Future<Map<String, dynamic>> detalleProfesor(int id) async {
    final r = await _get('/admin/profesores/$id/detalle');
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  // ── ADMIN: revisión de evidencias offline ─────────────────────────
  static Future<Map<String, dynamic>> offlineAdmin({String estado = 'pendiente', int page = 1}) async {
    final r = await _get('/admin/offline', {'estado': estado, 'page': '$page', 'limit': '20'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  static Future<Uint8List?> fotoOffline(int id) async {
    final r = await http.get(Uri.parse('$kBase/admin/offline/$id/foto'),
        headers: await _h()).timeout(_tFoto);
    return r.statusCode == 200 ? r.bodyBytes : null;
  }

  static Future<Map<String, dynamic>> revisarOffline(int id, bool aprobar, {String? motivo}) async {
    final r = await _post('/admin/offline/$id/${aprobar ? 'aprobar' : 'rechazar'}',
        {if (motivo != null && motivo.isNotEmpty) 'motivo': motivo});
    return {'_status': r.statusCode, ..._dec(r.body)};
  }
}
