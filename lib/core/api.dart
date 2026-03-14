import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ⚠️ CAMBIA ESTO POR LA URL DE TU SERVIDOR
const String kBase = 'https://TU_DOMINIO.com/api';

class Api {
  // ── PREFS ─────────────────────────────────────────────────────────
  static Future<String?> _token() async =>
      (await SharedPreferences.getInstance()).getString('token');

  static Future<Map<String, String>> _h() async {
    final t = await _token();
    return {'Content-Type': 'application/json',
      if (t != null) 'Authorization': 'Bearer $t'};
  }

  static Future<void> saveSession(Map d, String rol) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('token', d['token']);
    await p.setString('nombre', d['nombre'] ?? '');
    await p.setString('rol', rol);
    if (d['id'] != null) await p.setInt('userId', d['id']);
  }

  static Future<void> logout() async =>
      (await SharedPreferences.getInstance()).clear();

  static Future<Map<String, String>> getSession() async {
    final p = await SharedPreferences.getInstance();
    return {
      'token': p.getString('token') ?? '',
      'nombre': p.getString('nombre') ?? '',
      'rol': p.getString('rol') ?? '',
    };
  }

  // ── AUTH UNIFICADO ────────────────────────────────────────────────
  // El backend detecta si es estudiante o profesor por el identificador
  // Estudiante: username sin @ (ej: jdavidmonterrosa) + código
  // Profesor: cédula + código
  static Future<Map<String, dynamic>> login(
      String identificador, String codigo) async {
    final r = await http.post(
      Uri.parse('$kBase/auth/login'),
      headers: {'Content-Type': 'application/json'},
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
      headers: {'Content-Type': 'application/json'},
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
  }) async {
    final r = await http.post(
      Uri.parse('$kBase/estudiante/firmar'),
      headers: await _h(),
      body: jsonEncode({'horario_id': horarioId, 'latitud': lat, 'longitud': lon}),
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
