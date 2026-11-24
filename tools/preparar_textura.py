#!/usr/bin/env python3
"""Torna uma textura repetível (sem emenda) e gera o mapa de normais a partir da luminosidade.

Uso: python3 tools/preparar_textura.py entrada.png saida_cor.png saida_normal.png [forca_relevo] [tamanho]
"""
import sys

import numpy as np
from PIL import Image, ImageFilter


def main():
    src, out_cor, out_normal = sys.argv[1:4]
    forca = float(sys.argv[4]) if len(sys.argv) > 4 else 4.0
    tam = int(sys.argv[5]) if len(sys.argv) > 5 else 1024
    im = Image.open(src).convert("RGB").resize((tam, tam), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32)
    # Sem emenda: mistura com a cópia deslocada pela metade; no centro fica a original, nas bordas a deslocada
    rol = np.roll(np.roll(a, tam // 2, 0), tam // 2, 1)
    y, x = np.mgrid[0:tam, 0:tam] / (tam - 1)
    w = np.minimum(np.minimum(x, 1 - x), np.minimum(y, 1 - y)) * 2      # 0 na borda, 1 no centro
    w = np.clip(w * 2.2, 0, 1)[..., None]
    cor = a * w + rol * (1 - w)
    Image.fromarray(cor.clip(0, 255).astype(np.uint8)).save(out_cor)
    # Normais: altura = luminosidade suavizada (juntas escuras = fundas)
    lum = Image.fromarray(cor.clip(0, 255).astype(np.uint8)).convert("L").filter(ImageFilter.GaussianBlur(1.5))
    h = np.asarray(lum).astype(np.float32) / 255
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * forca
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * forca
    n = np.dstack([-dx, -dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(out_normal)
    print("ok", out_cor, out_normal)


if __name__ == "__main__":
    main()
