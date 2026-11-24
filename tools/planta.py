"""Leitura da planta (data/masmorra/layout.json) e coordenadas locais das áreas.

Coordenadas locais no estilo tabuleiro: letra = coluna, número = linha, a partir do
canto superior esquerdo da caixa que envolve a área. "A1" é esse canto; "C3" é a
terceira coluna da terceira linha. Só valem células que são chão daquela área.
"""
import json
import re
import string

LETRAS = string.ascii_uppercase


class Planta:
    def __init__(self, caminho="data/masmorra/layout.json"):
        self.dados = json.load(open(caminho))
        g = self.dados["grade"]
        self.W, self.H = g["largura"], g["altura"]
        self.areas = {a["id"]: a for a in self.dados["areas"]}
        self.cel = [[None] * self.W for _ in range(self.H)]
        for a in self.dados["areas"]:
            for x0, y0, x1, y1 in a["retangulos"]:
                for y in range(y0, y1):
                    for x in range(x0, x1):
                        self.cel[y][x] = a["id"]
        self.portas = {p["id"]: p for p in self.dados["portas"]}
        self.secretas = {s["id"]: s for s in self.dados.get("secretas_sugeridas", [])}

    def caixa(self, area):
        rs = self.areas[area]["retangulos"]
        return (min(r[0] for r in rs), min(r[1] for r in rs), max(r[2] for r in rs), max(r[3] for r in rs))

    def celulas(self, area):
        x0, y0, x1, y1 = self.caixa(area)
        return [(x, y) for y in range(y0, y1) for x in range(x0, x1) if self.cel[y][x] == area]

    def coord_para_celula(self, area, coord):
        """'C3' em `area` → (x, y) global. Erro se não for chão daquela área."""
        m = re.fullmatch(r"([A-Z])(\d{1,2})", coord.strip().upper())
        if not m:
            raise ValueError(f"coordenada inválida '{coord}' (use letra+número, ex.: C3)")
        x0, y0, _, _ = self.caixa(area)
        x, y = x0 + LETRAS.index(m.group(1)), y0 + int(m.group(2)) - 1
        if not (0 <= x < self.W and 0 <= y < self.H) or self.cel[y][x] != area:
            raise ValueError(f"{coord} não é chão da área {area}")
        return x, y

    def celula_para_coord(self, area, x, y):
        x0, y0, _, _ = self.caixa(area)
        return f"{LETRAS[x - x0]}{y - y0 + 1}"

    def cabe(self, area, coord, w, h):
        """Um objeto w×h com o canto superior esquerdo em `coord` cabe inteiro no chão da área?"""
        x, y = self.coord_para_celula(area, coord)
        return all(0 <= y + j < self.H and 0 <= x + i < self.W and self.cel[y + j][x + i] == area
                   for j in range(h) for i in range(w))
