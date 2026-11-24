#!/usr/bin/env python3
"""Desenha a planta base (v2, grade de células de 1,5 m) vista de cima.

Uso: python3 tools/desenhar_planta.py data/masmorra/layout.json saida.png [foto_para_comparar.jpg]
"""
import json
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFont

C = 20
M = 30
TOPO = 56
ROCHA = (122, 132, 140)
ROCHA_TRACO = (98, 107, 115)
CHAO = (248, 249, 247)
CHAO_GRADE = (222, 226, 224)
PAREDE = (34, 38, 44)
TINTA = (30, 36, 44)
SUAVE = (95, 104, 115)
GRADE_COR = (70, 76, 84)
PORTA = (139, 94, 52)
CRISTAL = (120, 170, 210)
ESTEIRA = (150, 140, 120)
ENTRADA = (179, 57, 43)
FONTE = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONTE_N = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def f(t, n=False):
    return ImageFont.truetype(FONTE_N if n else FONTE, t)


def main():
    sem_entradas = "--sem-entradas" in sys.argv
    if sem_entradas: sys.argv.remove("--sem-entradas")
    L = json.load(open(sys.argv[1]))
    saida = sys.argv[2]
    foto = sys.argv[3] if len(sys.argv) > 3 else None
    W, H = L["grade"]["largura"], L["grade"]["altura"]
    areas = {a["id"]: a for a in L["areas"]}
    cel = [[None] * W for _ in range(H)]
    for a in L["areas"]:
        for x0, y0, x1, y1 in a["retangulos"]:
            for y in range(y0, y1):
                for x in range(x0, x1):
                    cel[y][x] = a["id"]
    abertas = {}
    for p in L["aberturas"]:
        par, bordas = (p, "hv") if isinstance(p, list) else (p["entre"], p.get("bordas", "hv"))
        abertas[frozenset(par)] = bordas
    PX = lambda x, y: (M + x * C, TOPO + y * C)
    largura_img = M * 2 + W * C + 330
    img = Image.new("RGB", (largura_img, TOPO + H * C + 80), (236, 238, 236))
    d = ImageDraw.Draw(img)

    # Rocha hachurada
    x0, y0 = PX(0, 0); x1, y1 = PX(W, H)
    rocha = Image.new("RGB", (x1 - x0, y1 - y0), ROCHA); dr = ImageDraw.Draw(rocha)
    for k in range(-(y1 - y0), x1 - x0, 7):
        dr.line([(k, y1 - y0), (k + (y1 - y0), 0)], fill=ROCHA_TRACO, width=1)
    img.paste(rocha, (x0, y0))
    d.rectangle([x0, y0, x1, y1], outline=ROCHA_TRACO)

    # Chão
    for y in range(H):
        for x in range(W):
            if cel[y][x]:
                a, b = PX(x, y)
                d.rectangle([a, b, a + C, b + C], fill=CHAO, outline=CHAO_GRADE)

    # Detalhes: esteiras e cristais
    for est in L.get("esteiras", []):
        coluna = est["coluna"]
        if True:
            if True:
                a, b = PX(coluna, est["de_y"]); c_, e = PX(coluna + 1, est["ate_y"])
                d.rectangle([a + 3, b, c_ - 3, e], fill=ESTEIRA, outline=PAREDE)
                for yy in range(b, e, 8):
                    d.line([(a + 3, yy), (c_ - 3, yy)], fill=PAREDE)
    rnd = random.Random(7)
    if "33" in areas:
        for x0_, y0_, x1_, y1_ in areas["33"]["retangulos"]:
            for _ in range(26):
                cx = rnd.uniform(x0_ + 0.5, x1_ - 0.5); cy = rnd.uniform(y0_ + 1.2, y1_ - 0.4)
                a, b = PX(cx, cy); r = rnd.uniform(3, 6)
                d.polygon([(a, b - r * 1.6), (a + r, b), (a, b + r * 0.6), (a - r, b)], fill=CRISTAL, outline=(60, 100, 140))

    # Paredes
    def tipo(aid):
        return areas[aid]["tipo"] if aid else "rocha"

    def parede(p0, p1, natural):
        if not natural:
            d.line([p0, p1], fill=PAREDE, width=3)
            return
        # parede natural: linha ondulada
        n = 6
        pts = []
        for i in range(n + 1):
            t = i / n
            x = p0[0] + (p1[0] - p0[0]) * t; y = p0[1] + (p1[1] - p0[1]) * t
            j = (rnd.random() - 0.5) * 3
            if p0[0] == p1[0]: x += j
            else: y += j
            pts.append((x, y))
        d.line(pts, fill=PAREDE, width=3)

    def grade(p0, p1):
        d.line([p0, p1], fill=GRADE_COR, width=1)
        if p0[0] == p1[0]:
            for yy in range(int(p0[1]), int(p1[1]) + 1, 4):
                d.line([(p0[0] - 3, yy), (p0[0] + 3, yy)], fill=GRADE_COR, width=1)
        else:
            for xx in range(int(p0[0]), int(p1[0]) + 1, 4):
                d.line([(xx, p0[1] - 3), (xx, p0[1] + 3)], fill=GRADE_COR, width=1)

    for y in range(H + 1):
        for x in range(W + 1):
            for dx, dy in ((1, 0), (0, 1)):
                # borda à esquerda (vertical) ou em cima (horizontal) da célula (x, y)
                if dx == 1:      # borda vertical entre (x-1,y) e (x,y)
                    if y >= H: continue
                    a_ = cel[y][x - 1] if x - 1 >= 0 else None
                    b_ = cel[y][x] if x < W else None
                    p0, p1 = PX(x, y), PX(x, y + 1)
                else:            # borda horizontal entre (x,y-1) e (x,y)
                    if x >= W: continue
                    a_ = cel[y - 1][x] if y - 1 >= 0 else None
                    b_ = cel[y][x] if y < H else None
                    p0, p1 = PX(x, y), PX(x + 1, y)
                if a_ == b_ or (a_ is None and b_ is None):
                    continue
                if a_ and b_ and frozenset((a_, b_)) in abertas and ("v" if dx == 1 else "h") in abertas[frozenset((a_, b_))]:
                    continue
                if (tipo(a_) == "cela" and b_ and b_.startswith("19")) or (tipo(b_) == "cela" and a_ and a_.startswith("19")):
                    if a_ in ("19",) or b_ in ("19",) or (tipo(a_) == "cela" and tipo(b_) == "cela"):
                        if tipo(a_) == "cela" and tipo(b_) == "cela":
                            d.line([p0, p1], fill=PAREDE, width=3)
                        else:
                            grade(p0, p1)
                        continue
                natural = tipo(a_) in ("caverna",) or tipo(b_) in ("caverna",)
                parede(p0, p1, natural and (a_ is None or b_ is None))

    # Portas
    for pt in L["portas"]:
        x, y, n = pt["x"], pt["y"], pt["largura"]
        if pt["orient"] == "v":
            a, b = PX(x, y); c_, e = PX(x, y + n)
            d.line([(a, b), (c_, e)], fill=CHAO, width=5)
            if pt["tipo"] == "grade":
                grade((a, b), (c_, e))
            elif pt["tipo"] == "cela":
                grade((a, b), (c_, e)); d.rectangle([a - 2, b + 6, a + 2, e - 6], fill=GRADE_COR)
            else:
                partes = 2 if pt["tipo"] == "dupla" else 1
                for k in range(partes):
                    bb = b + (e - b) * k / partes; ee = b + (e - b) * (k + 1) / partes
                    d.rectangle([a - 3, bb + 3, a + 3, ee - 3], fill=PORTA, outline=PAREDE)
        else:
            a, b = PX(x, y); c_, e = PX(x + n, y)
            d.line([(a, b), (c_, e)], fill=CHAO, width=5)
            if pt["tipo"] == "grade":
                grade((a, b), (c_, e))
                mx = (a + c_) / 2
                d.rectangle([mx - 6, b - 3, mx + 6, b + 3], outline=PAREDE, fill=GRADE_COR)
            else:
                partes = 2 if pt["tipo"] == "dupla" else 1
                for k in range(partes):
                    aa = a + (c_ - a) * k / partes; cc = a + (c_ - a) * (k + 1) / partes
                    d.rectangle([aa + 3, b - 3, cc - 3, b + 3], fill=PORTA, outline=PAREDE)

    # Rótulos
    for aid, ar in areas.items():
        if ar["tipo"] == "cela" and aid.startswith("19c"):
            x0_, y0_, x1_, y1_ = ar["retangulos"][0]
            a, b = PX((x0_ + x1_) / 2, (y0_ + y1_) / 2)
            d.text((a, b), aid[3:], font=f(12, True), fill=SUAVE, anchor="mm")
            continue
        r = max(ar["retangulos"], key=lambda q: (q[2] - q[0]) * (q[3] - q[1]))
        a, b = PX((r[0] + r[2]) / 2, (r[1] + r[3]) / 2)
        if aid == "19": a, b = PX(1.5, 21.2)
        if aid == "19a": a, b = PX(14, 27)
        if aid == "19b": a, b = PX(16, 27)
        if aid in ("28", "29"): b -= 3 * C
        rotulo = aid if aid not in ("fenda34", "24p") else ""
        if rotulo:
            tam = 14 if len(rotulo) <= 2 else 12
            d.ellipse([a - 13, b - 13, a + 13, b + 13], fill=CHAO, outline=TINTA, width=2)
            d.text((a, b), rotulo, font=f(tam, True), fill=TINTA, anchor="mm")

    # IDs das portas e secretas sugeridas
    for pt in L["portas"]:
        if pt["tipo"] == "cela": continue
        n = pt["largura"]
        if pt["orient"] == "v": a, b = PX(pt["x"], pt["y"] + n / 2); pos = (a + 4, b - 9)
        else: a, b = PX(pt["x"] + n / 2, pt["y"]); pos = (a + 2, b - 13)
        d.text(pos, pt["id"], font=f(9, True), fill=PORTA, stroke_width=2, stroke_fill=CHAO)
    for sc in L.get("secretas_sugeridas", []):
        if "x" not in sc: continue
        a, b = PX(sc["x"], sc["y"] + 0.5)
        d.text((a, b), "S", font=f(13, True), fill=ENTRADA, anchor="mm", stroke_width=2, stroke_fill=CHAO)
        d.text((a + 4, b - 18), sc["id"], font=f(9, True), fill=ENTRADA, stroke_width=2, stroke_fill=CHAO)

    # Entradas possíveis
    for aid in ([] if sem_entradas else L.get("entradas_possiveis", {}).get("areas", [])):
        r = max(areas[aid]["retangulos"], key=lambda q: (q[2] - q[0]) * (q[3] - q[1]))
        cx, cy = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2
        bx, by = r[0] + 1, r[3] - 3
        if aid == "33": bx, by = r[2] - 3, r[1] + 1
        a, b = PX(bx, by); c_, e = PX(bx + 2, by + 2)
        for k in range(0, int(c_ - a), 5):
            d.line([(a + k, b), (a + k, e)], fill=(220, 150, 140), width=1)
        d.rectangle([a, b, c_, e], outline=ENTRADA, width=2)

    # Título, escala, legenda
    d.text((M, 14), L["nome"] + " — planta base (v%d)" % L.get("versao", 2), font=f(20, True), fill=TINTA)
    d.text((M, 38), "Desenho do Leonardo passado para a grade. 1 célula = 1,5 m (5 pés) = 1 personagem.", font=f(12), fill=SUAVE)
    yb = TOPO + H * C + 18
    for k in range(5):
        a, _ = PX(k * 2, 0)
        d.rectangle([a, yb, a + 2 * C, yb + 8], fill=TINTA if k % 2 == 0 else CHAO, outline=TINTA)
    d.text((M, yb + 14), "0        3 m       6 m       9 m      12 m     15 m", font=f(11), fill=SUAVE)
    lx = M + W * C + 24; ly = TOPO
    d.text((lx, ly), "Legenda", font=f(15, True), fill=TINTA); ly += 26
    itens = [("porta", "porta comum, com número (P01…); a aventura decide se emperra, tranca ou tem armadilha"),
             ("dupla", "porta dupla (20 → 19a)"), ("grade", "grade de cela com porta (2 → 1)"),
             ("cela", "porta de cela, fixa (celas 19cA–19cH)"), ("natural", "parede natural de caverna"),
             ("entrada", "possível entrada: escada 2×2 (24, 30, 33, 34, 21, 22)"),
             ("esteira", "esteira de pedra (mineração do 33)"), ("cristal", "cristal (gruta 33)")]
    for k, txt in itens:
        a, b = lx, ly + 8
        if k == "porta": d.rectangle([a, b - 3, a + 18, b + 3], fill=PORTA, outline=PAREDE)
        elif k == "dupla":
            d.rectangle([a, b - 3, a + 8, b + 3], fill=PORTA, outline=PAREDE); d.rectangle([a + 10, b - 3, a + 18, b + 3], fill=PORTA, outline=PAREDE)
        elif k in ("grade", "cela"): grade((a, b), (a + 18, b))
        elif k == "natural": parede((a, b), (a + 18, b), True)
        elif k == "entrada": d.rectangle([a, b - 8, a + 16, b + 8], outline=ENTRADA, width=2)
        elif k == "esteira": d.rectangle([a, b - 4, a + 18, b + 4], fill=ESTEIRA, outline=PAREDE)
        elif k == "cristal": d.polygon([(a + 9, b - 8), (a + 15, b), (a + 9, b + 3), (a + 3, b)], fill=CRISTAL, outline=(60, 100, 140))
        linhas = []
        atual = ""
        for w_ in txt.split():
            t2 = (atual + " " + w_).strip()
            if d.textlength(t2, font=f(11)) > 260: linhas.append(atual); atual = w_
            else: atual = t2
        linhas.append(atual)
        for i, ln in enumerate(linhas):
            d.text((lx + 28, ly + 2 + i * 14), ln, font=f(11), fill=TINTA)
        ly += 14 * len(linhas) + 10
    ly += 8
    d.text((lx, ly), "Observações", font=f(15, True), fill=TINTA); ly += 24
    for ln in ["19a e 19b: passagens que fazem parte do 19.", "Secretas sugeridas: S01 (início da fenda)",
               "e S02 (a própria P35); a aventura ativa.", "Variação: grupo capturado na cela 1,", "equipamento jogado na sala 4."]:
        d.text((lx, ly), ln, font=f(11), fill=SUAVE); ly += 15

    if foto:
        ft = Image.open(foto).convert("RGB")
        ft.thumbnail((img.width, 2000))
        out = Image.new("RGB", (img.width, img.height + ft.height + 10), (236, 238, 236))
        out.paste(ft, (0, 0)); out.paste(img, (0, ft.height + 10))
        img = out
    img.save(saida)
    print(f"salvo {saida} ({img.width}×{img.height})")


if __name__ == "__main__":
    main()
