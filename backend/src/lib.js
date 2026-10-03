const crypto = require('crypto');
const { promisify } = require('util');
const { Pool } = require('pg');
const jwt = require('jsonwebtoken');

const scrypt = promisify(crypto.scrypt);
const env = (k, d) => (process.env[k] !== undefined && process.env[k] !== '' ? process.env[k] : d);

const cfg = {
  port: +env('PORT', 3000),
  dbUrl: env('DATABASE_URL'),
  dbSsl: env('PGSSL', 'false') === 'true',
  jwtSecret: env('JWT_SECRET'),
  embKey: env('EMBEDDING_KEY'),            // 64 caracteres hex (32 bytes)
  faceUrl: env('FACE_URL'),
  faceKey: env('FACE_API_KEY'),
  tz: 'America/Bogota',
  campusLat: env('CAMPUS_LAT') ? +env('CAMPUS_LAT') : null,
  campusLon: env('CAMPUS_LON') ? +env('CAMPUS_LON') : null,
  radioM: +env('RADIO_METROS', 250),
  campusRadioM: +env('CAMPUS_RADIO_METROS', env('RADIO_METROS', 250)), // radio de todo el campus
  antesMin: +env('ANTES_MIN', 15),         // profesor puede firmar desde X min antes
  tolMin: +env('TOL_MIN', 10),             // a tiempo hasta X min después del inicio
  limiteMin: +env('LIMITE_MIN', 30),       // después de esto: ausente
  estTolMin: +env('EST_TOL_MIN', 15),      // estudiante: presente hasta X min
  diasStats: +env('DIAS_STATS', 90),
};

function validarConfig() {
  const faltan = [];
  if (!cfg.dbUrl) faltan.push('DATABASE_URL');
  if (!cfg.jwtSecret || cfg.jwtSecret.length < 32) faltan.push('JWT_SECRET (mín. 32 caracteres)');
  if (!/^[0-9a-fA-F]{64}$/.test(cfg.embKey || '')) faltan.push('EMBEDDING_KEY (64 caracteres hex)');
  if (faltan.length) throw new Error('Faltan variables: ' + faltan.join(', '));
}

const pool = new Pool({
  connectionString: cfg.dbUrl,
  max: +env('DB_POOL', 20),
  ssl: cfg.dbSsl ? { rejectUnauthorized: false } : false,
});
const q = (text, params) => pool.query(text, params);

// ── Contraseñas / códigos (scrypt nativo, no bloquea el event loop) ──
const P = { N: 16384, r: 8, p: 1 };
async function hashPw(pw) {
  const salt = crypto.randomBytes(16);
  const h = await scrypt(String(pw), salt, 32, P);
  return `s1$${salt.toString('base64')}$${h.toString('base64')}`;
}
async function checkPw(pw, stored) {
  try {
    const [v, s, h] = String(stored).split('$');
    if (v !== 's1') return false;
    const got = await scrypt(String(pw), Buffer.from(s, 'base64'), 32, P);
    const exp = Buffer.from(h, 'base64');
    return got.length === exp.length && crypto.timingSafeEqual(got, exp);
  } catch { return false; }
}

// ── Cifrado del embedding facial en reposo (AES-256-GCM) ──
function encrypt(text) {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', Buffer.from(cfg.embKey, 'hex'), iv);
  const ct = Buffer.concat([c.update(text, 'utf8'), c.final()]);
  return Buffer.concat([iv, c.getAuthTag(), ct]).toString('base64');
}
function decrypt(b64) {
  const raw = Buffer.from(b64, 'base64');
  const d = crypto.createDecipheriv('aes-256-gcm', Buffer.from(cfg.embKey, 'hex'), raw.subarray(0, 12));
  d.setAuthTag(raw.subarray(12, 28));
  return Buffer.concat([d.update(raw.subarray(28)), d.final()]).toString('utf8');
}

// ── JWT ──
const firmar = (u) => jwt.sign(u, cfg.jwtSecret, { expiresIn: '1d' });
const verificar = (t) => jwt.verify(t, cfg.jwtSecret);

// ── Tiempo (siempre hora de Colombia) ──
function ahora(d = new Date()) {
  const p = {};
  new Intl.DateTimeFormat('en-CA', {
    timeZone: cfg.tz, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23', weekday: 'short',
  }).formatToParts(d).forEach((x) => { p[x.type] = x.value; });
  const dow = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 }[p.weekday];
  const min = +p.hour * 60 + +p.minute;
  return { fecha: `${p.year}-${p.month}-${p.day}`, min, dow, hora: `${p.hour}:${p.minute}` };
}
const toMin = (t) => { const [h, m] = String(t).split(':'); return +h * 60 + +m; };
const hhmm = (m) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

// Ventana del profesor: [inicio-antes, inicio+tol] a tiempo; hasta inicio+limite tardanza
function ventanaProfesor(ini, now, fin) {
  const abre = ini - cfg.antesMin;
  if (now < abre) return { disponible: false, estado: null, mensaje: `Disponible a las ${hhmm(abre)}`, tarde: 0 };
  if (now <= ini + cfg.tolMin) return { disponible: true, estado: 'a_tiempo', mensaje: 'A tiempo', tarde: 0 };
  if (now <= fin) {
    const t = now - ini;
    return { disponible: true, estado: 'tardanza', mensaje: `Tardanza (+${t} min)`, tarde: t };
  }
  return { disponible: false, estado: null, mensaje: 'Tiempo expirado — Ausente', tarde: 0 };
}
// Ventana del estudiante: desde el inicio hasta EST_TOL_MIN minutos después
function ventanaEstudiante(ini, fin, now) {
  if (now < ini) return { disponible: false, estado: null, mensaje: `Disponible a las ${hhmm(ini)}` };
  if (now <= ini + cfg.estTolMin) return { disponible: true, estado: 'presente', mensaje: 'Presente' };
  return { disponible: false, estado: null, mensaje: 'Tiempo expirado — Ausente' };
}

// ── Geocerca ──
function distanciaM(lat1, lon1, lat2, lon2) {
  const R = 6371000, r = (x) => (x * Math.PI) / 180;
  const a = Math.sin(r(lat2 - lat1) / 2) ** 2 +
    Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(r(lon2 - lon1) / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}
// Devuelve {ok, dist}. Usa el salón si tiene coordenadas; si no, el campus; si no hay ninguno, no valida.
function chequearZona(lat, lon, salon) {
  let cLat = cfg.campusLat, cLon = cfg.campusLon, radio = cfg.radioM;
  if (salon && salon.lat != null && salon.lon != null) {
    cLat = salon.lat; cLon = salon.lon; radio = salon.radio_m || cfg.radioM;
  }
  if (cLat == null || cLon == null) return { ok: true, dist: null };
  const dist = Math.round(distanciaM(lat, lon, cLat, cLon));
  return { ok: dist <= radio, dist };
}

// ── Servicio facial ──
class ErrorApp extends Error {
  constructor(status, error, code) { super(error); this.status = status; this.code = code; }
}
async function faceCall(path, jpeg, embedding) {
  if (!cfg.faceUrl || !cfg.faceKey) throw new ErrorApp(503, 'Verificación facial no disponible', 'FACE_OFF');
  const form = new FormData();
  form.append('image', new Blob([jpeg], { type: 'image/jpeg' }), 'f.jpg');
  if (embedding) form.append('embedding', embedding);
  let r, d = {};
  try {
    r = await fetch(cfg.faceUrl + path, {
      method: 'POST', headers: { 'X-API-Key': cfg.faceKey }, body: form,
      signal: AbortSignal.timeout(15000),
    });
    d = await r.json().catch(() => ({}));
  } catch (e) {
    console.error('face service:', e.message);
    throw new ErrorApp(503, 'Verificación facial no disponible, intenta en unos minutos', 'FACE_DOWN');
  }
  if (r.ok) return d;
  const det = d.detail || {};
  if (r.status === 422) throw new ErrorApp(422, det.message || 'No se pudo leer tu rostro', det.code || 'FACE_BAD');
  console.error('face service status', r.status, det);
  throw new ErrorApp(503, 'Verificación facial no disponible, intenta en unos minutos', 'FACE_DOWN');
}

function decodificarFoto(b64) {
  if (typeof b64 !== 'string' || b64.length < 1000) throw new ErrorApp(400, 'Foto inválida', 'FOTO_INVALIDA');
  const buf = Buffer.from(b64, 'base64');
  if (buf.length < 500 || buf.length > 5 * 1024 * 1024) throw new ErrorApp(400, 'Foto inválida', 'FOTO_INVALIDA');
  return buf;
}

module.exports = {
  cfg, validarConfig, pool, q, hashPw, checkPw, encrypt, decrypt, firmar, verificar,
  ahora, toMin, hhmm, ventanaProfesor, ventanaEstudiante, chequearZona, faceCall,
  decodificarFoto, ErrorApp,
};
