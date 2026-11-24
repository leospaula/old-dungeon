#!/usr/bin/env python3
"""Recorta peças desenhadas sobre fundo liso: tira o fundo (alfa por distância de cor) e salva
cada objeto separado (componentes conectados), do maior para o menor.

Uso: python3 tools/recortar_pecas.py entrada.png pasta_saida prefixo [area_minima_px]
"""
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def main():
    src, pasta, prefixo = sys.argv[1], sys.argv[2], sys.argv[3]
    area_min = int(sys.argv[4]) if len(sys.argv) > 4 else 4000
    os.makedirs(pasta, exist_ok=True)
    im = Image.open(src).convert("RGB")
    a = np.asarray(im).astype(np.float32)
    cantos = np.concatenate([a[:8, :8].reshape(-1, 3), a[:8, -8:].reshape(-1, 3), a[-8:, :8].reshape(-1, 3), a[-8:, -8:].reshape(-1, 3)])
    fundo = np.median(cantos, axis=0)
    dist = np.linalg.norm(a - fundo, axis=2)
    # Fundo = pixels parecidos com o fundo E ligados à borda da imagem (o miolo claro das peças fica opaco)
    parecido = Image.fromarray(((dist < 32) * 255).astype(np.uint8), "L").copy()
    W, H = parecido.size
    sementes = [(x, 0) for x in range(0, W, 40)] + [(x, H - 1) for x in range(0, W, 40)] + \
               [(0, y) for y in range(0, H, 40)] + [(W - 1, y) for y in range(0, H, 40)]
    for p_ in sementes:
        if parecido.getpixel(p_) == 255:
            ImageDraw.floodfill(parecido, p_, 128)
    fundo_mask = np.asarray(parecido) == 128
    alfa = (~fundo_mask).astype(np.float32)
    alfa = np.asarray(Image.fromarray((alfa * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32) / 255
    mascara = alfa > 0.5
    # componentes em resolução reduzida (rápido), depois volta à resolução cheia
    f = 4
    peq = mascara[::f, ::f]
    rot = np.zeros(peq.shape, np.int32); n = 0; caixas = []
    for y0, x0 in zip(*np.nonzero(peq)):
        if rot[y0, x0]: continue
        n += 1; fila = deque([(y0, x0)]); rot[y0, x0] = n; ys, xs = [y0], [x0]
        while fila:
            y, x = fila.popleft()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < peq.shape[0] and 0 <= xx < peq.shape[1] and peq[yy, xx] and not rot[yy, xx]:
                    rot[yy, xx] = n; fila.append((yy, xx)); ys.append(yy); xs.append(xx)
        caixas.append((len(ys) * f * f, min(xs) * f, min(ys) * f, (max(xs) + 1) * f, (max(ys) + 1) * f))
    caixas = sorted([c for c in caixas if c[0] >= area_min], key=lambda c: (c[2] // 120, c[1]))  # leitura: linha, depois coluna
    rgba = np.dstack([np.asarray(im), (alfa * 255).astype(np.uint8)])
    out = Image.fromarray(rgba, "RGBA")
    for i, (_, x0, y0, x1, y1) in enumerate(caixas, 1):
        m = 6
        caixa = (max(0, x0 - m), max(0, y0 - m), min(im.width, x1 + m), min(im.height, y1 + m))
        out.crop(caixa).save(os.path.join(pasta, f"{prefixo}-{i:02d}.png"))
        print(f"{prefixo}-{i:02d}.png {caixa[2]-caixa[0]}x{caixa[3]-caixa[1]}")


if __name__ == "__main__":
    main()
