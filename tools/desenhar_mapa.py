#!/usr/bin/env python3
"""Desenha a masmorra vista de cima (estilo papel quadriculado de módulo clássico).

Uso:
    python3 tools/desenhar_mapa.py data/masmorra/layout.json saida.png
    python3 tools/desenhar_mapa.py data/masmorra/layout.json saida.png data/aventuras/monte-corvo-01/aventura.json

Sem aventura: só a planta padrão (salas, corredores, portas).
Com aventura: marca monstros, armadilhas, tesouros e segredos, com a legenda das salas ao lado.
"""
import json
import sys

from PIL import Image, ImageDraw, ImageFont

C = 22                      # pixels por quadrado de 3 m
M = 28                      # margem
LADO = 560                  # largura do painel de legenda
ROCHA = (86, 124, 156)
ROCHA_GRADE = (104, 141, 171)
CHAO = (247, 250, 252)
CHAO_GRADE = (205, 221, 232)
PAREDE = (24, 42, 64)
TINTA = (24, 39, 58)
SUAVE = (82, 99, 122)
VERMELHO = (179, 57, 43)
OURO = (201, 146, 24)
ROXO = (112, 64, 160)
VERDE = (47, 107, 79)
ABISMO = (20, 26, 34)
FONTE = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONTE_N = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONTE_C = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf"


def f(tam, negrito=False, cond=False):
    return ImageFont.truetype(FONTE_N if negrito else (FONTE_C if cond else FONTE), tam)


def px(x, y):
    return M + x * C, M + 40 + y * C


def ret(s):
    x0, y0 = px(s["x"], s["y"])
    return x0, y0, x0 + s["w"] * C, y0 + s["h"] * C


def corredor(a, b):
    """Corredor reto de 1 quadrado entre duas salas que se sobrepõem em x ou em y."""
    ax0, ax1, ay0, ay1 = a["x"], a["x"] + a["w"], a["y"], a["y"] + a["h"]
    bx0, bx1, by0, by1 = b["x"], b["x"] + b["w"], b["y"], b["y"] + b["h"]
    ox0, ox1 = max(ax0, bx0), min(ax1, bx1)
    oy0, oy1 = max(ay0, by0), min(ay1, by1)
    if ox1 - ox0 >= 1:          # vertical
        cx = (ox0 + ox1) // 2 if (ox1 - ox0) % 2 == 0 else ox0 + (ox1 - ox0) // 2
        cx = min(max(cx, ox0), ox1 - 1)
        y0, y1 = (ay1, by0) if ay1 <= by0 else (by1, ay0)
        return ("v", cx, y0, y1)
    if oy1 - oy0 >= 1:          # horizontal
        cy = min(max((oy0 + oy1) // 2, oy0), oy1 - 1)
        x0, x1 = (ax1, bx0) if ax1 <= bx0 else (bx1, ax0)
        return ("h", cy, x0, x1)
    raise ValueError(f"salas {a['id']} e {b['id']} não se alinham")


def grade_em(d, caixa, cor):
    x0, y0, x1, y1 = caixa
    for gx in range(x0, x1 + 1, C):
        d.line([(gx, y0), (gx, y1)], fill=cor)
    for gy in range(y0, y1 + 1, C):
        d.line([(x0, gy), (x1, gy)], fill=cor)


def desenhar_sala(d, s):
    x0, y0, x1, y1 = ret(s)
    forma = s.get("forma", "salao")
    if forma == "redonda":
        d.ellipse([x0, y0, x1, y1], fill=CHAO, outline=PAREDE, width=3)
    elif forma == "caverna":
        d.rounded_rectangle([x0, y0, x1, y1], radius=C * 1.2, fill=CHAO, outline=PAREDE, width=3)
    else:
        d.rectangle([x0, y0, x1, y1], fill=CHAO, outline=PAREDE, width=3)


def detalhes_sala(d, s):
    x0, y0, x1, y1 = ret(s)
    if s.get("forma") == "fenda":
        # Abismo no meio, ponte de tábuas atravessando de oeste a leste.
        cx = (x0 + x1) // 2
        d.polygon([(cx - C, y0 + 2), (cx + C * 0.6, y0 + 2), (cx + C * 0.9, y1 - 2), (cx - C * 0.7, y1 - 2)], fill=ABISMO)
        my = (y0 + y1) // 2
        for k in range(-int(C * 1.3), int(C * 1.3), 6):
            d.line([(cx + k, my - C // 3), (cx + k, my + C // 3)], fill=(150, 110, 60), width=3)
        d.line([(cx - C * 1.4, my - C // 3), (cx + C * 1.4, my - C // 3)], fill=(120, 85, 45), width=1)
        d.line([(cx - C * 1.4, my + C // 3), (cx + C * 1.4, my + C // 3)], fill=(120, 85, 45), width=1)
    if s.get("forma") == "redonda":
        cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
        d.ellipse([cx - C * 0.7, cy - C * 0.7, cx + C * 0.7, cy + C * 0.7], fill=ABISMO, outline=PAREDE, width=2)


def porta(d, con, cor_tipo, rotulo_fonte):
    tipo = cor_tipo["tipo"]
    if tipo in ("passagem", "ponte"):
        return
    eixo, a, b0, b1 = con
    meio = (b0 + b1) / 2
    if eixo == "v":
        cx, cy = px(a + 0.5, meio)
        horizontal = True
    else:
        cx, cy = px(meio, a + 0.5)
        horizontal = False
    w, h = (C * 0.9, C * 0.32) if horizontal else (C * 0.32, C * 0.9)
    if tipo == "porta_secreta":
        # Parede contínua com um S por cima.
        if horizontal:
            d.rectangle([cx - C / 2, cy - 2, cx + C / 2, cy + 2], fill=PAREDE)
        else:
            d.rectangle([cx - 2, cy - C / 2, cx + 2, cy + C / 2], fill=PAREDE)
        d.text((cx, cy), "S", font=f(15, True), fill=VERMELHO, anchor="mm", stroke_width=3, stroke_fill=CHAO)
        return
    fill = PAREDE if not cor_tipo.get("emperrada") else CHAO
    d.rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], fill=fill, outline=PAREDE, width=2)
    if cor_tipo.get("trancada"):
        d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=OURO, outline=PAREDE)


def marcadores(d, s, cont):
    """Ícones de conteúdo no canto da sala: monstros, armadilha, tesouro, segredo."""
    x0, y0, x1, y1 = ret(s)
    itens = []
    mons = [m for m in cont.get("monstros", []) if m.get("tipo") not in ("nao_combatente",)]
    if mons:
        n = sum(m.get("qtd", 1) for m in mons)
        itens.append(("mon", str(n)))
    if cont.get("armadilhas") or cont.get("teste") or cont.get("maldicao"):
        itens.append(("arm", "!"))
    if cont.get("tesouro"):
        itens.append(("tes", "$"))
    if cont.get("segredos") or cont.get("pistas") or (cont.get("tesouro") or {}).get("procurar"):
        itens.append(("seg", "?"))
    if cont.get("reacao"):
        itens.append(("fal", "…"))
    cores = {"mon": VERMELHO, "arm": ROXO, "tes": OURO, "seg": VERDE, "fal": SUAVE}
    r = 8
    x, y = x0 + 6 + r, y1 - 6 - r
    for tipo, txt in itens:
        if tipo == "tes":
            d.polygon([(x, y - r), (x + r, y), (x, y + r), (x - r, y)], fill=cores[tipo], outline=PAREDE)
        elif tipo == "arm":
            d.polygon([(x, y - r), (x + r, y + r - 1), (x - r, y + r - 1)], fill=cores[tipo], outline=PAREDE)
        else:
            d.ellipse([x - r, y - r, x + r, y + r], fill=cores[tipo], outline=PAREDE)
        d.text((x, y + (2 if tipo == "arm" else 0)), txt, font=f(10, True), fill="white", anchor="mm")
        x += 2 * r + 4


def resumo_sala(cont, monstros):
    partes = []
    mons = cont.get("monstros", [])
    if mons:
        nomes = []
        for m in mons:
            if m.get("tipo") == "pdm":
                classe = {"ladrao": "ladra", "guerreiro": "guerreira", "clerigo": "clériga", "mago": "maga"}.get(m.get("classe", ""), m.get("classe", ""))
                nomes.append(f"{m.get('nome', 'PdM')} ({classe} nv {m.get('nivel', '?')})")
            elif m.get("nome"):
                tipo = monstros.get(m["tipo"], {}).get("nome", m["tipo"]).lower()
                nomes.append(f"{m['nome']} ({tipo})")
            else:
                nome = monstros.get(m["tipo"], {}).get("nome", m["tipo"])
                nomes.append(f"{m.get('qtd', 1)} {nome.lower()}")
        partes.append(", ".join(nomes))
    for a in cont.get("armadilhas", []):
        partes.append(f"armadilha: {a['tipo']} ({a.get('chance', '')})")
    if cont.get("teste"):
        partes.append(f"teste de {cont['teste']['atributo'].upper()}")
    t = cont.get("tesouro") or {}
    moedas = [f"{t[k]} {k}" for k in ("po", "pp", "pc") if t.get(k)]
    itens = [i["nome"] for i in t.get("itens", [])] + [j["nome"] for j in t.get("joias", [])]
    if t.get("gemas"):
        itens.append(f"{len(t['gemas'])} gemas")
    if moedas or itens:
        partes.append("tesouro: " + ", ".join(moedas + itens))
    if cont.get("segredos"):
        partes.append("segredo: " + "; ".join(cont["segredos"]))
    return partes


def quebrar(texto, fonte, largura, d):
    linhas, atual = [], ""
    for palavra in texto.split():
        teste = (atual + " " + palavra).strip()
        if d.textlength(teste, font=fonte) <= largura:
            atual = teste
        else:
            linhas.append(atual)
            atual = palavra
    if atual:
        linhas.append(atual)
    return linhas


def main():
    layout = json.load(open(sys.argv[1]))
    saida = sys.argv[2]
    aventura = json.load(open(sys.argv[3])) if len(sys.argv) > 3 else None
    monstros = json.load(open("data/regras/monstros.json")) if aventura else {}
    G = layout["grade"]
    W_mapa = M * 2 + G["largura"] * C
    H = M * 2 + 40 + G["altura"] * C + 70
    W = W_mapa + (LADO if aventura else 250)
    img = Image.new("RGB", (W, H), (236, 242, 246))
    d = ImageDraw.Draw(img)

    # Rocha com grade
    rocha = (M, M + 40, M + G["largura"] * C, M + 40 + G["altura"] * C)
    d.rectangle(rocha, fill=ROCHA)
    grade_em(d, rocha, ROCHA_GRADE)

    salas = {s["id"]: s for s in layout["salas"]}
    cons = []
    for c in layout["conexoes"]:
        cons.append((corredor(salas[c["de"]], salas[c["para"]]), c))

    # Corredores (chão)
    for (eixo, a, b0, b1), _ in cons:
        if eixo == "v":
            x0, y0 = px(a, b0); x1, y1 = px(a + 1, b1)
        else:
            x0, y0 = px(b0, a); x1, y1 = px(b1, a + 1)
        d.rectangle([x0, y0, x1, y1], fill=CHAO, outline=PAREDE, width=3)
    for s in layout["salas"]:
        desenhar_sala(d, s)
    # Grade do chão por cima das áreas escavadas
    mascara = Image.new("L", img.size, 0)
    dm = ImageDraw.Draw(mascara)
    for (eixo, a, b0, b1), _ in cons:
        x0, y0 = (px(a, b0) if eixo == "v" else px(b0, a))
        x1, y1 = (px(a + 1, b1) if eixo == "v" else px(b1, a + 1))
        dm.rectangle([x0 + 2, y0 + 2, x1 - 2, y1 - 2], fill=255)
    for s in layout["salas"]:
        x0, y0, x1, y1 = ret(s)
        if s.get("forma") == "redonda":
            dm.ellipse([x0 + 3, y0 + 3, x1 - 3, y1 - 3], fill=255)
        elif s.get("forma") == "caverna":
            dm.rounded_rectangle([x0 + 3, y0 + 3, x1 - 3, y1 - 3], radius=C * 1.1, fill=255)
        else:
            dm.rectangle([x0 + 3, y0 + 3, x1 - 3, y1 - 3], fill=255)
    camada = Image.new("RGB", img.size, CHAO)
    grade_em(ImageDraw.Draw(camada), rocha, CHAO_GRADE)
    img.paste(camada, (0, 0), mascara)
    d = ImageDraw.Draw(img)
    # Abrir as paredes onde o corredor encontra a sala
    for (eixo, a, b0, b1), _ in cons:
        if eixo == "v":
            for yy in (b0, b1):
                x0, y = px(a, yy); d.rectangle([x0 + 3, y - 4, x0 + C - 3, y + 4], fill=CHAO)
        else:
            for xx in (b0, b1):
                x, y0 = px(xx, a); d.rectangle([x - 4, y0 + 3, x + 4, y0 + C - 3], fill=CHAO)
    for s in layout["salas"]:
        detalhes_sala(d, s)
    for con, c in cons:
        porta(d, con, c, f(12))

    # Números e nomes das salas
    for s in layout["salas"]:
        x0, y0, x1, y1 = ret(s)
        d.text((x0 + 7, y0 + 5), str(s["id"]), font=f(17, True), fill=TINTA, anchor="lt", stroke_width=3, stroke_fill=CHAO)
        if not aventura:
            nome = s["nome"]
            fonte = f(11, cond=True)
            linhas = quebrar(nome, fonte, (x1 - x0) - 12, d)
            for k, ln in enumerate(linhas[:2]):
                d.text(((x0 + x1) // 2, (y0 + y1) // 2 + 4 + k * 13 - (len(linhas[:2]) - 1) * 6), ln, font=fonte, fill=SUAVE, anchor="mm", stroke_width=2, stroke_fill=CHAO)

    # Entrada
    e = salas[layout["entrada"]]
    ex = M + (e["x"] + e["w"] / 2) * C
    ey = M + 40 + (e["y"] + e["h"]) * C
    d.polygon([(ex, ey + 4), (ex - 10, ey + 22), (ex + 10, ey + 22)], fill=VERMELHO)
    d.text((ex, ey + 36), "ENTRADA", font=f(12, True), fill=VERMELHO, anchor="mm")

    # Título, escala e norte
    titulo = layout["nome"] if not aventura else aventura["titulo"]
    sub = "Planta padrão — vale para todas as aventuras" if not aventura else "Aventura 1 — conteúdo das salas sobre a planta padrão"
    d.text((M, M - 6), titulo, font=f(22, True), fill=TINTA, anchor="lt")
    d.text((M, M + 20), sub, font=f(13), fill=SUAVE, anchor="lt")
    yb = M + 40 + G["altura"] * C + 22
    d.rectangle([M, yb, M + C, yb + 8], fill=TINTA)
    d.rectangle([M + C, yb, M + 2 * C, yb + 8], outline=TINTA, width=1)
    d.rectangle([M + 2 * C, yb, M + 5 * C, yb + 8], fill=TINTA)
    d.text((M, yb + 14), "1 quadrado = 3 m (10 pés)", font=f(12), fill=SUAVE, anchor="lt")
    nx, ny = W_mapa - M - 20, yb + 10
    d.polygon([(nx, ny - 18), (nx - 8, ny + 6), (nx, ny), (nx + 8, ny + 6)], fill=TINTA)
    d.text((nx, ny + 18), "N", font=f(13, True), fill=TINTA, anchor="mm")

    # Painel lateral
    px0 = W_mapa + 4
    y = M
    if not aventura:
        d.text((px0, y), "Portas", font=f(16, True), fill=TINTA); y += 30
        exemplos = [
            ("porta", {"tipo": "porta"}), ("porta emperrada", {"tipo": "porta", "emperrada": True}),
            ("porta trancada", {"tipo": "porta", "trancada": True}), ("porta secreta", {"tipo": "porta_secreta"}),
        ]
        for nome, tipo in exemplos:
            cx, cy = px0 + 14, y + 8
            if tipo["tipo"] == "porta_secreta":
                d.rectangle([cx - C / 2, cy - 2, cx + C / 2, cy + 2], fill=PAREDE)
                d.text((cx, cy), "S", font=f(15, True), fill=VERMELHO, anchor="mm", stroke_width=3, stroke_fill=(236, 242, 246))
            else:
                d.rectangle([cx - C * 0.45, cy - 4, cx + C * 0.45, cy + 4], fill=PAREDE if not tipo.get("emperrada") else CHAO, outline=PAREDE, width=2)
                if tipo.get("trancada"):
                    d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=OURO, outline=PAREDE)
            d.text((px0 + 36, y + 8), nome, font=f(13), fill=TINTA, anchor="lm")
            y += 26
        y += 14
        d.text((px0, y), "Salas", font=f(16, True), fill=TINTA); y += 28
        for s in layout["salas"]:
            d.text((px0, y), f"{s['id']:>2}  {s['nome']}", font=f(13), fill=TINTA); y += 20
        y += 12
        for ln in quebrar("A planta é fixa. Cada aventura muda só o que há em cada sala e o estado das portas.", f(12), 230, d):
            d.text((px0, y), ln, font=f(12), fill=SUAVE); y += 17
    else:
        d.text((px0, y), "Legenda", font=f(16, True), fill=TINTA); y += 28
        leg = [("mon", "monstros (número)"), ("arm", "armadilha, teste ou maldição"), ("tes", "tesouro"), ("seg", "segredo ou pista"), ("fal", "dá para negociar")]
        cores = {"mon": VERMELHO, "arm": ROXO, "tes": OURO, "seg": VERDE, "fal": SUAVE}
        lx = px0
        for tipo, txt in leg:
            cx, cy = lx + 8, y + 8
            if tipo == "tes":
                d.polygon([(cx, cy - 8), (cx + 8, cy), (cx, cy + 8), (cx - 8, cy)], fill=cores[tipo], outline=PAREDE)
            elif tipo == "arm":
                d.polygon([(cx, cy - 8), (cx + 8, cy + 7), (cx - 8, cy + 7)], fill=cores[tipo], outline=PAREDE)
            else:
                d.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=cores[tipo], outline=PAREDE)
            d.text((lx + 22, cy), txt, font=f(12), fill=TINTA, anchor="lm")
            y += 21
        y += 10
        larg = LADO - 40
        for s in layout["salas"]:
            cont = aventura["salas"].get(str(s["id"]), {})
            d.text((px0, y), f"{s['id']}. {s['nome']}", font=f(13, True), fill=TINTA); y += 18
            partes = resumo_sala(cont, monstros) or ["vazia"]
            for p in partes:
                for ln in quebrar(p, f(11, cond=True), larg - 12, d):
                    d.text((px0 + 12, y), ln, font=f(11, cond=True), fill=SUAVE); y += 14
            y += 5
        y += 6
        err = aventura.get("errantes", {})
        d.text((px0, y), f"Monstros errantes: {err.get('chance', '')} a cada {err.get('frequencia_turnos', '?')} turnos", font=f(12, True), fill=TINTA); y += 18
        tab = "; ".join(f"{i + 1}: {t.replace('_', ' ')}" for i, t in enumerate(err.get("tabela", [])))
        for ln in quebrar(tab, f(11, cond=True), larg, d):
            d.text((px0, y), ln, font=f(11, cond=True), fill=SUAVE); y += 14

    # Conteúdo da aventura no mapa
    if aventura:
        for s in layout["salas"]:
            marcadores(d, s, aventura["salas"].get(str(s["id"]), {}))
        # Portas que a aventura altera (ex.: 8-9 com armadilha)
        for chave, alt in aventura.get("portas", {}).items():
            a_, b_ = map(int, chave.split("-"))
            eixo, a, b0, b1 = corredor(salas[a_], salas[b_])
            cx, cy = (px(a + 0.5, (b0 + b1) / 2) if eixo == "v" else px((b0 + b1) / 2, a + 0.5))
            if alt.get("armadilha"):
                r = 7
                d.polygon([(cx + 12, cy - r - 10), (cx + 12 + r, cy + r - 11), (cx + 12 - r, cy + r - 11)], fill=ROXO, outline=PAREDE)
                d.text((cx + 12, cy - 8), "!", font=f(9, True), fill="white", anchor="mm")

    img.save(saida)
    print(f"salvo {saida} ({img.width}×{img.height})")


if __name__ == "__main__":
    main()
