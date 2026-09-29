const crypto = require('crypto');
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
  windowMs: 15 * 60 * 1000, limit: 10, standardHeaders: true, legacyHeaders: false,
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
function datosFirma(body) {
  const hid = parseInt(body.horario_id, 10);
  const lat = Number(body.latitud), lon = Number(body.longitud);
  if (!hid || !Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180)
    throw new ErrorApp(400, 'Datos incompletos', 'BAD_REQUEST');
  if (body.liveness !== true) throw new ErrorApp(400, 'Falta la prueba de vida', 'SIN_LIVENESS');
  return { hid, lat, lon };
}

// ── Salud ──────────────────────────────────────────────────────────
app.get('/', (_, res) => res.json({ servicio: 'UniGuajira API', ok: true }));
app.get('/health', wrap(async (_, res) => { await q('SELECT 1'); res.json({ ok: true }); }));

// ── AUTH ───────────────────────────────────────────────────────────
app.post('/api/auth/login', limLogin, wrap(async (req, res) => {
  const { identificador, codigo } = req.body || {};
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

  if (user.device_id && user.device_id !== did)
    throw new ErrorApp(403, 'Esta cuenta está vinculada a otro celular. Pide al administrador que la libere.', 'DEVICE_MISMATCH');
  if (!user.device_id)
    await q(`UPDATE ${TABLA[rol]} SET device_id=$1 WHERE id=$2 AND device_id IS NULL`, [did, user.id]);

  const f = await q('SELECT 1 FROM rostros_faciales WHERE usuario_id=$1 AND rol=$2', [user.id, rol]);
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

// ── ESTUDIANTE ─────────────────────────────────────────────────────
app.get('/api/estudiante/clases', auth(['estudiante']), wrap(async (req, res) => {
  const t = L.ahora();
  const r = await q(`
    SELECT h.id, h.materia, p.nombre AS profesor_nombre, COALESCE(s.nombre,'') AS salon,
           h.hora_inicio::text AS hora_inicio, h.hora_fin::text AS hora_fin,
           EXISTS (SELECT 1 FROM asistencias_estudiante a
                   WHERE a.horario_id=h.id AND a.estudiante_id=$1 AND a.fecha=$3::date) AS ya_firmo
    FROM inscripciones i
    JOIN horarios h ON h.id=i.horario_id
    JOIN profesores p ON p.id=h.profesor_id
    LEFT JOIN salones s ON s.id=h.salon_id
    WHERE i.estudiante_id=$1 AND h.dia_semana=$2
    ORDER BY h.hora_inicio`, [req.user.sub, t.dow, t.fecha]);
  res.json(r.rows.map((c) => {
    if (c.ya_firmo) return { ...c, disponible: false, mensaje: 'Firmado' };
    const v = L.ventanaEstudiante(L.toMin(c.hora_inicio), L.toMin(c.hora_fin), t.min);
    return { ...c, disponible: v.disponible, mensaje: v.mensaje };
  }));
}));

app.get('/api/estudiante/asistencias/:id', auth(['estudiante']), wrap(async (req, res) => {
  const hid = parseInt(req.params.id, 10);
  if (!hid) throw new ErrorApp(400, 'Clase inválida', 'BAD_REQUEST');
  const t = L.ahora();
  const r = await q(`
    WITH h AS (
      SELECT h.id, h.dia_semana, h.hora_fin, i.creado
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
    WHERE f.fecha < $3::date OR a.id IS NOT NULL
       OR $4::int >= (extract(hour FROM h.hora_fin)*60 + extract(minute FROM h.hora_fin))
    ORDER BY f.fecha DESC`, [req.user.sub, hid, t.fecha, t.min]);
  res.json(r.rows);
}));

app.post('/api/estudiante/firmar', auth(['estudiante']), limFirma, wrap(async (req, res) => {
  const { hid, lat, lon } = datosFirma(req.body || {});
  const t = L.ahora();
  const e = await q('SELECT activo FROM estudiantes WHERE id=$1', [req.user.sub]);
  if (!e.rows[0]?.activo) throw new ErrorApp(403, 'Cuenta desactivada', 'INACTIVO');
  const r = await q(`
    SELECT h.hora_inicio::text AS ini, h.hora_fin::text AS fin, s.lat, s.lon, s.radio_m
    FROM inscripciones i JOIN horarios h ON h.id=i.horario_id
    LEFT JOIN salones s ON s.id=h.salon_id
    WHERE i.estudiante_id=$1 AND h.id=$2 AND h.dia_semana=$3`, [req.user.sub, hid, t.dow]);
  const h = r.rows[0];
  if (!h) throw new ErrorApp(404, 'Esa clase no es hoy o no estás inscrito', 'NO_CLASE');
  const ya = await q('SELECT 1 FROM asistencias_estudiante WHERE horario_id=$1 AND estudiante_id=$2 AND fecha=$3::date',
    [hid, req.user.sub, t.fecha]);
  if (ya.rowCount) throw new ErrorApp(409, 'Ya firmaste esta clase', 'YA_REGISTRADA');
  const v = L.ventanaEstudiante(L.toMin(h.ini), L.toMin(h.fin), t.min);
  if (!v.disponible) throw new ErrorApp(403, v.mensaje, 'FUERA_DE_HORARIO');
  const z = L.chequearZona(lat, lon, h);
  if (!z.ok) throw new ErrorApp(403, `Estás fuera del salón (a ${z.dist} m)`, 'FUERA_DE_ZONA');
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
    SELECT h.id, h.materia, COALESCE(s.nombre,'') AS salon, NULLIF(s.bloque,'') AS bloque,
           h.hora_inicio::text AS hora_inicio, h.hora_fin::text AS hora_fin,
           a.estado AS asistencia_estado, ${HORA_ISO('a.hora_registro')} AS hora_registro
    FROM horarios h
    LEFT JOIN salones s ON s.id=h.salon_id
    LEFT JOIN asistencias_profesor a ON a.horario_id=h.id AND a.fecha=$3::date
    WHERE h.profesor_id=$1 AND h.dia_semana=$2
    ORDER BY h.hora_inicio`, [req.user.sub, t.dow, t.fecha]);
  res.json(r.rows.map((c) => {
    if (c.asistencia_estado) return { ...c, disponible: false, mensaje: '' };
    const v = L.ventanaProfesor(L.toMin(c.hora_inicio), t.min);
    return { ...c, disponible: v.disponible, mensaje: v.mensaje };
  }));
}));

app.get('/api/profesor/horario-semana', auth(['profesor']), wrap(async (req, res) => {
  const r = await q(`
    SELECT h.dia_semana, h.materia, COALESCE(s.nombre,'') AS salon,
           h.hora_inicio::text AS hora_inicio, h.hora_fin::text AS hora_fin
    FROM horarios h LEFT JOIN salones s ON s.id=h.salon_id
    WHERE h.profesor_id=$1 ORDER BY h.dia_semana, h.hora_inicio`, [req.user.sub]);
  res.json(r.rows.map((c) => ({ ...c, dia_semana: DIAS[c.dia_semana] })));
}));

app.post('/api/profesor/registrar-asistencia', auth(['profesor']), limFirma, wrap(async (req, res) => {
  const { hid, lat, lon } = datosFirma(req.body || {});
  const t = L.ahora();
  const p = await q('SELECT activo FROM profesores WHERE id=$1', [req.user.sub]);
  if (!p.rows[0]?.activo) throw new ErrorApp(403, 'Cuenta desactivada', 'INACTIVO');
  const r = await q(`
    SELECT h.hora_inicio::text AS ini, s.lat, s.lon, s.radio_m
    FROM horarios h LEFT JOIN salones s ON s.id=h.salon_id
    WHERE h.id=$1 AND h.profesor_id=$2 AND h.dia_semana=$3`, [hid, req.user.sub, t.dow]);
  const h = r.rows[0];
  if (!h) throw new ErrorApp(404, 'Esa clase no es hoy o no te pertenece', 'NO_CLASE');
  const ya = await q('SELECT 1 FROM asistencias_profesor WHERE horario_id=$1 AND fecha=$2::date', [hid, t.fecha]);
  if (ya.rowCount) throw new ErrorApp(409, 'Ya registraste esta clase', 'YA_REGISTRADA');
  const v = L.ventanaProfesor(L.toMin(h.ini), t.min);
  if (!v.disponible) throw new ErrorApp(403, v.mensaje, 'FUERA_DE_HORARIO');
  const z = L.chequearZona(lat, lon, h);
  if (!z.ok) throw new ErrorApp(403, `Estás fuera del salón (a ${z.dist} m)`, 'FUERA_DE_ZONA');
  const f = await verificarRostro('profesor', req.user.sub, req.body.foto_base64);
  try {
    await q(`INSERT INTO asistencias_profesor
      (horario_id, profesor_id, fecha, estado, minutos_tarde, lat, lon, distancia_m, face_score, foto_hash)
      VALUES ($1,$2,$3::date,$4,$5,$6,$7,$8,$9,$10)`,
      [hid, req.user.sub, t.fecha, v.estado, v.tarde, lat, lon, z.dist, f.score, f.hash]);
  } catch (err) { dupe(err); }
  res.json({ success: true, estado: v.estado, minutos_tarde: v.tarde });
}));

// ── ADMIN ──────────────────────────────────────────────────────────
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
    SELECT p.nombre AS profesor_nombre, h.materia, COALESCE(s.nombre,'') AS salon,
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
    for (let i = 0; i < profs.length; i++) {
      const p = profs[i];
      if (!p.cedula || !p.nombre) { aviso(`Profesor omitido (falta cedula/nombre): ${JSON.stringify(p).slice(0, 60)}`); continue; }
      await c.query(`INSERT INTO profesores (cedula, nombre, correo, codigo_hash) VALUES ($1,$2,$3,COALESCE($4::text,'!'))
        ON CONFLICT (cedula) DO UPDATE SET nombre=EXCLUDED.nombre, correo=COALESCE(EXCLUDED.correo, profesores.correo),
          codigo_hash=CASE WHEN $4::text IS NULL THEN profesores.codigo_hash ELSE $4::text END`,
        [String(p.cedula).trim(), p.nombre, p.correo || null, hp[i]]);
      res_.profesores++;
    }
    for (let i = 0; i < ests.length; i++) {
      const e = ests[i];
      if (!e.usuario || !e.nombre) { aviso(`Estudiante omitido (falta usuario/nombre): ${JSON.stringify(e).slice(0, 60)}`); continue; }
      await c.query(`INSERT INTO estudiantes (usuario, nombre, codigo_hash) VALUES ($1,$2,COALESCE($3::text,'!'))
        ON CONFLICT (usuario) DO UPDATE SET nombre=EXCLUDED.nombre,
          codigo_hash=CASE WHEN $3::text IS NULL THEN estudiantes.codigo_hash ELSE $3::text END`,
        [String(e.usuario).trim().toLowerCase(), e.nombre, he[i]]);
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
      const r = await c.query(`INSERT INTO horarios (clave, profesor_id, materia, salon_id, dia_semana, hora_inicio, hora_fin)
        SELECT $1, p.id, $3, (SELECT id FROM salones WHERE nombre=$4), $5, $6::time, $7::time FROM profesores p WHERE p.cedula=$2
        ON CONFLICT (clave) DO UPDATE SET profesor_id=EXCLUDED.profesor_id, materia=EXCLUDED.materia,
          salon_id=EXCLUDED.salon_id, dia_semana=EXCLUDED.dia_semana, hora_inicio=EXCLUDED.hora_inicio, hora_fin=EXCLUDED.hora_fin`,
        [clave, String(h.profesor_cedula).trim(), h.materia, h.salon || null, dia, h.hora_inicio, h.hora_fin]);
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
