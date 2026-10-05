"""Calibra MATCH_THRESHOLD con fotos reales de TU universidad.

Uso (dentro del contenedor o con las mismas dependencias):

    python calibrar.py ./fotos

Estructura de ./fotos: una carpeta por persona con 3 o más fotos suyas
(distintos días/luz, como las que tomaría la app).

    fotos/
      ana/   1.jpg 2.jpg 3.jpg
      luis/  1.jpg 2.jpg 3.jpg
      ...

Compara todas las parejas de la MISMA persona (genuinas) y de DISTINTAS personas
(impostores), y recomienda el umbral. Con pocas personas (<30) los porcentajes son
orientativos: repite la prueba cuando tengas más datos.
"""
import itertools
import os
import sys

import cv2
import numpy as np
from insightface.app import FaceAnalysis

MODEL = os.environ.get("FACE_MODEL", "buffalo_l")
MODEL_DIR = os.environ.get("MODEL_DIR", "/srv/models")


def embeddings(raiz):
    fa = FaceAnalysis(name=MODEL, root=MODEL_DIR, providers=["CPUExecutionProvider"])
    fa.prepare(ctx_id=-1, det_size=(640, 640))
    datos = {}
    for persona in sorted(os.listdir(raiz)):
        carpeta = os.path.join(raiz, persona)
        if not os.path.isdir(carpeta):
            continue
        for nombre in sorted(os.listdir(carpeta)):
            img = cv2.imread(os.path.join(carpeta, nombre))
            caras = fa.get(img) if img is not None else []
            if len(caras) != 1:
                print(f"  (se omite {persona}/{nombre}: {len(caras)} rostros)")
                continue
            datos.setdefault(persona, []).append(caras[0].normed_embedding)
    return {p: v for p, v in datos.items() if len(v) >= 2}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    datos = embeddings(sys.argv[1])
    if len(datos) < 2:
        sys.exit("Se necesitan al menos 2 personas con 2+ fotos válidas cada una.")
    gen, imp = [], []
    for v in datos.values():
        gen += [float(a @ b) for a, b in itertools.combinations(v, 2)]
    for (_, a), (_, b) in itertools.combinations(datos.items(), 2):
        imp += [float(x @ y) for x in a for y in b]
    gen, imp = np.array(gen), np.array(imp)
    print(f"\nPersonas: {len(datos)} | parejas genuinas: {len(gen)} | parejas impostoras: {len(imp)}")
    print(f"Genuinas   mín {gen.min():.3f}  p5 {np.percentile(gen, 5):.3f}  mediana {np.median(gen):.3f}")
    print(f"Impostores p95 {np.percentile(imp, 95):.3f}  p99.9 {np.percentile(imp, 99.9):.3f}  máx {imp.max():.3f}")

    mejor = None
    print("\numbral   FRR (rechaza a quien SÍ es)   FAR (acepta a quien NO es)")
    for u in np.arange(0.20, 0.71, 0.05):
        frr, far = float((gen < u).mean()), float((imp >= u).mean())
        print(f" {u:.2f}      {frr*100:6.2f} %                      {far*100:6.3f} %")
        if mejor is None or abs(frr - far) < abs(mejor[1] - mejor[2]):
            mejor = (u, frr, far)
    # Para asistencia es peor que firme alguien que no es (FAR) que repetir la foto (FRR)
    seguros = [u for u in np.arange(0.20, 0.71, 0.01) if float((imp >= u).mean()) <= 0.001]
    if seguros:
        u = float(seguros[0])
        print(f"\nUmbral más bajo con FAR <= 0.1 %: {u:.2f} (FRR {float((gen < u).mean())*100:.1f} %)")
        print(f"Sugerencia: MATCH_THRESHOLD={max(u, 0.40):.2f}")
    else:
        print("\nNingún umbral logra FAR <= 0.1 % con estos datos: revisa la calidad de las fotos.")


if __name__ == "__main__":
    main()
