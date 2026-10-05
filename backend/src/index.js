const crypto = require('crypto');
const { Readable } = require('stream');
const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const L = require('./lib');
const schema = require('./schema');
const { cfg, q, pool, ErrorApp } = L;

const app = express();
app.set('trust proxy', 1);
app.disable('x-powered-by');
app.use(helmet());
app.use(express.json({ limit: '8mb' }));

const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
const HORA_ISO = (c) => `to_char(${c} AT TIME ZONE 'America/Bogota','YYYY-MM-DD"T"HH24:MI:SS')`;
const TABLA = { profesor: 'profesores', estudiante: 'estudiantes' };
const DIAS = ['', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

// ── Auth / middlewares ─────────────────────────────────────────────
function auth(roles) {
  return (req, res, next) => {
    try {
      const t = (req.get('Authorization') || '').replace(/^Bearer /, '');
      const u = L.verificar(t);
      if (!roles.includes(u.rol)) throw new ErrorApp(403, 'Sin permiso', 'FORBIDDEN');
      // Un token robado no sirve en otro celular
      if (u.rol !== 'admin' && req.get('X-Device-Id') !== u.did)
        throw new ErrorApp(403, 'Sesión inválida en este dispositivo', 'DEVICE_MISMATCH');
      req.user = u;
      next();
    } catch (e) {
      next(e instanceof ErrorApp ? e : new ErrorApp(401, 'Sesión expirada', 'NO_AUTH'));
    }
  };
}
const admin = auth(['admin']);
const limLogin = rateLimit({
  windowMs: 15 * 60 * 1000, limit: 20, standardHeaders: true, legacyHeaders: false,
  keyGenerator: (req) => String(req.body?.identificador || req.body?.correo || 'x').toLowerCase().slice(0, 64),
  message: { error: 'Demasiados intentos. Espera 15 minutos.', code: 'RATE_LIMIT' },
});
const limUser = (max) => rateLimit({
  windowMs: 60 * 1000, limit: max, standardHeaders: true, legacyHeaders: false,
  keyGenerator: (req) => `${req.user.rol}:${req.user.sub}`,
  message: { error: 'Demasiadas solicitudes, espera un momento.', code: 'RATE_LIMIT' },
});
const limFirma = limUser(10);

const DUMMY = { h: null };
const dupe = (e) => {
  if (e.code !== '23505') throw e;
  throw new ErrorApp(409, /foto_hash/.test(e.constraint || '') ? 'Esa foto ya fue usada' : 'Ya registraste tu asistencia',
    /foto_hash/.test(e.constraint || '') ? 'FOTO_REPETIDA' : 'YA_REGISTRADA');
};

async function verificarRostro(rol, id, fotoB64) {
  const buf = L.decodificarFoto(fotoB64);
  const r = await q('SELECT embedding_enc FROM rostros_faciales WHERE usuario_id=$1 AND rol=$2', [id, rol]);
  if (!r.rows[0]) throw new ErrorApp(403, 'Debes registrar tu rostro primero', 'SIN_ROSTRO');
  const v = await L.faceCall('/v1/verify', buf, L.decrypt(r.rows[0].embedding_enc));
  if (!v.match) throw new ErrorApp(403, 'El rostro no coincide', 'ROSTRO_NO_COINCIDE');
  return { score: v.score, hash: crypto.createHash('sha256').update(buf).digest('hex') };
}
async function esVirtual(hid) {
  if (!hid) return false;
  return (await q("SELECT 1 FROM horarios WHERE id=$1 AND modalidad='virtual'", [hid])).rowCount > 0;
}
function datosFirma(body, virtual = false) {
  const hid = parseInt(body.horario_id, 10);
  const lat = virtual ? null : Number(body.latitud), lon = virtual ? null : Number(body.longitud);
  if (!hid || (!virtual && (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180)))
    throw new ErrorApp(400, 'Datos incompletos', 'BAD_REQUEST');
  if (body.liveness !== true) throw new ErrorApp(400, 'Falta la prueba de vida', 'SIN_LIVENESS');
  return { hid, lat, lon };
}

// ── Salud ──────────────────────────────────────────────────────────
app.get('/', (_, res) => res.json({ servicio: 'UniGuajira API', ok: true }));
app.get('/health', wrap(async (_, res) => { await q('SELECT 1'); res.json({ ok: true }); }));

// ── Actualización de la app (APK publicada en GitHub Releases) ─────
const GH_REPO = process.env.GITHUB_REPO || 'monterrosacotesjesusdavid-cyber/Aplicacion_uniguajira';
const ghHeaders = (extra = {}) => ({
  'User-Agent': 'uniguajira-backend',
  Accept: 'application/vnd.github+json',
  ...(process.env.GITHUB_TOKEN ? { Authorization: `Bearer ${process.env.GITHUB_TOKEN}` } : {}),
  ...extra,
});
let apkCache = { t: 0, data: null };
async function ultimaApk() {
  if (apkCache.data && Date.now() - apkCache.t < 120000) return apkCache.data;
  let j;
  try {
    const r = await fetch(`https://api.github.com/repos/${GH_REPO}/releases/latest`, { headers: ghHeaders() });
    if (!r.ok) throw new Error('GitHub ' + r.status);
    j = await r.json();
  } catch (e) {
    // GitHub limita las consultas sin token: si falla, se usa la última versión conocida.
    if (apkCache.data) return apkCache.data;
    throw new ErrorApp(502, 'No se pudo consultar la versión', 'GITHUB');
  }
  const asset = (j.assets || []).find((a) => String(a.name).endsWith('.apk'));
  const build = parseInt(String(j.tag_name || '').replace(/\D/g, ''), 10) || 0;
  if (!asset || !build) throw new ErrorApp(404, 'Sin APK publicada', 'NO_APK');
  apkCache = { t: Date.now(), data: { build, assetUrl: asset.url, size: asset.size } };
  return apkCache.data;
}
app.get('/api/app/version', wrap(async (_, res) => {
  const a = await ultimaApk();
  res.json({ build: a.build, size: a.size });
}));
app.get('/api/app/descargar', wrap(async (_, res) => {
  const a = await ultimaApk();
  const r = await fetch(a.assetUrl, { headers: ghHeaders({ Accept: 'application/octet-stream' }) });
  if (!r.ok || !r.body) throw new ErrorApp(502, 'No se pudo descargar la APK', 'GITHUB');
  res.set({
    'Content-Type': 'application/vnd.android.package-archive',
    'Content-Disposition': 'attachment; filename="uniguajira.apk"',
  });
  if (a.size) res.set('Content-Length', String(a.size));
  Readable.fromWeb(r.body).pipe(res);
}));

// ── AUTH ───────────────────────────────────────────────────────────
app.post('/api/auth/login', limLogin, wrap(async (req, res) => {
  const { identificador, codigo, foto_base64, liveness } = req.body || {};
  const did = req.get('X-Device-Id') || '';
  if (typeof identificador !== 'string' || typeof codigo !== 'string' || !identificador.trim() || !codigo)
    throw new ErrorApp(400, 'Completa todos los campos', 'BAD_REQUEST');
  if (did.length < 16 || did.length > 128) throw new ErrorApp(400, 'Dispositivo no identificado', 'NO_DEVICE');

  const id = identificador.trim();
  let user = null, rol = null;
  let r = await q('SELECT id,nombre,codigo_hash,device_id,activo FROM profesores WHERE cedula=$1', [id]);
  if (r.rows[0]) { user = r.rows[0]; rol = 'profesor'; }
  else {
    r = await q('SELECT id,nombre,codigo_hash,device_id,activo FROM estudiantes WHERE usuario=$1', [id.toLowerCase()]);
    if (r.rows[0]) { user = r.rows[0]; rol = 'estudiante'; }
  }
  if (!DUMMY.h) DUMMY.h = await L.hashPw('dummy');
  const ok = await L.checkPw(codigo, user ? user.codigo_hash : DUMMY.h);
  if (!user || !ok || !user.activo) throw new ErrorApp(401, 'Datos incorrectos', 'BAD_LOGIN');

  // Verificación facial al iniciar sesión: si ya tiene rostro registrado, debe coincidir.
  // (Si aún no lo tiene, entra y la app le pide registrarlo.)
  const f = await q('SELECT 1 FROM rostros_faciales WHERE usuario_id=$1 AND rol=$2', [user.id, rol]);
  if (f.rowCount > 0) {
    if (!foto_base64) throw new ErrorApp(403, 'Verifica tu rostro para entrar', 'FACE_REQUIRED');
    if (liveness !== true) throw new ErrorApp(400, 'Falta la prueba de vida', 'SIN_LIVENESS');
    await verificarRostro(rol, user.id, foto_base64);
  }

  // Sin bloqueo por celular: el último dispositivo que inicia sesión queda registrado.
  if (user.device_id !== did)
    await q(`UPDATE ${TABLA[rol]} SET device_id=$1 WHERE id=$2`, [did, user.id]);

  res.json({
    token: L.firmar({ sub: user.id, rol, did }), nombre: user.nombre, rol, id: user.id,
    rostro_registrado: f.rowCount > 0,
  });
}));

app.post('/api/auth/admin/login', limLogin, wrap(async (req, res) => {
  const { correo, password } = req.body || {};
  if (typeof correo !== 'string' || typeof password !== 'string' || !correo || !password)
    throw new ErrorApp(400, 'Completa todos los campos', 'BAD_REQUEST');
  const r = await q('SELECT id,nombre,password_hash FROM admins WHERE correo=$1', [correo.trim().toLowerCase()]);
  if (!DUMMY.h) DUMMY.h = await L.hashPw('dummy');
  const ok = await L.checkPw(password, r.rows[0] ? r.rows[0].password_hash : DUMMY.h);
  if (!r.rows[0] || !ok) throw new ErrorApp(401, 'Datos incorrectos', 'BAD_LOGIN');
  res.json({ token: L.firmar({ sub: r.rows[0].id, rol: 'admin' }), nombre: r.rows[0].nombre, rol: 'admin', id: r.rows[0].id });
}));

// ── ROSTRO ─────────────────────────────────────────────────────────
app.post('/api/face/enroll', auth(['profesor', 'estudiante']), limUser(5), wrap(async (req, res) => {
  if (req.body?.liveness !== true) throw new ErrorApp(400, 'Falta la prueba de vida', 'SIN_LIVENESS');
  const buf = L.decodificarFoto(req.body?.foto_base64);
  const ya = await q('SELECT 1 FROM rostros_faciales WHERE usuario_id=$1 AND rol=$2', [req.user.sub, req.user.rol]);
  if (ya.rowCount) throw new ErrorApp(409, 'Ya tienes un rostro registrado. Pide al administrador que lo reinicie.', 'ROSTRO_YA_REGISTRADO');
  const d = await L.faceCall('/v1/embed', buf);
  await q(`INSERT INTO rostros_faciales (usuario_id, rol, embedding_enc) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING`,
    [req.user.sub, req.user.rol, L.encrypt(d.embedding)]);
  res.json({ success: true });
}));

// ── ZONA DEL CAMPUS ────────────────────────────────────────────────
// La app decide "dentro/fuera de la universidad" con estos datos (también sin internet).
app.get('/api/zona', auth(['profesor', 'estudiante']), wrap(async (_, res) => {
  if (!Number.isFinite(cfg.campusLat) || !Number.isFinite(cfg.campusLon))
    return res.json({ configurada: false });
  res.json({ configurada: true, lat: cfg.campusLat, lon: cfg.campusLon, radio_m: cfg.campusRadioM });
}));

// ── ESTUDIANTE ─────────────────────────────────────────────────────
app.get('/api/estudiante/clases', auth(['estudiante']), wrap(async (req, res) => {
  const t = L.ahora();
  const r = await q(`
    SELECT h.id, h.materia, h.modalidad, p.nombre AS profesor_nombre, COALESCE(s.nombre,'') AS salon,
           h.hora_inicio::text AS hora_inicio, h.hora_fin::text AS hora_fin,
           (SELECT cv.link FROM clases_virtuales cv WHERE cv.horario_id=h.id AND cv.fecha=$3::date) AS link_virtual,
           EXISTS (SELECT 1 FROM asistencias_estudiante a
                   WHERE a.horario_id=h.id AND a.estudiante_id=$1 AND a.fecha=$3::date) AS ya_firmo,
           EXISTS (SELECT 1 FROM sesiones_clase sc
                   WHERE sc.horario_id=h.id AND sc.fecha=$3::date AND sc.cerrada_en IS NULL) AS sesion_abierta
    FROM inscripciones i
    JOIN horarios h ON h.id=i.horario_id
    JOIN profesores p ON p.id=h.profesor_id
    LEFT JOIN salones s ON s.id=h.salon_id
    WHERE i.estudiante_id=$1 AND h.dia_semana=$2
    ORDER BY h.hora_inicio`, [req.user.sub, t.dow, t.fecha]);
  res.json(r.rows.map((c) => {
    if (c.modalidad === 'virtual')
      return { ...c, disponible: false, mensaje: 'Clase virtual: la asistencia la registra tu profesor' };
    if (c.ya_firmo) return { ...c, disponible: false, mensaje: 'Firmado' };
    const v = L.ventanaEstudiante(L.toMin(c.hora_inicio), L.toMin(c.hora_fin), t.min);
    if (v.disponible && !c.sesion_abierta)
      return { ...c, disponible: false, esperando_profesor: true, mensaje: 'Esperando que el profesor habilite la asistencia' };
    return { ...c, disponible: v.disponible, mensaje: v.mensaje };
  }));
}));

// Horario completo de la semana: la app lo guarda para poder mostrar las clases sin internet
app.get('/api/estudiante/horario-semana', auth(['estudiante']), wrap(async (req, res) => {
  const r = await q(`
    SELECT h.id, h.dia_semana AS dia_num, h.materia, h.modalidad, p.nombre AS profesor_nombre, COALESCE(s.nombre,'') AS salon,
           h.hora_inicio::text AS hora_inicio, h.hora_fin::text AS hora_fin
    FROM inscripciones i JOIN horarios h ON h.id=i.horario_id
    JOIN profesores p ON p.id=h.profesor_id LEFT JOIN salones s ON s.id=h.salon_id
    WHERE i.estudiante_id=$1 ORDER BY h.dia_semana, h.hora_inicio`, [req.user.sub]);
  res.json(r.rows);
}));

app.get('/api/estudiante/asistencias/:id', auth(['estudiante']), wrap(async (req, res) => {
  const hid = parseInt(req.params.id, 10);
  if (!hid) throw new ErrorApp(400, 'Clase inválida', 'BAD_REQUEST');
  const t = L.ahora();
  const r = await q(`
    WITH h AS (
      SELECT h.id, h.dia_semana, h.hora_fin, h.modalidad, i.creado
      FROM horarios h JOIN inscripciones i ON i.horario_id=h.id AND i.estudiante_id=$1
      WHERE h.id=$2),
    fechas AS (
      SELECT d::date AS fecha FROM h,
        generate_series(GREATEST(h.creado, $3::date - 120)::timestamp, $3::date::timestamp, interval '1 day') d
      WHERE extract(isodow FROM d) = h.dia_semana)
    SELECT to_char(f.fecha,'YYYY-MM-DD') AS fecha,
           COALESCE(a.estado,'ausente') AS estado,
           ${HORA_ISO('a.hora_registro')} AS hora_registro
    FROM fechas f CROSS JOIN h
    LEFT JOIN asistencias_estudiante a ON a.horario_id=h.id AND a.estudiante_id=$1 AND a.fecha=f.fecha
    LEFT JOIN clases_virtuales cv ON cv.horario_id=h.id AND cv.fecha=f.fecha
    WHERE a.id IS NOT NULL
       OR CASE WHEN h.modalidad='virtual'
            THEN (cv.cerrada_en IS NOT NULL OR f.fecha < $3::date - 1
                  OR (f.fecha = $3::date - 1
                      AND $4::int >= (extract(hour FROM h.hora_fin)*60 + extract(minute FROM h.hora_fin))))
            ELSE (f.fecha < $3::date
                  OR $4::int >= (extract(hour FROM h.hora_fin)*60 + extract(minute FROM h.hora_fin)))
          END
    ORDER BY f.fecha DESC`, [req.user.sub, hid, t.fecha, t.min]);
  res.json(r.rows);
}));

app.post('/api/estudiante/firmar', auth(['estudiante']), limFirma, wrap(async (req, res) => {
  const { hid, lat, lon } = datosFirma(req.body || {});
  const t = L.ahora();
  const e = await q('SELECT activo FROM estudiantes WHERE id=$1', [req.user.sub]);
  if (!e.rows[0]?.activo) throw new ErrorApp(403, 'Cuenta desactivada', 'INACTIVO');
  const r = await q(`
    SELECT h.hora_inicio::text AS ini, h.hora_fin::text AS fin, h.modalidad, s.lat, s.lon, s.radio_m
    FROM inscripciones i JOIN horarios h ON h.id=i.horario_id
    LEFT JOIN salones s ON s.id=h.salon_id
    WHERE i.estudiante_id=$1 AND h.id=$2 AND h.dia_semana=$3`, [req.user.sub, hid, t.dow]);
  const h = r.rows[0];
  if (!h) throw new ErrorApp(404, 'Esa clase no es hoy o no estás inscrito', 'NO_CLASE');
  if (h.modalidad === 'virtual')
    throw new ErrorApp(403, 'Esta clase es virtual: tu profesor registra la asistencia', 'CLASE_VIRTUAL');
  const ya = await q('SELECT 1 FROM asistencias_estudiante WHERE horario_id=$1 AND estudiante_id=$2 AND fecha=$3::date',
    [hid, req.user.sub, t.fecha]);
  if (ya.rowCount) throw new ErrorApp(409, 'Ya firmaste esta clase', 'YA_REGISTRADA');
  const v = L.ventanaEstudiante(L.toMin(h.ini), L.toMin(h.fin), t.min);
  if (!v.disponible) throw new ErrorApp(403, v.mensaje, 'FUERA_DE_HORARIO');
  const ses = await q('SELECT 1 FROM sesiones_clase WHERE horario_id=$1 AND fecha=$2::date AND cerrada_en IS NULL', [hid, t.fecha]);
  if (!ses.rowCount) throw new ErrorApp(403, 'El profesor aún no ha habilitado la asistencia', 'SESION_CERRADA');
  const z = L.chequearZona(lat, lon, h);
  if (!z.ok) throw new ErrorApp(403, `Estás fuera del salón (a ${z.dist} m)`, 'FUERA_DE_ZONA');
  // Estar en el campus no basta: debe estar cerca de donde firmó el profesor hoy (su salón).
  const pr = (await q('SELECT lat, lon FROM asistencias_profesor WHERE horario_id=$1 AND fecha=$2::date', [hid, t.fecha])).rows[0];
  if (pr && pr.lat != null && pr.lon != null) {
    const dp = Math.round(L.distanciaM(lat, lon, pr.lat, pr.lon));
    if (dp > cfg.companeroRadioM)
      throw new ErrorApp(403, `Estás lejos del salón de tu profesor (a ${dp} m). Acércate para firmar`, 'LEJOS_DEL_PROFESOR');
  }
  const f = await verificarRostro('estudiante', req.user.sub, req.body.foto_base64);
  try {
    await q(`INSERT INTO asistencias_estudiante
      (horario_id, estudiante_id, fecha, estado, lat, lon, distancia_m, face_score, foto_hash)
      VALUES ($1,$2,$3::date,$4,$5,$6,$7,$8,$9)`,
      [hid, req.user.sub, t.fecha, v.estado, lat, lon, z.dist, f.score, f.hash]);
  } catch (err) { dupe(err); }
  res.json({ success: true, estado: v.estado });
}));

// ── PROFESOR ───────────────────────────────────────────────────────
app.get('/api/profesor/clases-hoy', auth(['profesor']), wrap(async (req, res) => {
  const t = L.ahora();
  const r = await q(`
    SELECT h.id, h.materia, h.modalidad, COALESCE(s.nombre,'') AS salon, NULLIF(s.bloque,'') AS bloque,
           h.hora_inicio::text AS hora_inicio, h.hora_fin::text AS hora_fin,
           (SELECT cv.link FROM clases_virtuales cv WHERE cv.horario_id=h.id AND cv.fecha=$3::date) AS link_virtual,
           a.estado AS asistencia_estado, ${HORA_ISO('a.hora_registro')} AS hora_registro,
           EXISTS (SELECT 1 FROM sesiones_clase sc WHERE sc.horario_id=h.id AND sc.fecha=$3::date
                   AND sc.cerrada_en IS NULL) AS sesion_abierta,
           (SELECT count(*)::int FROM asistencias_estudiante ae WHERE ae.horario_id=h.id AND ae.fecha=$3::date) AS estudiantes_firmaron,
           (SELECT count(*)::int FROM inscripciones i WHERE i.horario_id=h.id) AS estudiantes_total
    FROM horarios h
    LEFT JOIN salones s ON s.id=h.salon_id
    LEFT JOIN asistencias_profesor a ON a.horario_id=h.id AND a.fecha=$3::date
    WHERE h.profesor_id=$1 AND h.dia_semana=$2
    ORDER BY h.hora_inicio`, [req.user.sub, t.dow, t.fecha]);
  res.json(r.rows.map((c) => {
    if (c.asistencia_estado) return { ...c, disponible: false, mensaje: '' };
    const v = L.ventanaProfesor(L.toMin(c.hora_inicio), t.min, L.toMin(c.hora_fin));
    return { ...c, disponible: v.disponible, mensaje: v.mensaje };
  }));
}));

app.get('/api/profesor/horario-semana', auth(['profesor']), wrap(async (req, res) => {
  const r = await q(`
    SELECT h.id, h.dia_semana, h.materia, h.modalidad, COALESCE(s.nombre,'') AS salon, NULLIF(s.bloque,'') AS bloque,
           h.hora_inicio::text AS hora_inicio, h.hora_fin::text AS hora_fin
    FROM horarios h LEFT JOIN salones s ON s.id=h.salon_id
    WHERE h.profesor_id=$1 ORDER BY h.dia_semana, h.hora_inicio`, [req.user.sub]);
  res.json(r.rows.map((c) => ({ ...c, dia_num: c.dia_semana, dia_semana: DIAS[c.dia_semana] })));
}));

app.post('/api/profesor/registrar-asistencia', auth(['profesor']), limFirma, wrap(async (req, res) => {
  const virtual = await esVirtual(parseInt(req.body?.horario_id, 10));
  const { hid, lat, lon } = datosFirma(req.body || {}, virtual);
  const t = L.ahora();
  const p = await q('SELECT activo FROM profesores WHERE id=$1', [req.user.sub]);
  if (!p.rows[0]?.activo) throw new ErrorApp(403, 'Cuenta desactivada', 'INACTIVO');
  const r = await q(`
    SELECT h.hora_inicio::text AS ini, h.hora_fin::text AS fin, s.lat, s.lon, s.radio_m
    FROM horarios h LEFT JOIN salones s ON s.id=h.salon_id
    WHERE h.id=$1 AND h.profesor_id=$2 AND h.dia_semana=$3`, [hid, req.user.sub, t.dow]);
  const h = r.rows[0];
  if (!h) throw new ErrorApp(404, 'Esa clase no es hoy o no te pertenece', 'NO_CLASE');
  const ya = await q('SELECT 1 FROM asistencias_profesor WHERE horario_id=$1 AND fecha=$2::date', [hid, t.fecha]);
  if (ya.rowCount) throw new ErrorApp(409, 'Ya registraste esta clase', 'YA_REGISTRADA');
  const v = L.ventanaProfesor(L.toMin(h.ini), t.min, L.toMin(h.fin));
  if (!v.disponible) throw new ErrorApp(403, v.mensaje, 'FUERA_DE_HORARIO');
  // Clase virtual: no hay salón, así que no se valida ubicación ni se pide foto del salón.
  const z = virtual ? { ok: true, dist: null } : L.chequearZona(lat, lon, h);
  if (!z.ok) throw new ErrorApp(403, `Estás fuera del salón (a ${z.dist} m)`, 'FUERA_DE_ZONA');
  // La foto del salón ya no se pide aquí: se toma después de habilitar a los estudiantes
  // (POST /api/profesor/foto-salon). Si llega una foto, se guarda igual.
  const fotoSalon = (!virtual && req.body.foto_salon_base64)
    ? L.decodificarFoto(req.body.foto_salon_base64) : null;
  const f = await verificarRostro('profesor', req.user.sub, req.body.foto_base64);
  try {
    await q(`INSERT INTO asistencias_profesor
      (horario_id, profesor_id, fecha, estado, minutos_tarde, lat, lon, distancia_m, face_score, foto_hash, foto_salon)
      VALUES ($1,$2,$3::date,$4,$5,$6,$7,$8,$9,$10,$11)`,
      [hid, req.user.sub, t.fecha, v.estado, v.tarde, lat, lon, z.dist, f.score, f.hash, fotoSalon]);
  } catch (err) { dupe(err); }
  res.json({ success: true, estado: v.estado, minutos_tarde: v.tarde });
}));


// El profesor habilita / cierra la firma de sus estudiantes (solo si ya registró su propia asistencia)
app.post('/api/profesor/sesion', auth(['profesor']), limUser(20), wrap(async (req, res) => {
  const hid = parseInt(req.body?.horario_id, 10);
  const abrir = req.body?.abrir === true;
  if (!hid) throw new ErrorApp(400, 'Clase inválida', 'BAD_REQUEST');
  const t = L.ahora();
  const r = await q(`SELECT h.hora_fin::text AS fin, h.modalidad FROM horarios h
                     WHERE h.id=$1 AND h.profesor_id=$2 AND h.dia_semana=$3`, [hid, req.user.sub, t.dow]);
  if (!r.rows[0]) throw new ErrorApp(404, 'Esa clase no es hoy o no te pertenece', 'NO_CLASE');
  if (r.rows[0].modalidad === 'virtual')
    throw new ErrorApp(400, 'Clase virtual: usa la lista del profesor', 'CLASE_VIRTUAL');
  if (abrir) {
    const reg = await q('SELECT (foto_salon IS NOT NULL) AS tiene FROM asistencias_profesor WHERE horario_id=$1 AND fecha=$2::date', [hid, t.fecha]);
    if (!reg.rowCount) throw new ErrorApp(403, 'Primero registra tu asistencia', 'PROFESOR_NO_REGISTRADO');
    if (t.min > L.toMin(r.rows[0].fin)) throw new ErrorApp(403, 'La clase ya terminó', 'FUERA_DE_HORARIO');
    // Sin la foto del salón (cámara trasera) no se habilita a los estudiantes.
    if (req.body?.foto_salon_base64) {
      const foto = L.decodificarFoto(req.body.foto_salon_base64);
      await q(`UPDATE asistencias_profesor SET foto_salon=$1
               WHERE horario_id=$2 AND fecha=$3::date AND foto_salon IS NULL`, [foto, hid, t.fecha]);
    } else if (!reg.rows[0].tiene) {
      throw new ErrorApp(400, 'Toma la foto del salón para habilitar a los estudiantes', 'FOTO_SALON_REQUERIDA');
    }
    await q(`INSERT INTO sesiones_clase (horario_id, fecha) VALUES ($1,$2::date)
             ON CONFLICT (horario_id, fecha) DO UPDATE SET cerrada_en=NULL`, [hid, t.fecha]);
  } else {
    await q('UPDATE sesiones_clase SET cerrada_en=now() WHERE horario_id=$1 AND fecha=$2::date', [hid, t.fecha]);
  }
  res.json({ success: true, sesion_abierta: abrir });
}));

// Planilla de una clase: todos los inscritos con sus asistencias y su porcentaje
app.get('/api/profesor/clase/:id/asistencias', auth(['profesor']), wrap(async (req, res) => {
  const hid = parseInt(req.params.id, 10);
  if (!hid) throw new ErrorApp(400, 'Clase inválida', 'BAD_REQUEST');
  const t = L.ahora();
  const c = await q(`
    SELECT h.id, h.materia, h.modalidad, h.dia_semana, h.hora_inicio::text AS hora_inicio, h.hora_fin::text AS hora_fin,
           COALESCE(s.nombre,'') AS salon, p.nombre AS profesor
    FROM horarios h JOIN profesores p ON p.id=h.profesor_id LEFT JOIN salones s ON s.id=h.salon_id
    WHERE h.id=$1 AND h.profesor_id=$2`, [hid, req.user.sub]);
  if (!c.rows[0]) throw new ErrorApp(404, 'Clase no encontrada', 'NO_CLASE');
  const r = await q(`
    WITH h AS (
      SELECT id, dia_semana, modalidad, (extract(hour FROM hora_fin)*60 + extract(minute FROM hora_fin))::int AS fin_min
      FROM horarios WHERE id=$1),
    est AS (
      SELECT e.id, e.nombre, e.usuario, i.creado
      FROM inscripciones i JOIN estudiantes e ON e.id=i.estudiante_id
      WHERE i.horario_id=$1),
    fechas AS (
      SELECT est.id AS est_id, d::date AS fecha
      FROM est, h,
        generate_series(GREATEST(est.creado, $2::date - 120)::timestamp, $2::date::timestamp, interval '1 day') d
      WHERE extract(isodow FROM d) = h.dia_semana)
    SELECT est.id, est.nombre, est.usuario,
           to_char(f.fecha,'YYYY-MM-DD') AS fecha,
           COALESCE(a.estado,'ausente') AS estado,
           ${HORA_ISO('a.hora_registro')} AS hora_registro
    FROM est
    LEFT JOIN fechas f ON f.est_id=est.id
    CROSS JOIN h
    LEFT JOIN asistencias_estudiante a ON a.horario_id=$1 AND a.estudiante_id=est.id AND a.fecha=f.fecha
    LEFT JOIN clases_virtuales cv ON cv.horario_id=$1 AND cv.fecha=f.fecha
    WHERE f.fecha IS NULL OR a.id IS NOT NULL
       OR CASE WHEN h.modalidad='virtual'
            THEN (cv.cerrada_en IS NOT NULL OR f.fecha < $2::date - 1
                  OR (f.fecha = $2::date - 1 AND $3::int >= h.fin_min))
            ELSE (f.fecha < $2::date OR $3::int >= h.fin_min)
          END
    ORDER BY est.nombre, f.fecha DESC`, [hid, t.fecha, t.min]);
  const mapa = new Map();
  for (const row of r.rows) {
    let e = mapa.get(row.id);
    if (!e) {
      e = { id: row.id, nombre: row.nombre, usuario: row.usuario,
            presentes: 0, tardanzas: 0, ausentes: 0, total: 0, registros: [] };
      mapa.set(row.id, e);
    }
    if (!row.fecha) continue;
    e.total++;
    if (row.estado === 'presente') e.presentes++;
    else if (row.estado === 'tardanza') e.tardanzas++;
    else e.ausentes++;
    e.registros.push({ fecha: row.fecha, estado: row.estado, hora_registro: row.hora_registro });
  }
  const estudiantes = [...mapa.values()].map((e) => ({
    ...e, porcentaje: e.total ? Math.round(((e.presentes + e.tardanzas) / e.total) * 100) : 0,
  }));
  const k = c.rows[0];
  res.json({
    clase: { id: k.id, materia: k.materia, modalidad: k.modalidad, salon: k.salon, profesor: k.profesor,
             dia: DIAS[k.dia_semana], hora_inicio: k.hora_inicio, hora_fin: k.hora_fin },
    estudiantes,
  });
}));

// ── CLASES VIRTUALES (Meet) ────────────────────────────────────────
// El profesor firma con rostro, pasa lista y marca a cada estudiante. Puede corregir hasta 24 h
// después de terminar la clase; luego solo el admin. Cada cambio queda en virtual_historial.
const FECHA_OK = /^\d{4}-\d{2}-\d{2}$/;
const URL_OK = /^https?:\/\/[^\s\/]+\.\S{2,490}$/i;
const EDITABLE_SQL = `((($2::date + h.hora_fin) AT TIME ZONE 'America/Bogota') + interval '24 hours') > now()`;

// Fecha de la clase: hoy si hoy toca esa clase; si no, la última vez que tocó.
async function fechaVirtualProfesor(hid, pid) {
  const r = await q(`SELECT to_char($1::date - ((extract(isodow FROM $1::date)::int - h.dia_semana + 7) % 7), 'YYYY-MM-DD') AS fecha
                     FROM horarios h WHERE h.id=$2 AND h.profesor_id=$3`, [L.ahora().fecha, hid, pid]);
  if (!r.rows[0]) throw new ErrorApp(404, 'Clase no encontrada', 'NO_CLASE');
  return r.rows[0].fecha;
}

async function claseVirtual(hid, fecha) {
  const r = await q(`SELECT h.modalidad, ${EDITABLE_SQL} AS editable,
      EXISTS (SELECT 1 FROM asistencias_profesor ap WHERE ap.horario_id=h.id AND ap.fecha=$2::date) AS profesor_firmo
    FROM horarios h WHERE h.id=$1`, [hid, fecha]);
  const k = r.rows[0];
  if (!k) throw new ErrorApp(404, 'Clase no encontrada', 'NO_CLASE');
  if (k.modalidad !== 'virtual') throw new ErrorApp(400, 'Esta clase no es virtual', 'NO_VIRTUAL');
  return k;
}

async function cargarListaVirtual(hid, fecha, profId = null) {
  const c = await q(`
    SELECT h.id, h.materia, h.modalidad, h.hora_inicio::text AS hora_inicio, h.hora_fin::text AS hora_fin,
           p.nombre AS profesor, cv.link, (cv.cerrada_en IS NOT NULL) AS cerrada, ${EDITABLE_SQL} AS editable,
           EXISTS (SELECT 1 FROM asistencias_profesor ap WHERE ap.horario_id=h.id AND ap.fecha=$2::date) AS profesor_firmo
    FROM horarios h JOIN profesores p ON p.id=h.profesor_id
    LEFT JOIN clases_virtuales cv ON cv.horario_id=h.id AND cv.fecha=$2::date
    WHERE h.id=$1 AND ($3::int IS NULL OR h.profesor_id=$3::int)`, [hid, fecha, profId]);
  const k = c.rows[0];
  if (!k) throw new ErrorApp(404, 'Clase no encontrada', 'NO_CLASE');
  if (k.modalidad !== 'virtual') throw new ErrorApp(400, 'Esta clase no es virtual', 'NO_VIRTUAL');
  const e = await q(`
    SELECT e.id, e.nombre, e.usuario, (a.id IS NOT NULL) AS presente
    FROM inscripciones i JOIN estudiantes e ON e.id=i.estudiante_id
    LEFT JOIN asistencias_estudiante a ON a.horario_id=i.horario_id AND a.estudiante_id=e.id AND a.fecha=$2::date
    WHERE i.horario_id=$1 ORDER BY e.nombre`, [hid, fecha]);
  return {
    fecha, editable: k.editable,
    clase: { id: k.id, materia: k.materia, profesor: k.profesor, hora_inicio: k.hora_inicio, hora_fin: k.hora_fin,
             link: k.link || '', cerrada: k.cerrada, profesor_firmo: k.profesor_firmo },
    estudiantes: e.rows,
  };
}

function idsBody(body) {
  const ids = (Array.isArray(body?.estudiante_ids) ? body.estudiante_ids : [])
    .map(Number).filter((n) => Number.isInteger(n) && n > 0).slice(0, 500);
  if (!ids.length || typeof body?.presente !== 'boolean') throw new ErrorApp(400, 'Datos incompletos', 'BAD_REQUEST');
  return ids;
}

async function marcarVirtual({ hid, fecha, ids, presente, porRol, porId }) {
  const c = await pool.connect();
  let cambios = 0;
  try {
    await c.query('BEGIN');
    const ins = await c.query(
      'SELECT estudiante_id FROM inscripciones WHERE horario_id=$1 AND estudiante_id = ANY($2::int[])', [hid, ids]);
    for (const { estudiante_id: eid } of ins.rows) {
      const r = presente
        ? await c.query(`INSERT INTO asistencias_estudiante (horario_id, estudiante_id, fecha, estado, origen, marcado_por)
            VALUES ($1,$2,$3::date,'presente',$4,$5) ON CONFLICT (horario_id, estudiante_id, fecha) DO NOTHING`,
            [hid, eid, fecha, porRol, porId])
        : await c.query('DELETE FROM asistencias_estudiante WHERE horario_id=$1 AND estudiante_id=$2 AND fecha=$3::date',
            [hid, eid, fecha]);
      if (r.rowCount) {
        cambios++;
        await c.query(`INSERT INTO virtual_historial (horario_id, estudiante_id, fecha, accion, por_rol, por_id)
          VALUES ($1,$2,$3::date,$4,$5,$6)`, [hid, eid, fecha, presente ? 'presente' : 'ausente', porRol, porId]);
      }
    }
    await c.query('COMMIT');
  } catch (e) { await c.query('ROLLBACK').catch(() => {}); throw e; }
  finally { c.release(); }
  return cambios;
}

// Reglas para que el profesor pueda editar: ya firmó su asistencia y no pasaron 24 h.
function exigirEdicionProfesor(k) {
  if (!k.profesor_firmo) throw new ErrorApp(403, 'Primero registra tu asistencia', 'PROFESOR_NO_REGISTRADO');
  if (!k.editable) throw new ErrorApp(403, 'Pasaron más de 24 horas: solo el administrador puede cambiar esta lista', 'LISTA_BLOQUEADA');
}

app.get('/api/profesor/virtual/:id/lista', auth(['profesor']), wrap(async (req, res) => {
  const hid = parseInt(req.params.id, 10);
  if (!hid) throw new ErrorApp(400, 'Clase inválida', 'BAD_REQUEST');
  const fecha = await fechaVirtualProfesor(hid, req.user.sub);
  res.json(await cargarListaVirtual(hid, fecha, req.user.sub));
}));

app.post('/api/profesor/virtual/:id/marcar', auth(['profesor']), limUser(60), wrap(async (req, res) => {
  const hid = parseInt(req.params.id, 10);
  if (!hid) throw new ErrorApp(400, 'Clase inválida', 'BAD_REQUEST');
  const ids = idsBody(req.body);
  const fecha = await fechaVirtualProfesor(hid, req.user.sub);
  exigirEdicionProfesor(await claseVirtual(hid, fecha));
  const cambios = await marcarVirtual({ hid, fecha, ids, presente: req.body.presente, porRol: 'profesor', porId: req.user.sub });
  res.json({ success: true, cambios });
}));

// Guarda el link (Meet o grabación). Con cerrar=true finaliza la lista, y solo si el link ya está guardado.
app.post('/api/profesor/virtual/:id/link', auth(['profesor']), limUser(20), wrap(async (req, res) => {
  const hid = parseInt(req.params.id, 10);
  if (!hid) throw new ErrorApp(400, 'Clase inválida', 'BAD_REQUEST');
  const fecha = await fechaVirtualProfesor(hid, req.user.sub);
  exigirEdicionProfesor(await claseVirtual(hid, fecha));
  const cerrar = req.body?.cerrar === true;
  // Finalizar la lista: el link debe haberse guardado antes (paso aparte).
  if (cerrar) {
    const prev = await q('SELECT link FROM clases_virtuales WHERE horario_id=$1 AND fecha=$2::date', [hid, fecha]);
    if (!prev.rows[0]?.link)
      throw new ErrorApp(400, 'Primero guarda el link del Meet o de la grabación para finalizar la lista', 'LINK_REQUERIDO');
    await q('UPDATE clases_virtuales SET cerrada_en=now() WHERE horario_id=$1 AND fecha=$2::date', [hid, fecha]);
    return res.json({ success: true, cerrada: true });
  }
  let link = String(req.body?.link || '').trim();
  if (!link) throw new ErrorApp(400, 'Escribe el link del Meet o de la grabación', 'LINK_REQUERIDO');
  // Acepta el link con o sin https:// (ej. meet.google.com/abc-defg-hij)
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(link)) link = 'https://' + link;
  if (!URL_OK.test(link)) throw new ErrorApp(400, 'El link no es válido. Ejemplo: meet.google.com/abc-defg-hij', 'LINK_INVALIDO');
  await q(`INSERT INTO clases_virtuales (horario_id, fecha, link) VALUES ($1,$2::date,$3::text)
    ON CONFLICT (horario_id, fecha) DO UPDATE SET link=EXCLUDED.link`, [hid, fecha, link]);
  res.json({ success: true, cerrada: false });
}));

// Admin: ve la lista y su historial de cambios, y puede corregirla sin límite de tiempo.
app.get('/api/admin/virtual/:id/lista', admin, wrap(async (req, res) => {
  const hid = parseInt(req.params.id, 10);
  if (!hid) throw new ErrorApp(400, 'Clase inválida', 'BAD_REQUEST');
  const fecha = FECHA_OK.test(req.query.fecha || '') ? req.query.fecha : L.ahora().fecha;
  const d = await cargarListaVirtual(hid, fecha);
  const h = await q(`
    SELECT e.nombre AS estudiante, vh.accion, vh.por_rol,
           CASE WHEN vh.por_rol='profesor' THEN (SELECT nombre FROM profesores WHERE id=vh.por_id)
                ELSE (SELECT nombre FROM admins WHERE id=vh.por_id) END AS por_nombre,
           ${HORA_ISO('vh.hecho_en')} AS hecho_en
    FROM virtual_historial vh JOIN estudiantes e ON e.id=vh.estudiante_id
    WHERE vh.horario_id=$1 AND vh.fecha=$2::date ORDER BY vh.hecho_en DESC LIMIT 300`, [hid, fecha]);
  res.json({ ...d, historial: h.rows });
}));

app.post('/api/admin/virtual/:id/marcar', admin, wrap(async (req, res) => {
  const hid = parseInt(req.params.id, 10);
  if (!hid || !FECHA_OK.test(req.body?.fecha || '')) throw new ErrorApp(400, 'Datos incompletos', 'BAD_REQUEST');
  const ids = idsBody(req.body);
  await claseVirtual(hid, req.body.fecha);
  const cambios = await marcarVirtual({ hid, fecha: req.body.fecha, ids, presente: req.body.presente, porRol: 'admin', porId: req.user.sub });
  res.json({ success: true, cambios });
}));

// ── ASISTENCIA OFFLINE ─────────────────────────────────────────────
// La app guarda foto+GPS+hora sin internet. Al volver la conexión pide una selfie
// con prueba de vida (identidad) y envía todo aquí; un admin aprueba o rechaza.
const TABLA_ASIST = { profesor: ['asistencias_profesor', 'profesor_id'], estudiante: ['asistencias_estudiante', 'estudiante_id'] };

async function puntuarRostro(rol, id, buf) {          // no lanza si no coincide: solo informa el puntaje
  try {
    const r = await q('SELECT embedding_enc FROM rostros_faciales WHERE usuario_id=$1 AND rol=$2', [id, rol]);
    if (!r.rows[0]) return null;
    const v = await L.faceCall('/v1/verify', buf, L.decrypt(r.rows[0].embedding_enc));
    return v.score;
  } catch { return null; }
}

app.post('/api/offline/sincronizar', auth(['profesor', 'estudiante']), limUser(20), wrap(async (req, res) => {
  const b = req.body || {}, { rol, sub } = req.user;
  const cid = String(b.client_id || '');
  if (!/^[0-9a-f]{16,64}$/i.test(cid)) throw new ErrorApp(400, 'Registro inválido', 'BAD_REQUEST');
  const hid = parseInt(b.horario_id, 10);
  const lat = b.latitud == null ? null : Number(b.latitud), lon = b.longitud == null ? null : Number(b.longitud);
  if (!hid || (lat != null && (!Number.isFinite(lat) || Math.abs(lat) > 90)) || (lon != null && (!Number.isFinite(lon) || Math.abs(lon) > 180)))
    throw new ErrorApp(400, 'Datos incompletos', 'BAD_REQUEST');
  if (await esVirtual(hid)) throw new ErrorApp(403, 'Las clases virtuales no se registran sin conexión', 'CLASE_VIRTUAL');
  const hd = new Date(b.hora_dispositivo);
  if (isNaN(hd)) throw new ErrorApp(400, 'Hora inválida', 'BAD_REQUEST');
  if (hd.getTime() > Date.now() + 5 * 60000) throw new ErrorApp(400, 'La hora del celular está en el futuro', 'HORA_INVALIDA');
  if (hd.getTime() < Date.now() - 7 * 86400000) throw new ErrorApp(400, 'La evidencia tiene más de 7 días', 'EVIDENCIA_VIEJA');
  if (b.liveness !== true) throw new ErrorApp(400, 'Falta la prueba de vida', 'SIN_LIVENESS');

  // Idempotencia: si el celular reintenta un envío ya recibido, no se duplica.
  const prev = await q('SELECT rol, usuario_id, estado FROM asistencias_offline WHERE client_id=$1', [cid]);
  if (prev.rows[0]) {
    if (prev.rows[0].rol !== rol || prev.rows[0].usuario_id !== sub) throw new ErrorApp(409, 'Registro inválido', 'BAD_REQUEST');
    return res.json({ success: true, duplicado: true, estado: prev.rows[0].estado });
  }
  const act = await q(`SELECT activo FROM ${TABLA[rol]} WHERE id=$1`, [sub]);
  if (!act.rows[0]?.activo) throw new ErrorApp(403, 'Cuenta desactivada', 'INACTIVO');

  const t = L.ahora(hd);
  const r = rol === 'profesor'
    ? await q(`SELECT h.dia_semana, s.lat, s.lon, s.radio_m FROM horarios h LEFT JOIN salones s ON s.id=h.salon_id
               WHERE h.id=$1 AND h.profesor_id=$2`, [hid, sub])
    : await q(`SELECT h.dia_semana, s.lat, s.lon, s.radio_m FROM inscripciones i JOIN horarios h ON h.id=i.horario_id
               LEFT JOIN salones s ON s.id=h.salon_id WHERE i.estudiante_id=$1 AND h.id=$2`, [sub, hid]);
  const h = r.rows[0];
  if (!h) throw new ErrorApp(404, 'Esa clase no te corresponde', 'NO_CLASE');
  if (h.dia_semana !== t.dow) throw new ErrorApp(400, 'La fecha no corresponde al día de esa clase', 'FECHA_INVALIDA');
  const [tabla, col] = TABLA_ASIST[rol];
  const ya = await q(`SELECT 1 FROM ${tabla} WHERE horario_id=$1 AND ${col}=$2 AND fecha=$3::date`, [hid, sub, t.fecha]);
  if (ya.rowCount) throw new ErrorApp(409, 'Ya tenías esta asistencia registrada', 'YA_REGISTRADA');

  // 1) Selfie de envío: confirma que quien envía es el dueño de la cuenta (obligatoria y bloqueante)
  await verificarRostro(rol, sub, b.foto_verificacion_base64);
  // 2) Foto de evidencia: solo se puntúa, la decisión es del admin
  const evid = L.decodificarFoto(b.foto_evidencia_base64);
  const scoreEv = await puntuarRostro(rol, sub, evid);
  const scoreEnvio = (await puntuarRostro(rol, sub, L.decodificarFoto(b.foto_verificacion_base64)));
  const z = lat != null && lon != null ? L.chequearZona(lat, lon, h) : { ok: false, dist: null };
  if (z.ok && rol === 'estudiante') {
    const pr = (await q('SELECT lat, lon FROM asistencias_profesor WHERE horario_id=$1 AND fecha=$2::date', [hid, t.fecha])).rows[0];
    if (pr && pr.lat != null && pr.lon != null && L.distanciaM(lat, lon, pr.lat, pr.lon) > cfg.companeroRadioM) z.ok = false;
  }

  try {
    await q(`INSERT INTO asistencias_offline
      (client_id, rol, usuario_id, horario_id, fecha, hora_dispositivo, lat, lon, distancia_m, fuera_zona,
       foto_evidencia, score_evidencia, score_envio)
      VALUES ($1,$2,$3,$4,$5::date,$6,$7,$8,$9,$10,$11,$12,$13)`,
      [cid, rol, sub, hid, t.fecha, hd.toISOString(), lat, lon, z.dist, !z.ok, evid, scoreEv, scoreEnvio]);
  } catch (e) {
    if (e.code !== '23505') throw e;
    if (/client_id/.test(e.constraint || '')) return res.json({ success: true, duplicado: true, estado: 'pendiente' });
    throw new ErrorApp(409, 'Ya enviaste una evidencia para esta clase', 'YA_REGISTRADA');
  }
  res.json({ success: true, estado: 'pendiente' });
}));

app.get('/api/offline/mis', auth(['profesor', 'estudiante']), wrap(async (req, res) => {
  const r = await q(`
    SELECT o.client_id, o.estado, o.motivo, h.materia, to_char(o.fecha,'YYYY-MM-DD') AS fecha
    FROM asistencias_offline o JOIN horarios h ON h.id=o.horario_id
    WHERE o.rol=$1 AND o.usuario_id=$2 ORDER BY o.hora_envio DESC LIMIT 50`, [req.user.rol, req.user.sub]);
  res.json(r.rows);
}));

// ── ADMIN ──────────────────────────────────────────────────────────
// Distribución de puntajes faciales de las firmas aceptadas: sirve para calibrar MATCH_THRESHOLD.
app.get('/api/admin/face-scores', admin, wrap(async (_, res) => {
  const una = (tabla, rol) => `SELECT '${rol}' AS rol, count(*)::int AS n, round(min(face_score)::numeric,3) AS minimo,
      round((percentile_cont(0.05) WITHIN GROUP (ORDER BY face_score))::numeric,3) AS p05,
      round((percentile_cont(0.5) WITHIN GROUP (ORDER BY face_score))::numeric,3) AS mediana,
      round(avg(face_score)::numeric,3) AS promedio
    FROM ${tabla} WHERE face_score IS NOT NULL`;
  const r = await q(`${una('asistencias_profesor', 'profesor')} UNION ALL ${una('asistencias_estudiante', 'estudiante')}`);
  res.json(r.rows);
}));

app.get('/api/admin/dashboard', admin, wrap(async (req, res) => {
  const t = L.ahora();
  const r = await q(`
    SELECT
      (SELECT count(*)::int FROM profesores WHERE activo) AS total_profesores,
      (SELECT count(*)::int FROM horarios WHERE dia_semana=$1) AS total_clases_hoy,
      (SELECT count(*)::int FROM asistencias_profesor WHERE fecha=$2::date) AS presentes_hoy,
      (SELECT count(*)::int FROM asistencias_profesor WHERE fecha=$2::date AND estado='tardanza') AS tardanzas_hoy,
      (SELECT count(*)::int FROM horarios h WHERE h.dia_semana=$1
         AND h.hora_inicio + ($3 * interval '1 minute') < $4::time
         AND NOT EXISTS (SELECT 1 FROM asistencias_profesor a WHERE a.horario_id=h.id AND a.fecha=$2::date)) AS ausentes_hoy`,
    [t.dow, t.fecha, cfg.limiteMin, t.hora]);
  res.json(r.rows[0]);
}));

app.get('/api/admin/asistencias', admin, wrap(async (req, res) => {
  const t = L.ahora();
  const fecha = /^\d{4}-\d{2}-\d{2}$/.test(req.query.fecha || '') ? req.query.fecha : t.fecha;
  const pid = req.query.profesor_id ? parseInt(req.query.profesor_id, 10) : null;
  const r = await q(`
    SELECT p.nombre AS profesor_nombre, h.id AS horario_id, h.materia, h.modalidad, COALESCE(s.nombre,'') AS salon,
           COALESCE(a.estado,'ausente') AS estado, COALESCE(a.minutos_tarde,0)::int AS minutos_tarde,
           ${HORA_ISO('a.hora_registro')} AS hora_registro
    FROM horarios h
    JOIN profesores p ON p.id=h.profesor_id
    LEFT JOIN salones s ON s.id=h.salon_id
    LEFT JOIN asistencias_profesor a ON a.horario_id=h.id AND a.fecha=$1::date
    WHERE h.dia_semana = extract(isodow FROM $1::date)
      AND ($2::int IS NULL OR h.profesor_id=$2)
      AND (a.id IS NOT NULL OR $1::date < $3::date
           OR h.hora_inicio + ($4 * interval '1 minute') < $5::time)
    ORDER BY a.hora_registro NULLS LAST, h.hora_inicio
    LIMIT 1000`, [fecha, pid, t.fecha, cfg.limiteMin, t.hora]);
  res.json(r.rows);
}));

const like = (s) => '%' + String(s || '').replace(/[%_\\]/g, ' ').trim() + '%';
const pag = (req) => {
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 30));
  return { page, limit, offset: (page - 1) * limit };
};

app.get('/api/admin/profesores', admin, wrap(async (req, res) => {
  const { page, limit, offset } = pag(req);
  const b = String(req.query.q || '').trim();
  const [rows, tot] = await Promise.all([
    q(`SELECT id, cedula, nombre, correo, activo FROM profesores
       WHERE ($1::text='' OR nombre ILIKE $2 OR cedula ILIKE $2) ORDER BY nombre LIMIT $3 OFFSET $4`,
      [b, like(b), limit, offset]),
    q(`SELECT count(*)::int AS n FROM profesores WHERE ($1::text='' OR nombre ILIKE $2 OR cedula ILIKE $2)`, [b, like(b)]),
  ]);
  res.json({ page, total: tot.rows[0].n, profesores: rows.rows });
}));

app.get('/api/admin/estadisticas', admin, wrap(async (req, res) => {
  const { page, limit, offset } = pag(req);
  const b = String(req.query.q || '').trim();
  const t = L.ahora();
  const [rows, tot] = await Promise.all([
    q(`SELECT p.id, p.nombre, p.cedula, c.a_tiempo, c.tardanzas,
              GREATEST(esperadas_prof(p.id, $2::date - $3::int, $2::date, $4::time) - c.a_tiempo - c.tardanzas, 0)::int AS ausencias
       FROM (SELECT id, nombre, cedula FROM profesores
             WHERE activo AND ($1::text='' OR nombre ILIKE $5 OR cedula ILIKE $5)
             ORDER BY nombre LIMIT $6 OFFSET $7) p
       LEFT JOIN LATERAL (
         SELECT count(*) FILTER (WHERE estado='a_tiempo')::int AS a_tiempo,
                count(*) FILTER (WHERE estado='tardanza')::int AS tardanzas
         FROM asistencias_profesor a
         WHERE a.profesor_id=p.id AND a.fecha >= $2::date - $3::int AND a.fecha <= $2::date) c ON true
       ORDER BY p.nombre`, [b, t.fecha, cfg.diasStats, t.hora, like(b), limit, offset]),
    q(`SELECT count(*)::int AS n FROM profesores WHERE activo AND ($1::text='' OR nombre ILIKE $2 OR cedula ILIKE $2)`, [b, like(b)]),
  ]);
  res.json({ page, total: tot.rows[0].n, profesores: rows.rows });
}));

app.get('/api/admin/profesores/:id/detalle', admin, wrap(async (req, res) => {
  const id = parseInt(req.params.id, 10);
  const t = L.ahora();
  const p = await q('SELECT id, nombre, cedula, correo FROM profesores WHERE id=$1', [id]);
  if (!p.rows[0]) throw new ErrorApp(404, 'Profesor no encontrado', 'NO_ENCONTRADO');
  const [st, hist] = await Promise.all([
    q(`SELECT count(*) FILTER (WHERE estado='a_tiempo')::int AS a_tiempo,
              count(*) FILTER (WHERE estado='tardanza')::int AS tardanzas,
              GREATEST(esperadas_prof($1, $2::date - $3::int, $2::date, $4::time)
                - count(*)::int, 0)::int AS ausencias
       FROM asistencias_profesor WHERE profesor_id=$1 AND fecha >= $2::date - $3::int AND fecha <= $2::date`,
      [id, t.fecha, cfg.diasStats, t.hora]),
    q(`SELECT to_char(d::date,'YYYY-MM-DD') AS fecha, h.materia, COALESCE(s.nombre,'') AS salon,
              COALESCE(a.estado,'ausente') AS estado, COALESCE(a.minutos_tarde,0)::int AS minutos_tarde,
              ${HORA_ISO('a.hora_registro')} AS hora_registro
       FROM horarios h
       CROSS JOIN generate_series(($2::date - 60)::timestamp, $2::date::timestamp, interval '1 day') d
       LEFT JOIN salones s ON s.id=h.salon_id
       LEFT JOIN asistencias_profesor a ON a.horario_id=h.id AND a.fecha=d::date
       WHERE h.profesor_id=$1 AND extract(isodow FROM d)=h.dia_semana
         AND (a.id IS NOT NULL OR d::date < $2::date OR h.hora_inicio + ($3 * interval '1 minute') < $4::time)
       ORDER BY d DESC, h.hora_inicio DESC LIMIT 100`, [id, t.fecha, cfg.limiteMin, t.hora]),
  ]);
  res.json({ ...p.rows[0], estadisticas: st.rows[0], historial: hist.rows });
}));

// ── Revisión de asistencias offline ────────────────────────────────
app.get('/api/admin/offline', admin, wrap(async (req, res) => {
  const { page, limit, offset } = pag(req);
  const est = ['pendiente', 'aprobada', 'rechazada'].includes(req.query.estado) ? req.query.estado : 'pendiente';
  const r = await q(`
    SELECT o.id, o.rol, o.estado, o.motivo, COALESCE(p.nombre, e.nombre) AS nombre, h.materia,
           COALESCE(s.nombre,'') AS salon, ${HORA_ISO('o.hora_dispositivo')} AS hora_dispositivo,
           ${HORA_ISO('o.hora_envio')} AS hora_envio, o.distancia_m, o.fuera_zona,
           o.score_evidencia, o.score_envio,
           (SELECT count(*)::int FROM asistencias_offline WHERE estado=$1) AS total
    FROM asistencias_offline o
    JOIN horarios h ON h.id=o.horario_id
    LEFT JOIN salones s ON s.id=h.salon_id
    LEFT JOIN profesores p ON o.rol='profesor' AND p.id=o.usuario_id
    LEFT JOIN estudiantes e ON o.rol='estudiante' AND e.id=o.usuario_id
    WHERE o.estado=$1 ORDER BY o.hora_envio DESC LIMIT $2 OFFSET $3`, [est, limit, offset]);
  res.json({ page, total: r.rows[0]?.total ?? 0, items: r.rows });
}));

app.get('/api/admin/asistencias/profesor/:id/foto-salon', admin, wrap(async (req, res) => {
  const r = await q('SELECT foto_salon FROM asistencias_profesor WHERE id=$1', [parseInt(req.params.id, 10) || 0]);
  if (!r.rows[0]?.foto_salon) throw new ErrorApp(404, 'Sin foto del salón', 'NO_ENCONTRADO');
  res.set('Cache-Control', 'private, max-age=3600').type('image/jpeg').send(r.rows[0].foto_salon);
}));

app.get('/api/admin/offline/:id/foto', admin, wrap(async (req, res) => {
  const r = await q('SELECT foto_evidencia FROM asistencias_offline WHERE id=$1', [parseInt(req.params.id, 10) || 0]);
  if (!r.rows[0]) throw new ErrorApp(404, 'No encontrado', 'NO_ENCONTRADO');
  res.set('Cache-Control', 'private, max-age=3600').type('image/jpeg').send(r.rows[0].foto_evidencia);
}));

app.post('/api/admin/offline/:id/:accion', admin, wrap(async (req, res) => {
  const id = parseInt(req.params.id, 10), accion = req.params.accion;
  if (!id || !['aprobar', 'rechazar'].includes(accion)) throw new ErrorApp(404, 'No existe', 'NOT_FOUND');
  const motivo = String(req.body?.motivo || '').trim().slice(0, 200) || null;
  if (accion === 'rechazar') {
    const u = await q(`UPDATE asistencias_offline SET estado='rechazada', motivo=$2, revisado_por=$3, revisado_en=now()
                       WHERE id=$1 AND estado='pendiente'`, [id, motivo, req.user.sub]);
    if (!u.rowCount) throw new ErrorApp(409, 'Ya fue revisada', 'YA_REVISADA');
    return res.json({ success: true });
  }
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const o = (await c.query(`SELECT o.*, to_char(o.fecha,'YYYY-MM-DD') AS fecha_txt, h.hora_inicio::text AS ini
                              FROM asistencias_offline o JOIN horarios h ON h.id=o.horario_id
                              WHERE o.id=$1 FOR UPDATE OF o`, [id])).rows[0];
    if (!o) throw new ErrorApp(404, 'No encontrado', 'NO_ENCONTRADO');
    if (o.estado !== 'pendiente') throw new ErrorApp(409, 'Ya fue revisada', 'YA_REVISADA');
    const t = L.ahora(new Date(o.hora_dispositivo)), ini = L.toMin(o.ini);
    const hash = crypto.createHash('sha256').update(o.foto_evidencia).digest('hex');
    try {
      if (o.rol === 'profesor') {
        const tarde = Math.max(0, t.min - ini);
        await c.query(`INSERT INTO asistencias_profesor
          (horario_id, profesor_id, fecha, hora_registro, estado, minutos_tarde, lat, lon, distancia_m, face_score, foto_hash)
          VALUES ($1,$2,$3::date,$4,$5,$6,$7,$8,$9,$10,$11)`,
          [o.horario_id, o.usuario_id, o.fecha_txt, o.hora_dispositivo, tarde <= cfg.tolMin ? 'a_tiempo' : 'tardanza',
           tarde, o.lat, o.lon, o.distancia_m, o.score_evidencia, hash]);
      } else {
        await c.query(`INSERT INTO asistencias_estudiante
          (horario_id, estudiante_id, fecha, hora_registro, estado, lat, lon, distancia_m, face_score, foto_hash)
          VALUES ($1,$2,$3::date,$4,$5,$6,$7,$8,$9,$10)`,
          [o.horario_id, o.usuario_id, o.fecha_txt, o.hora_dispositivo, t.min <= ini + cfg.estTolMin ? 'presente' : 'tardanza',
           o.lat, o.lon, o.distancia_m, o.score_evidencia, hash]);
      }
    } catch (e) {
      if (e.code === '23505') {
        const foto = /foto_hash/.test(e.constraint || '');
        throw new ErrorApp(409, foto ? 'Esa foto ya fue usada en otro registro' : 'Ya existe una asistencia para esa clase ese día',
          foto ? 'FOTO_REPETIDA' : 'YA_REGISTRADA');
      }
      throw e;
    }
    await c.query(`UPDATE asistencias_offline SET estado='aprobada', motivo=$2, revisado_por=$3, revisado_en=now() WHERE id=$1`,
      [id, motivo, req.user.sub]);
    await c.query('COMMIT');
    res.json({ success: true });
  } catch (e) { await c.query('ROLLBACK').catch(() => {}); throw e; }
  finally { c.release(); }
}));

// Liberar celular o reiniciar rostro (p. ej. cambió de teléfono)
app.post('/api/admin/reset/:que', admin, wrap(async (req, res) => {
  const { rol, id } = req.body || {};
  if (!TABLA[rol] || !parseInt(id, 10)) throw new ErrorApp(400, 'Datos inválidos', 'BAD_REQUEST');
  if (req.params.que === 'dispositivo') await q(`UPDATE ${TABLA[rol]} SET device_id=NULL WHERE id=$1`, [id]);
  else if (req.params.que === 'rostro') await q('DELETE FROM rostros_faciales WHERE usuario_id=$1 AND rol=$2', [id, rol]);
  else throw new ErrorApp(404, 'No existe', 'NOT_FOUND');
  res.json({ success: true });
}));

// ── Importación masiva ─────────────────────────────────────────────
const parseDia = (d) => {
  if (Number.isInteger(+d) && +d >= 1 && +d <= 7) return +d;
  const n = String(d || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  const i = ['', 'lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo'].indexOf(n);
  return i > 0 ? i : null;
};
async function hashLote(lista, key) {
  const out = [];
  for (let i = 0; i < lista.length; i += 8)
    out.push(...await Promise.all(lista.slice(i, i + 8).map((x) => (x[key] ? L.hashPw(x[key]) : null))));
  return out;
}
app.post('/api/admin/importar', admin, wrap(async (req, res) => {
  const b = req.body || {}, arr = (k) => (Array.isArray(b[k]) ? b[k] : []);
  const profs = arr('profesores'), ests = arr('estudiantes');
  const res_ = { profesores: 0, estudiantes: 0, salones: 0, horarios: 0, inscripciones: 0, avisos: [] };
  const aviso = (m) => { if (res_.avisos.length < 50) res_.avisos.push(m); };
  const hp = await hashLote(profs, 'codigo'), he = await hashLote(ests, 'codigo');
  const c = await pool.connect();
  try {
    await c.query('BEGIN');

    // Eliminar: {"eliminar":{"confirmar":true,"profesores":["cedula"],"estudiantes":["usuario"],
    //            "horarios":["clave"],"inscripciones":[{"estudiante":"usuario","clave":"clave"}]}}
    // Borra también sus asistencias, listas e historial. Exige "confirmar":true.
    if (b.eliminar && typeof b.eliminar === 'object') {
      const el = b.eliminar, lista = (k) => (Array.isArray(el[k]) ? el[k] : []);
      if (el.confirmar !== true)
        throw new Error('Para eliminar agrega "confirmar":true dentro de "eliminar"');
      const txt = (v) => String(v ?? '').trim();
      res_.eliminados = { profesores: 0, estudiantes: 0, horarios: 0, inscripciones: 0 };
      for (const i of lista('inscripciones')) {
        const r = await c.query(`DELETE FROM inscripciones WHERE
          estudiante_id=(SELECT id FROM estudiantes WHERE usuario=$1)
          AND horario_id=(SELECT id FROM horarios WHERE clave=$2)`, [txt(i.estudiante).toLowerCase(), txt(i.clave)]);
        res_.eliminados.inscripciones += r.rowCount;
      }
      for (const clave of lista('horarios')) {
        const r = await c.query('DELETE FROM horarios WHERE clave=$1', [txt(clave)]);
        res_.eliminados.horarios += r.rowCount;
      }
      for (const u of lista('estudiantes')) {
        const r = await c.query('DELETE FROM estudiantes WHERE usuario=$1 RETURNING id', [txt(u).toLowerCase()]);
        for (const x of r.rows) {
          await c.query("DELETE FROM rostros_faciales WHERE rol='estudiante' AND usuario_id=$1", [x.id]);
          await c.query("DELETE FROM asistencias_offline WHERE rol='estudiante' AND usuario_id=$1", [x.id]);
        }
        res_.eliminados.estudiantes += r.rowCount;
      }
      for (const ced of lista('profesores')) {
        const r = await c.query('DELETE FROM profesores WHERE cedula=$1 RETURNING id', [txt(ced)]);
        for (const x of r.rows) {
          await c.query("DELETE FROM rostros_faciales WHERE rol='profesor' AND usuario_id=$1", [x.id]);
          await c.query("DELETE FROM asistencias_offline WHERE rol='profesor' AND usuario_id=$1", [x.id]);
        }
        res_.eliminados.profesores += r.rowCount;
      }
    }

    for (let i = 0; i < profs.length; i++) {
      const p = profs[i];
      if (!p.cedula || !p.nombre) { aviso(`Profesor omitido (falta cedula/nombre): ${JSON.stringify(p).slice(0, 60)}`); continue; }
      await c.query(`INSERT INTO profesores (cedula, nombre, correo, codigo_hash) VALUES ($1,$2,$3,COALESCE($4::text,'!'))
        ON CONFLICT (cedula) DO UPDATE SET nombre=EXCLUDED.nombre, correo=COALESCE(EXCLUDED.correo, profesores.correo),
          codigo_hash=CASE WHEN $4::text IS NULL THEN profesores.codigo_hash ELSE $4::text END,
          device_id=CASE WHEN $5::boolean THEN NULL ELSE profesores.device_id END`,
        [String(p.cedula).trim(), p.nombre, p.correo || null, hp[i], p.reset_dispositivo === true]);
      res_.profesores++;
    }
    for (let i = 0; i < ests.length; i++) {
      const e = ests[i];
      if (!e.usuario || !e.nombre) { aviso(`Estudiante omitido (falta usuario/nombre): ${JSON.stringify(e).slice(0, 60)}`); continue; }
      await c.query(`INSERT INTO estudiantes (usuario, nombre, codigo_hash) VALUES ($1,$2,COALESCE($3::text,'!'))
        ON CONFLICT (usuario) DO UPDATE SET nombre=EXCLUDED.nombre,
          codigo_hash=CASE WHEN $3::text IS NULL THEN estudiantes.codigo_hash ELSE $3::text END,
          device_id=CASE WHEN $4::boolean THEN NULL ELSE estudiantes.device_id END`,
        [String(e.usuario).trim().toLowerCase(), e.nombre, he[i], e.reset_dispositivo === true]);
      res_.estudiantes++;
    }
    for (const s of arr('salones')) {
      if (!s.nombre) continue;
      await c.query(`INSERT INTO salones (nombre, bloque, lat, lon, radio_m) VALUES ($1,$2,$3,$4,$5)
        ON CONFLICT (nombre) DO UPDATE SET bloque=EXCLUDED.bloque, lat=EXCLUDED.lat, lon=EXCLUDED.lon, radio_m=EXCLUDED.radio_m`,
        [s.nombre, s.bloque || null, s.lat ?? null, s.lon ?? null, s.radio_m ?? null]);
      res_.salones++;
    }
    for (const h of arr('horarios')) {
      const dia = parseDia(h.dia_semana);
      if (!h.profesor_cedula || !h.materia || !dia || !h.hora_inicio || !h.hora_fin) { aviso(`Horario omitido: ${JSON.stringify(h).slice(0, 70)}`); continue; }
      const clave = h.clave || `${h.profesor_cedula}-${h.materia}-${dia}-${h.hora_inicio}`;
      const modalidad = h.modalidad ? (String(h.modalidad).trim().toLowerCase() === 'virtual' ? 'virtual' : 'presencial') : null;
      const r = await c.query(`INSERT INTO horarios (clave, profesor_id, materia, salon_id, dia_semana, hora_inicio, hora_fin, modalidad)
        SELECT $1, p.id, $3, (SELECT id FROM salones WHERE nombre=$4), $5, $6::time, $7::time, COALESCE($8::text,'presencial')
        FROM profesores p WHERE p.cedula=$2
        ON CONFLICT (clave) DO UPDATE SET profesor_id=EXCLUDED.profesor_id, materia=EXCLUDED.materia,
          salon_id=EXCLUDED.salon_id, dia_semana=EXCLUDED.dia_semana, hora_inicio=EXCLUDED.hora_inicio, hora_fin=EXCLUDED.hora_fin,
          modalidad=CASE WHEN $8::text IS NULL THEN horarios.modalidad ELSE $8::text END`,
        [clave, String(h.profesor_cedula).trim(), h.materia, h.salon || null, dia, h.hora_inicio, h.hora_fin, modalidad]);
      if (r.rowCount) res_.horarios++; else aviso(`Horario sin profesor ${h.profesor_cedula}`);
    }
    for (const i of arr('inscripciones')) {
      const r = await c.query(`INSERT INTO inscripciones (estudiante_id, horario_id)
        SELECT e.id, h.id FROM estudiantes e, horarios h WHERE e.usuario=$1 AND h.clave=$2 ON CONFLICT DO NOTHING`,
        [String(i.estudiante || '').trim().toLowerCase(), i.clave]);
      if (r.rowCount) res_.inscripciones++;
    }
    await c.query('COMMIT');
  } catch (e) { await c.query('ROLLBACK').catch(() => {}); throw new ErrorApp(400, 'Importación fallida: ' + e.message, 'IMPORT_ERROR'); }
  finally { c.release(); }
  res.json(res_);
}));

// Página simple para importar desde el celular
app.get('/importar', (_, res) => {
  res.set('Content-Security-Policy', "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'");
  res.type('html').send(`<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>Importar datos</title><style>body{font-family:system-ui;background:#0A1A12;color:#fff;padding:16px;max-width:640px;margin:auto}
input,textarea,button{width:100%;box-sizing:border-box;margin:6px 0;padding:12px;border-radius:10px;border:1px solid #1E3A28;background:#1A2E20;color:#fff;font-size:15px}
button{background:#006847;font-weight:700}pre{white-space:pre-wrap;background:#112218;padding:12px;border-radius:10px}</style>
<h2>Importar datos</h2><input id=c placeholder="Correo admin"><input id=p type=password placeholder="Contraseña">
<textarea id=j rows=14 placeholder='{"profesores":[{"cedula":"123","nombre":"Ana","codigo":"9911"}],"estudiantes":[{"usuario":"jperez","nombre":"Juan","codigo":"2024001"}],"salones":[{"nombre":"A-101","bloque":"A"}],"horarios":[{"clave":"MAT1","profesor_cedula":"123","materia":"Matemáticas","salon":"A-101","dia_semana":"Lunes","hora_inicio":"07:00","hora_fin":"09:00"}],"inscripciones":[{"estudiante":"jperez","clave":"MAT1"}]}'></textarea>
<button onclick=go()>Importar</button><pre id=o></pre>
<script>async function go(){const o=document.getElementById('o');o.textContent='Enviando...';try{
const l=await fetch('/api/auth/admin/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({correo:c.value,password:p.value})});
const d=await l.json();if(!l.ok){o.textContent=d.error;return}
const r=await fetch('/api/admin/importar',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+d.token},body:j.value});
o.textContent=JSON.stringify(await r.json(),null,2)}catch(e){o.textContent='Error: '+e.message}}</script>`);
});

// ── Errores ────────────────────────────────────────────────────────
app.use((req, res) => res.status(404).json({ error: 'No encontrado', code: 'NOT_FOUND' }));
app.use((err, req, res, _next) => {
  if (err instanceof ErrorApp) return res.status(err.status).json({ error: err.message, code: err.code });
  if (err.type === 'entity.too.large') return res.status(413).json({ error: 'Imagen demasiado grande', code: 'TOO_LARGE' });
  if (err.type === 'entity.parse.failed') return res.status(400).json({ error: 'JSON inválido', code: 'BAD_JSON' });
  console.error(err);
  res.status(500).json({ error: 'Error interno', code: 'INTERNAL' });
});

// ── Arranque ───────────────────────────────────────────────────────
async function migrar() {
  const c = await pool.connect();
  try {
    await c.query('SELECT pg_advisory_lock(424242)');
    await c.query(schema);
  } finally {
    await c.query('SELECT pg_advisory_unlock(424242)').catch(() => {});
    c.release();
  }
}
async function bootstrapAdmin() {
  const { ADMIN_CORREO: correo, ADMIN_PASSWORD: pw, ADMIN_NOMBRE: nombre } = process.env;
  if (!correo || !pw) return;
  await q(`INSERT INTO admins (nombre, correo, password_hash) VALUES ($1,$2,$3) ON CONFLICT (correo) DO NOTHING`,
    [nombre || 'Administrador', correo.trim().toLowerCase(), await L.hashPw(pw)]);
}
async function seedDemo() {
  if (process.env.SEED_DEMO !== 'true') return;
  if ((await q('SELECT 1 FROM profesores LIMIT 1')).rowCount) return;
  const t = L.ahora();
  const ini = Math.max(0, t.min - 5), fin = Math.min(23 * 60 + 59, ini + 120);
  const p = await q(`INSERT INTO profesores (cedula, nombre, codigo_hash) VALUES ('1000000001','Profesor Demo',$1) RETURNING id`, [await L.hashPw('1234')]);
  const e = await q(`INSERT INTO estudiantes (usuario, nombre, codigo_hash) VALUES ('demo','Estudiante Demo',$1) RETURNING id`, [await L.hashPw('1234')]);
  const s = await q(`INSERT INTO salones (nombre, bloque) VALUES ('Aula Demo','A') RETURNING id`);
  const h = await q(`INSERT INTO horarios (clave, profesor_id, materia, salon_id, dia_semana, hora_inicio, hora_fin)
    VALUES ('DEMO',$1,'Clase de prueba',$2,$3,$4::time,$5::time) RETURNING id`,
    [p.rows[0].id, s.rows[0].id, t.dow, L.hhmm(ini), L.hhmm(fin)]);
  await q('INSERT INTO inscripciones (estudiante_id, horario_id) VALUES ($1,$2)', [e.rows[0].id, h.rows[0].id]);
  console.warn('⚠ SEED_DEMO: usuarios de prueba creados (cédula 1000000001 / usuario demo, código 1234). Desactiva SEED_DEMO en producción.');
}

async function main() {
  L.validarConfig();
  await migrar();
  await bootstrapAdmin();
  await seedDemo();
  if (cfg.campusLat == null) console.warn('⚠ CAMPUS_LAT/CAMPUS_LON no configurados: NO se valida la ubicación.');
  const server = app.listen(cfg.port, () => console.log('API lista en puerto', cfg.port));
  const cerrar = () => server.close(() => pool.end().then(() => process.exit(0)));
  process.on('SIGTERM', cerrar); process.on('SIGINT', cerrar);
}
main().catch((e) => { console.error('Error al iniciar:', e.message); process.exit(1); });
