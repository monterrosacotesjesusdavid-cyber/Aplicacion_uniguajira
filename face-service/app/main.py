"""Servicio de reconociimiento facial (InsightFace) para UniGuajira Asistencia.

Sin estado: no guarda fotos ni embeddings. Tu backend Node guarda el embedding
(cifrado) y lo envía en cada verificación 1:1.
"""
import base64
import hmac
import logging
import os
import time
from contextlib import asynccontextmanager

import cv2
import numpy as np
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from insightface.app import FaceAnalysis

API_KEY = os.environ.get("FACE_API_KEY", "")
THRESHOLD = float(os.environ.get("MATCH_THRESHOLD", "0.45"))   # calibrar con datos reales
MODEL = os.environ.get("FACE_MODEL", "buffalo_l")              # buffalo_s = más rápido
MODEL_DIR = os.environ.get("MODEL_DIR", "/srv/models")
MAX_BYTES = int(os.environ.get("MAX_IMAGE_BYTES", str(5 * 1024 * 1024)))
MIN_DET_SCORE = float(os.environ.get("MIN_DET_SCORE", "0.60"))
MIN_FACE_PX = int(os.environ.get("MIN_FACE_PX", "90"))
MAX_YAW = float(os.environ.get("MAX_YAW", "35"))
MAX_PITCH = float(os.environ.get("MAX_PITCH", "30"))
MIN_SHARPNESS = float(os.environ.get("MIN_SHARPNESS", "40"))
EMB_DIM = 512

log = logging.getLogger("face")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
models = {}


@asynccontextmanager
async def lifespan(_: FastAPI):
    if not API_KEY:
        raise RuntimeError("Falta FACE_API_KEY")
    fa = FaceAnalysis(name=MODEL, root=MODEL_DIR, providers=["CPUExecutionProvider"])
    fa.prepare(ctx_id=-1, det_size=(640, 640))
    models["fa"] = fa
    log.info("Modelo %s cargado", MODEL)
    yield


app = FastAPI(title="UniGuajira Face Service", version="1.0.0", lifespan=lifespan)


def auth(x_api_key: str = Header(default="")):
    if not hmac.compare_digest(x_api_key.encode(), API_KEY.encode()):
        raise HTTPException(401, {"code": "UNAUTHORIZED"})


def fail(code: str, msg: str):
    raise HTTPException(422, {"code": code, "message": msg})


def analyze(data: bytes):
    """Devuelve (face, calidad). Rechaza fotos que no sirvan para reconocer."""
    if len(data) > MAX_BYTES:
        raise HTTPException(413, {"code": "IMAGE_TOO_LARGE"})
    img = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        fail("BAD_IMAGE", "Imagen inválida")
    faces = models["fa"].get(img)
    if not faces:
        fail("NO_FACE", "No se detectó ningún rostro")
    faces.sort(key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]), reverse=True)
    face = faces[0]
    if len(faces) > 1:
        a1 = (faces[1].bbox[2] - faces[1].bbox[0]) * (faces[1].bbox[3] - faces[1].bbox[1])
        a0 = (face.bbox[2] - face.bbox[0]) * (face.bbox[3] - face.bbox[1])
        if a1 > 0.35 * a0:
            fail("MULTIPLE_FACES", "Hay más de una persona en la foto")
    x1, y1, x2, y2 = [int(v) for v in face.bbox]
    side = min(x2 - x1, y2 - y1)
    if float(face.det_score) < MIN_DET_SCORE:
        fail("LOW_CONFIDENCE", "Rostro poco claro")
    if side < MIN_FACE_PX:
        fail("FACE_TOO_SMALL", "Acércate más a la cámara")
    crop = img[max(y1, 0):y2, max(x1, 0):x2]
    sharp = float(cv2.Laplacian(cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY), cv2.CV_64F).var())
    if sharp < MIN_SHARPNESS:
        fail("BLURRY", "Foto borrosa, mejora la luz y no te muevas")
    pose = getattr(face, "pose", None)
    if pose is not None and (abs(pose[1]) > MAX_YAW or abs(pose[0]) > MAX_PITCH):
        fail("BAD_POSE", "Mira de frente a la cámara")
    quality = {"det_score": round(float(face.det_score), 3), "face_px": side,
               "sharpness": round(sharp, 1)}
    return face, quality


def decode_emb(b64: str) -> np.ndarray:
    try:
        raw = base64.b64decode(b64, validate=True)
        v = np.frombuffer(raw, dtype=np.float32)
    except Exception:
        raise HTTPException(400, {"code": "BAD_EMBEDDING"})
    if v.shape[0] != EMB_DIM:
        raise HTTPException(400, {"code": "BAD_EMBEDDING"})
    n = np.linalg.norm(v)
    return v / n if n else v


@app.get("/health")
def health():
    return {"ok": "fa" in models, "model": MODEL, "threshold": THRESHOLD}


@app.post("/v1/embed", dependencies=[Depends(auth)])
def embed(image: UploadFile = File(...)):
    """Enrolamiento: foto -> embedding (base64 de 512 float32)."""
    t = time.perf_counter()
    face, q = analyze(image.file.read())
    emb = face.normed_embedding.astype(np.float32)
    log.info("embed ok %.0fms", (time.perf_counter() - t) * 1000)
    return {"embedding": base64.b64encode(emb.tobytes()).decode(), "quality": q}


@app.post("/v1/verify", dependencies=[Depends(auth)])
def verify(image: UploadFile = File(...), embedding: str = Form(...)):
    """Verificación 1:1: selfie vs embedding guardado del usuario."""
    t = time.perf_counter()
    ref = decode_emb(embedding)
    face, q = analyze(image.file.read())
    score = float(np.dot(face.normed_embedding, ref))
    match = score >= THRESHOLD
    log.info("verify match=%s score=%.3f %.0fms", match, score, (time.perf_counter() - t) * 1000)
    return {"match": match, "score": round(score, 4), "threshold": THRESHOLD, "quality": q}
