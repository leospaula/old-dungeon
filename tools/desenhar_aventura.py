#!/usr/bin/env python3
"""Desenha o mapa de uma aventura: a planta base com o conteúdo da aventura por cima.

Uso: python3 tools/desenhar_aventura.py data/aventuras/<id>/aventura.json saida.png
"""
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from planta import Planta  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
C, M, TOPO = 20, 30, 56                 # mesma geometria de desenhar_planta.py
F = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FN = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FC = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf"
TINTA, SUAVE = (30, 36, 44), (95, 104, 115)
VERMELHO, VERDE, OURO, ROXO, AZUL = (190, 50, 40), (40, 120, 70), (200, 145, 20), (115, 60, 165), (40, 100, 170)
COR_CAT = {"estrutura": (150, 150, 150), "mobilia": (176, 130, 84), "deposito": (150, 105, 60), "religioso": (190, 180, 210),
           "prisao": (110, 110, 120), "mineracao": (140, 120, 95), "caverna": (130, 140, 110), "luz": (235, 170, 60),
           "perigo": (160, 80, 160), "decoracao": (170, 160, 130)}
ESTADO = {"trancada": ("T", OURO), "emperrada": ("E", (150, 100, 40)), "aberta": ("A", VERDE), "quebrada": ("X", SUAVE),
          "secreta": ("S", VERMELHO), "fechada": ("F", SUAVE)}


def f(t, n=False, c=False):
    return ImageFont.truetype(FN if n else (FC if c else F), t)


def main():
    av = json.load(open(sys.argv[1])); saida = sys.argv[2]
    pl = Planta(os.path.join(RAIZ, "data/masmorra/layout.json"))
    props = json.load(open(os.path.join(RAIZ, "data/catalogos/props.json")))["props"]
    monstros = json.load(open(os.path.join(RAIZ, "data/regras/monstros.json")))
    tmp = tempfile.mktemp(suffix=".png")
    subprocess.run([sys.executable, "-I", os.path.join(RAIZ, "tools/desenhar_planta.py"),
                    os.path.join(RAIZ, "data/masmorra/layout.json"), tmp, "--sem-entradas"], check=True, capture_output=True)
    base = Image.open(tmp).convert("RGB"); os.remove(tmp)
    largura_mapa = M + pl.W * C + 8
    img = Image.new("RGB", (largura_mapa + 470, max(base.height, 1100)), (236, 238, 236))
    img.paste(base.crop((0, 0, largura_mapa, base.height)), (0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, largura_mapa, 52], fill=(236, 238, 236))
    d.text((M, 14), av["titulo"], font=f(20, True), fill=TINTA)
    d.text((M, 38), f"Aventura sobre a planta {av['planta']} · níveis {av['nivel'][0]}–{av['nivel'][1]}", font=f(12), fill=SUAVE)
    PX = lambda x, y: (M + x * C, TOPO + y * C)
    cel = lambda area, pos: pl.coord_para_celula(area, pos)

    def retangulo(area, pos, w, h, cor, rotulo=None):
        x, y = cel(area, pos); a, b = PX(x, y); c_, e = PX(x + w, y + h)
        d.rectangle([a + 2, b + 2, c_ - 2, e - 2], fill=cor, outline=TINTA, width=1)
        if rotulo: d.text(((a + c_) / 2, (b + e) / 2), rotulo, font=f(8, True), fill="white", anchor="mm", stroke_width=1, stroke_fill=TINTA)

    def ponto(area, pos, cor, txt, forma="circulo"):
        x, y = cel(area, pos); a, b = PX(x + 0.5, y + 0.5); r = 8
        if forma == "losango": d.polygon([(a, b - r), (a + r, b), (a, b + r), (a - r, b)], fill=cor, outline=TINTA)
        elif forma == "triangulo": d.polygon([(a, b - r), (a + r, b + r - 2), (a - r, b + r - 2)], fill=cor, outline=TINTA)
        else: d.ellipse([a - r, b - r, a + r, b + r], fill=cor, outline=TINTA)
        d.text((a, b + (2 if forma == "triangulo" else 0)), txt, font=f(9, True), fill="white", anchor="mm")

    # Portas e secretas
    for pid, est in av.get("portas", {}).items():
        p = pl.portas[pid]; n = p["largura"]
        a, b = PX(p["x"] + (0 if p["orient"] == "v" else n / 2), p["y"] + (n / 2 if p["orient"] == "v" else 0))
        letra, cor = ESTADO.get(est.get("estado", "fechada"), ("?", SUAVE))
        d.ellipse([a - 7, b - 7, a + 7, b + 7], fill=cor, outline="white", width=2)
        d.text((a, b), letra, font=f(9, True), fill="white", anchor="mm")
        if est.get("armadilha"):
            d.polygon([(a + 9, b - 14), (a + 16, b - 2), (a + 2, b - 2)], fill=ROXO, outline=TINTA)
    for sid in av.get("secretas", []):
        s = pl.secretas[sid]
        if "x" in s:
            a, b = PX(s["x"], s["y"] + 0.5)
            d.ellipse([a - 9, b - 9, a + 9, b + 9], outline=VERMELHO, width=3)

    # Conteúdo das áreas
    for area, c in av["areas"].items():
        for pr in c.get("props", []):
            cat = props[pr["tipo"]]
            w, h = cat["tamanho"]
            if pr.get("giro", 0) in (90, 270): w, h = h, w
            if pr["tipo"] == "escada-entrada":
                x, y = cel(area, pr["pos"]); a, b = PX(x, y); c_, e = PX(x + w, y + h)
                d.rectangle([a + 1, b + 1, c_ - 1, e - 1], fill=(120, 80, 40), outline=TINTA)
                for k in range(int(b) + 4, int(e), 6): d.line([(a + 3, k), (c_ - 3, k)], fill=(220, 190, 140), width=2)
                continue
            retangulo(area, pr["pos"], w, h, COR_CAT.get(cat["categoria"], (160, 160, 160)), cat["nome"][:2].upper())
        for t in c.get("tesouros", []):
            if "pos" in t: ponto(area, t["pos"], OURO, "$", "losango")
        for a_ in c.get("armadilhas", []):
            if "pos" in a_: ponto(area, a_["pos"], ROXO, "!", "triangulo")
        for m in c.get("monstros", []):
            sigla = (m.get("nome") or monstros.get(m["tipo"], {}).get("nome", m["tipo"]))[:1].upper()
            for p_ in (m.get("posicoes") or ([m["pos"]] if "pos" in m else [])):
                ponto(area, p_, VERMELHO, sigla)
        for p_ in c.get("pdms", []):
            ponto(area, p_["pos"], VERDE, "P")

    # Início
    ini = av["inicio"]
    if ini["tipo"] == "escada":
        x, y = cel(ini["area"], ini["pos"]); a, b = PX(x, y); c_, e = PX(x + 2, y + 2)
        d.rectangle([a + 1, b + 1, c_ - 1, e - 1], fill=(120, 80, 40), outline=TINTA)
        for k in range(int(b) + 4, int(e), 6): d.line([(a + 3, k), (c_ - 3, k)], fill=(220, 190, 140), width=2)
    x, y = cel(ini["area"], ini["pos"]); a, b = PX(x + 0.5, y + 0.5)
    d.polygon([(a - 2, b - 16), (a + 14, b - 11), (a - 2, b - 6)], fill=VERDE); d.line([(a - 2, b - 16), (a - 2, b + 6)], fill=TINTA, width=2)
    d.text((a + 4, b + 2), "INÍCIO", font=f(9, True), fill=VERDE, stroke_width=2, stroke_fill="white")
    if ini.get("equipamento_em"):
        q = ini["equipamento_em"]; ponto(q["area"], q["pos"], AZUL, "Eq", "losango")

    # Painel
    px0 = largura_mapa + 10; y = 18
    d.text((px0, y), "Legenda da aventura", font=f(15, True), fill=TINTA); y += 26
    leg = [(VERMELHO, "monstro (inicial)", "c"), (VERDE, "PdM", "c"), (OURO, "tesouro", "l"), (ROXO, "armadilha", "t"),
           (AZUL, "equipamento do grupo", "l"), ((120, 80, 40), "escada de entrada (2×2)", "r"), (VERMELHO, "secreta ativa", "o")]
    for cor, txt, forma in leg:
        a, b = px0 + 8, y + 7
        if forma == "c": d.ellipse([a - 7, b - 7, a + 7, b + 7], fill=cor, outline=TINTA)
        elif forma == "l": d.polygon([(a, b - 7), (a + 7, b), (a, b + 7), (a - 7, b)], fill=cor, outline=TINTA)
        elif forma == "t": d.polygon([(a, b - 7), (a + 7, b + 6), (a - 7, b + 6)], fill=cor, outline=TINTA)
        elif forma == "r": d.rectangle([a - 7, b - 7, a + 7, b + 7], fill=cor, outline=TINTA)
        else: d.ellipse([a - 7, b - 7, a + 7, b + 7], outline=cor, width=3)
        d.text((px0 + 22, b), txt, font=f(11), fill=TINTA, anchor="lm"); y += 19
    d.text((px0, y + 2), "Portas: F fechada · E emperrada · T trancada · A aberta · X quebrada · S secreta", font=f(10, c=True), fill=SUAVE); y += 18
    d.text((px0, y), "Props: retângulo com as 2 primeiras letras do nome", font=f(10, c=True), fill=SUAVE); y += 24

    def linha(txt, fonte, cor, recuo=0):
        nonlocal y
        palavras, atual = txt.split(), ""
        for w_ in palavras:
            t2 = (atual + " " + w_).strip()
            if d.textlength(t2, font=fonte) > 440 - recuo: d.text((px0 + recuo, y), atual, font=fonte, fill=cor); y += 14; atual = w_
            else: atual = t2
        if atual: d.text((px0 + recuo, y), atual, font=fonte, fill=cor); y += 14

    d.text((px0, y), "Início", font=f(13, True), fill=TINTA); y += 18
    txt = f"{ini['tipo']} em {ini['area']} {ini['pos']}"
    if ini.get("sem_equipamento"): txt += " · sem equipamento"
    if ini.get("equipamento_em"): txt += f" · equipamento em {ini['equipamento_em']['area']} {ini['equipamento_em']['pos']}"
    linha(txt, f(11, c=True), SUAVE); y += 4
    if av.get("portas"):
        d.text((px0, y), "Portas", font=f(13, True), fill=TINTA); y += 18
        for pid, est in av["portas"].items():
            p = pl.portas[pid]
            extra = (f", abre com {est['abre_com']}" if est.get("abre_com") else "") + (f", armadilha: {est['armadilha']['tipo']}" if est.get("armadilha") else "")
            linha(f"{pid} ({p['de']}↔{p['para']}): {est.get('estado', '')}{extra}", f(11, c=True), SUAVE)
        y += 4
    d.text((px0, y), "Áreas", font=f(13, True), fill=TINTA); y += 18
    for area, c in av["areas"].items():
        partes = []
        for m in c.get("monstros", []):
            nome = m.get("nome") or monstros.get(m["tipo"], {}).get("nome", m["tipo"]).lower()
            onde = ", ".join(m.get("posicoes") or ([m["pos"]] if "pos" in m else []))
            partes.append(f"{m.get('qtd', 1)}× {nome} ({onde}{', ' + m['estado'] if m.get('estado') else ''})")
        for p_ in c.get("pdms", []): partes.append(f"PdM {av['pdms'][p_['id']]['nome']} ({p_['pos']})")
        for pr in c.get("props", []): partes.append(f"{props[pr['tipo']]['nome'].lower()} {pr['pos']}")
        for t in c.get("tesouros", []):
            moedas = ", ".join(f"{t[k]} {k}" for k in ("po", "pp", "pc") if t.get(k))
            partes.append(f"tesouro {t.get('pos', '')}: {moedas}{' (escondido)' if t.get('escondido') else ''}")
        for a_ in c.get("armadilhas", []): partes.append(f"armadilha {a_['tipo']} {a_.get('pos', '')}")
        d.text((px0, y), f"{area} — {pl.areas[area]['nome']}", font=f(11, True), fill=TINTA); y += 15
        linha("; ".join(partes) or "só texto", f(10, c=True), SUAVE, 10); y += 3
    if av.get("objetivos"):
        y += 4; d.text((px0, y), "Objetivos", font=f(13, True), fill=TINTA); y += 18
        for o in av["objetivos"]:
            linha(f"{'★ ' if o.get('final') else '• '}{o['descricao']} ({o.get('xp', 0)} XP)", f(11, c=True), SUAVE)
    img = img.crop((0, 0, img.width, max(base.height, y + 20)))
    img.save(saida)
    print(f"salvo {saida} ({img.width}×{img.height})")


if __name__ == "__main__":
    main()
