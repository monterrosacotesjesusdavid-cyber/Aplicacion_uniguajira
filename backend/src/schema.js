// Esquema idempotente: se ejecuta al arrancar (CREATE ... IF NOT EXISTS).
module.exports = `
CREATE TABLE IF NOT EXISTS admins (
  id SERIAL PRIMARY KEY, nombre TEXT NOT NULL,
  correo TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL,
  creado TIMESTAMPTZ NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS profesores (
  id SERIAL PRIMARY KEY, cedula TEXT UNIQUE NOT NULL, nombre TEXT NOT NULL,
  correo TEXT, codigo_hash TEXT NOT NULL, device_id TEXT,
  activo BOOLEAN NOT NULL DEFAULT true, creado TIMESTAMPTZ NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS estudiantes (
  id SERIAL PRIMARY KEY, usuario TEXT UNIQUE NOT NULL, nombre TEXT NOT NULL,
  codigo_hash TEXT NOT NULL, device_id TEXT,
  activo BOOLEAN NOT NULL DEFAULT true, creado TIMESTAMPTZ NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS salones (
  id SERIAL PRIMARY KEY, nombre TEXT UNIQUE NOT NULL, bloque TEXT,
  lat DOUBLE PRECISION, lon DOUBLE PRECISION, radio_m INT);

CREATE TABLE IF NOT EXISTS horarios (
  id SERIAL PRIMARY KEY, clave TEXT UNIQUE,
  profesor_id INT NOT NULL REFERENCES profesores(id) ON DELETE CASCADE,
  materia TEXT NOT NULL,
  salon_id INT REFERENCES salones(id) ON DELETE SET NULL,
  dia_semana SMALLINT NOT NULL CHECK (dia_semana BETWEEN 1 AND 7),
  hora_inicio TIME NOT NULL, hora_fin TIME NOT NULL);
CREATE INDEX IF NOT EXISTS idx_horarios_dia ON horarios(dia_semana);
CREATE INDEX IF NOT EXISTS idx_horarios_prof ON horarios(profesor_id);

CREATE TABLE IF NOT EXISTS inscripciones (
  estudiante_id INT NOT NULL REFERENCES estudiantes(id) ON DELETE CASCADE,
  horario_id INT NOT NULL REFERENCES horarios(id) ON DELETE CASCADE,
  creado DATE NOT NULL DEFAULT CURRENT_DATE,
  PRIMARY KEY (estudiante_id, horario_id));
CREATE INDEX IF NOT EXISTS idx_insc_horario ON inscripciones(horario_id);

CREATE TABLE IF NOT EXISTS rostros_faciales (
  usuario_id INT NOT NULL,
  rol TEXT NOT NULL CHECK (rol IN ('profesor','estudiante')),
  embedding_enc TEXT NOT NULL,
  creado TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (usuario_id, rol));

CREATE TABLE IF NOT EXISTS asistencias_profesor (
  id BIGSERIAL PRIMARY KEY,
  horario_id INT NOT NULL REFERENCES horarios(id) ON DELETE CASCADE,
  profesor_id INT NOT NULL, fecha DATE NOT NULL,
  hora_registro TIMESTAMPTZ NOT NULL DEFAULT now(),
  estado TEXT NOT NULL CHECK (estado IN ('a_tiempo','tardanza')),
  minutos_tarde INT NOT NULL DEFAULT 0,
  lat DOUBLE PRECISION, lon DOUBLE PRECISION, distancia_m INT,
  face_score REAL, foto_hash TEXT NOT NULL UNIQUE,
  UNIQUE (horario_id, fecha));
CREATE INDEX IF NOT EXISTS idx_ap_prof ON asistencias_profesor(profesor_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_ap_fecha ON asistencias_profesor(fecha);
ALTER TABLE asistencias_profesor ADD COLUMN IF NOT EXISTS foto_salon BYTEA;

CREATE TABLE IF NOT EXISTS asistencias_estudiante (
  id BIGSERIAL PRIMARY KEY,
  horario_id INT NOT NULL REFERENCES horarios(id) ON DELETE CASCADE,
  estudiante_id INT NOT NULL, fecha DATE NOT NULL,
  hora_registro TIMESTAMPTZ NOT NULL DEFAULT now(),
  estado TEXT NOT NULL CHECK (estado IN ('presente','tardanza')),
  lat DOUBLE PRECISION, lon DOUBLE PRECISION, distancia_m INT,
  face_score REAL, foto_hash TEXT NOT NULL UNIQUE,
  UNIQUE (horario_id, estudiante_id, fecha));
CREATE INDEX IF NOT EXISTS idx_ae_est ON asistencias_estudiante(estudiante_id, fecha DESC);

-- El profesor habilita la asistencia de los estudiantes para su clase de hoy.
CREATE TABLE IF NOT EXISTS sesiones_clase (
  horario_id INT NOT NULL REFERENCES horarios(id) ON DELETE CASCADE,
  fecha DATE NOT NULL,
  abierta_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  cerrada_en TIMESTAMPTZ,
  PRIMARY KEY (horario_id, fecha));

-- Evidencias tomadas sin internet: quedan pendientes hasta que un admin las revise.
CREATE TABLE IF NOT EXISTS asistencias_offline (
  id BIGSERIAL PRIMARY KEY,
  client_id TEXT NOT NULL UNIQUE,
  rol TEXT NOT NULL CHECK (rol IN ('profesor','estudiante')),
  usuario_id INT NOT NULL,
  horario_id INT NOT NULL REFERENCES horarios(id) ON DELETE CASCADE,
  fecha DATE NOT NULL,
  hora_dispositivo TIMESTAMPTZ NOT NULL,
  hora_envio TIMESTAMPTZ NOT NULL DEFAULT now(),
  lat DOUBLE PRECISION, lon DOUBLE PRECISION, distancia_m INT,
  fuera_zona BOOLEAN NOT NULL DEFAULT false,
  foto_evidencia BYTEA NOT NULL,
  score_evidencia REAL, score_envio REAL,
  estado TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','aprobada','rechazada')),
  motivo TEXT, revisado_por INT, revisado_en TIMESTAMPTZ);
CREATE INDEX IF NOT EXISTS idx_off_estado ON asistencias_offline(estado, hora_envio DESC);
CREATE INDEX IF NOT EXISTS idx_off_usuario ON asistencias_offline(rol, usuario_id, hora_envio DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_off_unico
  ON asistencias_offline(rol, usuario_id, horario_id, fecha) WHERE estado <> 'rechazada';

-- Clases virtuales (Meet): el profesor marca la asistencia de sus estudiantes.
ALTER TABLE horarios ADD COLUMN IF NOT EXISTS modalidad TEXT NOT NULL DEFAULT 'presencial'
  CHECK (modalidad IN ('presencial','virtual'));
ALTER TABLE asistencias_estudiante ALTER COLUMN foto_hash DROP NOT NULL;
ALTER TABLE asistencias_estudiante ADD COLUMN IF NOT EXISTS origen TEXT NOT NULL DEFAULT 'firma';
ALTER TABLE asistencias_estudiante ADD COLUMN IF NOT EXISTS marcado_por INT;

CREATE TABLE IF NOT EXISTS clases_virtuales (
  horario_id INT NOT NULL REFERENCES horarios(id) ON DELETE CASCADE,
  fecha DATE NOT NULL,
  link TEXT,
  cerrada_en TIMESTAMPTZ,
  PRIMARY KEY (horario_id, fecha));

CREATE TABLE IF NOT EXISTS virtual_historial (
  id BIGSERIAL PRIMARY KEY,
  horario_id INT NOT NULL REFERENCES horarios(id) ON DELETE CASCADE,
  fecha DATE NOT NULL,
  estudiante_id INT NOT NULL REFERENCES estudiantes(id) ON DELETE CASCADE,
  accion TEXT NOT NULL CHECK (accion IN ('presente','ausente')),
  por_rol TEXT NOT NULL CHECK (por_rol IN ('profesor','admin')),
  por_id INT NOT NULL,
  hecho_en TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS idx_vh_clase ON virtual_historial(horario_id, fecha, hecho_en DESC);

-- Retos de prueba de vida ya usados (cada reto sirve una sola vez).
CREATE TABLE IF NOT EXISTS liveness_usados (
  nonce TEXT PRIMARY KEY,
  foto_hash TEXT NOT NULL,
  validada BOOLEAN NOT NULL DEFAULT false,
  exp TIMESTAMPTZ NOT NULL);

CREATE OR REPLACE FUNCTION esperadas_prof(pid INT, desde DATE, hoy DATE, ahora_t TIME)
RETURNS INT LANGUAGE sql STABLE AS $$
  SELECT count(*)::int FROM horarios h,
    generate_series(desde::timestamp, hoy::timestamp, interval '1 day') d
  WHERE h.profesor_id = pid AND extract(isodow FROM d) = h.dia_semana
    AND (d::date < hoy OR h.hora_fin <= ahora_t)
$$;
`;
