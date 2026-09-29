import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kBase = 'https://nodeapkuniguajira-production.up.railway.app/api';

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
    // Si el backend aún no envía este campo, no bloqueamos al usuario.
    await p.setBool('rostro', d['rostro_registrado'] != false);
    if (d['id'] != null) await p.setInt('userId', d['id']);
  }

  static Future<void> logout() async {
    await _ss.delete(key: 'token');
    await (await SharedPreferences.getInstance()).clear();
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
    final r = await http.post(
      Uri.parse('$kBase/face/enroll'),
      headers: await _h(),
      body: jsonEncode({'foto_base64': fotoBase64, 'liveness': true}),
    );
    final d = jsonDecode(r.body) as Map<String, dynamic>;
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
    final r = await http.post(
      Uri.parse('$kBase/auth/login'),
      headers: await _h(),
      body: jsonEncode({'identificador': identificador, 'codigo': codigo}),
    );
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode == 200) await saveSession(d, d['rol']);
    return {'_status': r.statusCode, ...d};
  }

  static Future<Map<String, dynamic>> loginAdmin(
      String correo, String password) async {
    final r = await http.post(
      Uri.parse('$kBase/auth/admin/login'),
      headers: await _h(),
      body: jsonEncode({'correo': correo, 'password': password}),
    );
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode == 200) await saveSession(d, 'admin');
    return {'_status': r.statusCode, ...d};
  }

  // ── ESTUDIANTE ────────────────────────────────────────────────────
  static Future<List> misClasesEstudiante() async {
    final r = await http.get(Uri.parse('$kBase/estudiante/clases'),
        headers: await _h());
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  static Future<List> asistenciasClase(int horarioId) async {
    final r = await http.get(
        Uri.parse('$kBase/estudiante/asistencias/$horarioId'),
        headers: await _h());
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  static Future<Map<String, dynamic>> firmarAsistenciaEstudiante({
    required int horarioId,
    required double lat,
    required double lon,
    required String fotoBase64,
  }) async {
    final r = await http.post(
      Uri.parse('$kBase/estudiante/firmar'),
      headers: await _h(),
      body: jsonEncode({
        'horario_id': horarioId,
        'latitud': lat,
        'longitud': lon,
        'foto_base64': fotoBase64,
        'liveness': true,
      }),
    );
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    return {'_status': r.statusCode, ...d};
  }

  // ── PROFESOR ──────────────────────────────────────────────────────
  static Future<List> misClasesProfesor() async {
    final r = await http.get(Uri.parse('$kBase/profesor/clases-hoy'),
        headers: await _h());
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  static Future<List> horarioSemanaProfesor() async {
    final r = await http.get(Uri.parse('$kBase/profesor/horario-semana'),
        headers: await _h());
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  static Future<Map<String, dynamic>> firmarAsistenciaProfesor({
    required int horarioId,
    required double lat,
    required double lon,
    required String fotoBase64,
  }) async {
    final r = await http.post(
      Uri.parse('$kBase/profesor/registrar-asistencia'),
      headers: await _h(),
      body: jsonEncode({
        'horario_id': horarioId,
        'latitud': lat,
        'longitud': lon,
        'foto_base64': fotoBase64,
        'liveness': true,
      }),
    );
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    return {'_status': r.statusCode, ...d};
  }

  // ── ADMIN ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> dashboard() async {
    final r = await http.get(Uri.parse('$kBase/admin/dashboard'),
        headers: await _h());
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  // Lista paginada de profesores (para manejar 5000+)
  static Future<Map<String, dynamic>> profesoresPaginados({
    int page = 1, int limit = 30, String busqueda = '',
  }) async {
    final q = {'page': '$page', 'limit': '$limit',
      if (busqueda.isNotEmpty) 'q': busqueda};
    final r = await http.get(
        Uri.parse('$kBase/admin/profesores')
            .replace(queryParameters: q),
        headers: await _h());
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  static Future<Map<String, dynamic>> estadisticasProfesores({
    String busqueda = '', int page = 1,
  }) async {
    final q = {'page': '$page', 'limit': '30',
      if (busqueda.isNotEmpty) 'q': busqueda};
    final r = await http.get(
        Uri.parse('$kBase/admin/estadisticas')
            .replace(queryParameters: q),
        headers: await _h());
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  static Future<List> asistenciasAdmin({String? fecha, int? profId}) async {
    final q = {if (fecha != null) 'fecha': fecha,
      if (profId != null) 'profesor_id': '$profId'};
    final r = await http.get(
        Uri.parse('$kBase/admin/asistencias').replace(queryParameters: q),
        headers: await _h());
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }

  static Future<Map<String, dynamic>> detalleProfesor(int id) async {
    final r = await http.get(Uri.parse('$kBase/admin/profesores/$id/detalle'),
        headers: await _h());
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw r.body;
  }
}
