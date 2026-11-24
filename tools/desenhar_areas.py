#!/usr/bin/env python3
"""Fichas de coordenadas: uma imagem por área com a grade local (letras = colunas, números = linhas),
as portas (P01…) e as secretas sugeridas (S01…). Também gera um índice com todas as fichas.

Uso: python3 tools/desenhar_areas.py data/masmorra/layout.json arte/mapas/areas
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from planta import LETRAS, Planta  # noqa: E402

C = 40
MARGEM = 1  # células de contexto ao redor
F = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FN = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
CHAO, OUTRA, ROCHA, TINTA, SUAVE, PORTA, SECRETA = (250, 248, 240), (214, 214, 208), (120, 128, 136), (30, 36, 44), (100, 108, 118), (139, 94, 52), (179, 57, 43)


def ficha(pl, area, saida):
    x0, y0, x1, y1 = pl.caixa(area)
    gx0, gy0, gx1, gy1 = x0 - MARGEM, y0 - MARGEM, x1 + MARGEM, y1 + MARGEM
    topo, esq = 70, 40
    W, H = esq + (gx1 - gx0) * C + 20, topo + (gy1 - gy0) * C + 40
    img = Image.new("RGB", (W, H), (240, 240, 236)); d = ImageDraw.Draw(img)
    P = lambda x, y: (esq + (x - gx0) * C, topo + (y - gy0) * C)
    nome = pl.areas[area]["nome"]
    d.text((12, 10), f"{area} — {nome}", font=ImageFont.truetype(FN, 20), fill=TINTA)
    d.text((12, 38), "Coordenadas locais: letra = coluna, número = linha (ex.: C3).", font=ImageFont.truetype(F, 12), fill=SUAVE)
    fonte = ImageFont.truetype(F, 12); fonte_n = ImageFont.truetype(FN, 13)
    for y in range(gy0, gy1):
        for x in range(gx0, gx1):
            a, b = P(x, y)
            dentro = 0 <= x < pl.W and 0 <= y < pl.H
            v = pl.cel[y][x] if dentro else None
            cor = CHAO if v == area else (OUTRA if v else ROCHA)
            d.rectangle([a, b, a + C, b + C], fill=cor, outline=(200, 200, 194) if v else (110, 118, 126))
            if v == area:
                d.text((a + C / 2, b + C / 2), pl.celula_para_coord(area, x, y), font=fonte, fill=SUAVE, anchor="mm")
            elif v and v != area and (x in (gx0, gx1 - 1) or y in (gy0, gy1 - 1) or True):
                pass
    # Paredes da área
    for (x, y) in pl.celulas(area):
        for dx, dy, borda in ((-1, 0, "e"), (1, 0, "d"), (0, -1, "c"), (0, 1, "b")):
            nx, ny = x + dx, y + dy
            viz = pl.cel[ny][nx] if 0 <= nx < pl.W and 0 <= ny < pl.H else None
            if viz == area: continue
            a, b = P(x, y)
            seg = {"e": [(a, b), (a, b + C)], "d": [(a + C, b), (a + C, b + C)], "c": [(a, b), (a + C, b)], "b": [(a, b + C), (a + C, b + C)]}[borda]
            d.line(seg, fill=TINTA, width=3)
    # Rótulos de colunas e linhas (só da caixa da área)
    for i, x in enumerate(range(x0, x1)):
        a, _ = P(x, gy0)
        d.text((a + C / 2, topo - 12), LETRAS[i], font=fonte_n, fill=TINTA, anchor="mm")
    for j, y in enumerate(range(y0, y1)):
        _, b = P(gx0, y)
        d.text((esq - 14, b + C / 2), str(j + 1), font=fonte_n, fill=TINTA, anchor="mm")
    # Vizinhos (nome no centro da parte visível)
    vistos = {}
    for y in range(max(gy0, 0), min(gy1, pl.H)):
        for x in range(max(gx0, 0), min(gx1, pl.W)):
            v = pl.cel[y][x]
            if v and v != area: vistos.setdefault(v, []).append((x, y))
    for v, cs in vistos.items():
        mx = sum(c[0] for c in cs) / len(cs); my = sum(c[1] for c in cs) / len(cs)
        a, b = P(mx + 0.5, my + 0.5)
        d.text((a, b), v, font=fonte_n, fill=SUAVE, anchor="mm", stroke_width=3, stroke_fill=OUTRA)
    # Portas e secretas
    itens = [(p["id"], p, PORTA) for p in pl.portas.values() if area in (p["de"], p["para"])]
    itens += [(s["id"], s, SECRETA) for s in pl.secretas.values() if "x" in s and area in (s["de"], s["para"])]
    for pid, p, cor in itens:
        n = p.get("largura", 1)
        if p["orient"] == "v":
            a, b = P(p["x"], p["y"]); _, e = P(p["x"], p["y"] + n)
            d.rectangle([a - 4, b + 3, a + 4, e - 3], fill=cor, outline=TINTA)
            dentro_esq = 0 <= p["x"] - 1 < pl.W and pl.cel[p["y"]][p["x"] - 1] == area
            d.text((a + 7 if dentro_esq else a - 7, (b + e) / 2), pid, font=fonte_n, fill=cor, anchor="lm" if dentro_esq else "rm", stroke_width=3, stroke_fill=(255, 255, 255))
        else:
            a, b = P(p["x"], p["y"]); c_, _ = P(p["x"] + n, p["y"])
            d.rectangle([a + 3, b - 4, c_ - 3, b + 4], fill=cor, outline=TINTA)
            dentro_cima = 0 <= p["y"] - 1 < pl.H and pl.cel[p["y"] - 1][p["x"]] == area
            d.text(((a + c_) / 2, b + 7 if dentro_cima else b - 7), pid, font=fonte_n, fill=cor, anchor="mt" if dentro_cima else "mb", stroke_width=3, stroke_fill=(255, 255, 255))
    img.save(saida)
    return img


def main():
    pl = Planta(sys.argv[1]); pasta = sys.argv[2]
    os.makedirs(pasta, exist_ok=True)
    ordem = sorted(pl.areas, key=lambda a: (int("".join(ch for ch in a if ch.isdigit()) or 0), a))
    for a in ordem:
        ficha(pl, a, os.path.join(pasta, f"area-{a}.png"))
    print(f"{len(ordem)} fichas em {pasta}")


if __name__ == "__main__":
    main()
