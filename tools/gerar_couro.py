#!/usr/bin/env python3
"""Gera a textura de couro envelhecido (cor + normal), sem emenda, para itens desenhados pelo jogo
(chicote, funda). Mesma textura no jogo e no Ateliê.

Couro curtido e gasto: marrom escuro com manchas mais claras onde gastou, poros finos, vincos
irregulares escuros e um leve brilho nas partes mais altas.

Uso: python3 tools/gerar_couro.py  →  arte/texturas/couro_cor.png, arte/texturas/couro_normal.png
"""
import os
import numpy as np
from PIL import Image

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N = 256
rng = np.random.default_rng(7)


def ruido(freq, oitavas=4):
    """Ruído de valor periódico (sem emenda) em N×N."""
    out = np.zeros((N, N)); amp = 1.0; tot = 0.0
    for o in range(oitavas):
        f = freq * (2 ** o)
        g = rng.random((f, f))
        x = np.linspace(0, f, N, endpoint=False)
        i0 = np.floor(x).astype(int); t = x - i0; t = t * t * (3 - 2 * t); i1 = (i0 + 1) % f
        a = g[np.ix_(i0, i0)] * (1 - t)[None, :] + g[np.ix_(i0, i1)] * t[None, :]
        b = g[np.ix_(i1, i0)] * (1 - t)[None, :] + g[np.ix_(i1, i1)] * t[None, :]
        out += amp * (a * (1 - t)[:, None] + b * t[:, None]); tot += amp; amp *= 0.5
    return out / tot


manchas = ruido(3, 4)                      # gasto: manchas grandes mais claras
poros = ruido(48, 2)                       # textura fina do couro
veios = np.abs(ruido(6, 4) - 0.5)          # vincos: linhas onde o ruído cruza o meio
vinco = np.clip(1 - veios / 0.035, 0, 1) ** 2
gasto = np.clip((manchas - 0.45) * 2.2, 0, 1)

base = np.array([0.30, 0.17, 0.09]); claro = np.array([0.50, 0.33, 0.19]); escuro = np.array([0.13, 0.07, 0.04])
cor = base[None, None, :] * (1 - gasto[..., None]) + claro[None, None, :] * gasto[..., None]
cor *= (0.88 + 0.24 * poros)[..., None]
cor = cor * (1 - 0.65 * vinco[..., None]) + escuro[None, None, :] * 0.65 * vinco[..., None]
Image.fromarray((np.clip(cor, 0, 1) * 255).astype(np.uint8)).save(os.path.join(RAIZ, "arte/texturas/couro_cor.png"))

# Normal: altura = poros + manchas - vincos (vinco afunda).
h = 0.35 * poros + 0.4 * manchas - 0.9 * vinco
dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 2.5
dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 2.5
nz = np.ones_like(h); l = np.sqrt(dx * dx + dy * dy + nz)
nrm = np.stack([-dx / l, -dy / l, nz / l], -1) * 0.5 + 0.5
Image.fromarray((nrm * 255).astype(np.uint8)).save(os.path.join(RAIZ, "arte/texturas/couro_normal.png"))
print("ok: arte/texturas/couro_cor.png, couro_normal.png")
