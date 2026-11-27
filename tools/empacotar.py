#!/usr/bin/env python3
"""Monta a exportação para navegador em pacotes: um pacote base e um por parte da aventura.

- Base (index.pck): motor do jogo, cena, scripts, dados, interface, retratos, masmorra, os personagens
  jogáveis e as armas do catálogo. É o que carrega quando a página abre.
- Partes (<id>.pck): props e criaturas de cada parte da aventura (aventura.json, "partes"). O jogo baixa
  a parte quando o grupo chega nela e a guarda no navegador (scripts/exploracao/pacotes.gd).

Uso:
    python3 tools/empacotar.py                 # gera export_presets.cfg e exporta para export/web/
    python3 tools/empacotar.py --so-presets    # só escreve export_presets.cfg
    python3 tools/empacotar.py --destino DIR   # exporta para outra pasta
"""
import glob
import json
import os
import subprocess
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AVENTURAS = ["aventura-1"]
PERSONAGENS = "data/personagens/grupo-inicial.json"
HEROIS_GLB = {"tessa": "tessa-heroica", "durgo": "anao", "caco": "caco", "lianne": "lianne",
              "mirela": "maga", "anselmo": "clerigo", "bento": "halfling"}


def r(p):
    return "res://" + p


def ler(p):
    with open(os.path.join(RAIZ, p)) as f:
        return json.load(f)


def arquivos(*padroes):
    out = []
    for pad in padroes:
        for f in glob.glob(os.path.join(RAIZ, pad), recursive=True):
            if os.path.isfile(f) and not f.endswith((".import", ".uid")):
                out.append(os.path.relpath(f, RAIZ))
    return sorted(set(out))


def lista_base():
    base = arquivos("scenes/**/*.tscn", "scenes/**/*.scn", "scripts/**/*.gd", "shaders/**/*.gdshader", "shaders/**/*.gdshaderinc",
                    "arte/texturas/*.png", "arte/final/interface/**/*.png", "arte/final/retratos/*.jpg",
                    "assets/fontes/*.ttf", "assets/fontes/*.otf",
                    "arte/sons/**/*.ogg")   # efeitos sonoros (data/sons.json)
    for id_, glb in HEROIS_GLB.items():
        base.append(f"arte/final/3d/norm/{glb}.glb")
    for cen in ["tocha-parede", "porta", "porta-dupla", "portao"]:   # cenário da masmorra (em toda parte)
        base.append(f"arte/final/3d/{cen}.glb")
    for b in ler("data/regras/animacoes.json")["bibliotecas"].values():   # bibliotecas de animação (uma por arquivo)
        base.append(b["arquivo"].replace("res://", ""))
    itens = ler("data/catalogos/itens.json")["itens"]
    for it in itens.values():
        arq = it.get("modelo3d", {}).get("arquivo", "")
        if arq: base.append(arq.replace("res://", ""))
    return sorted(set(base))


def listas_partes():
    props = ler("data/catalogos/props.json")["props"]
    partes = {}
    for av in AVENTURAS:
        d = ler(f"data/aventuras/{av}/aventura.json")
        for p in d.get("partes", []):
            lst = []
            for a in p.get("areas", []):
                for pr in d.get("areas", {}).get(a, {}).get("props", []):
                    arq = props.get(pr["tipo"], {}).get("modelo3d", {}).get("arquivo", "")
                    if arq: lst.append(arq.replace("res://", ""))
            cri = ler("data/regras/animacoes.json")["criaturas"]
            for c in p.get("criaturas", []):
                lst.append(cri[c]["modelo"].replace("res://", "") if c in cri else f"arte/final/3d/norm/{c}.glb")
            partes[p["id"]] = sorted(set(lst))
    return partes


def preset(i, nome, arquivos_, runnable, incluir=""):
    lista = ", ".join('"%s"' % r(a) for a in arquivos_)
    return f"""[preset.{i}]

name="{nome}"
platform="Web"
runnable={"true" if runnable else "false"}
export_filter="resources"
export_files=PackedStringArray({lista})
include_filter="{incluir}"
exclude_filter=""
export_path="export/web/index.html"

[preset.{i}.options]

variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/canvas_resize_policy=2
progressive_web_app/enabled=false

"""


def main():
    a = sys.argv[1:]
    destino = os.path.join(RAIZ, "export/web")
    if "--destino" in a: destino = os.path.abspath(a[a.index("--destino") + 1])
    base = lista_base()
    partes = listas_partes()
    for pid, lst in partes.items():   # o que é da parte não vai no base
        base = [x for x in base if x not in lst]
    txt = preset(0, "Web", base, True, "data/*.json, data/**/*.json")
    for i, (pid, lst) in enumerate(partes.items(), start=1):
        txt += preset(i, f"Pacote {pid}", lst, False)
    with open(os.path.join(RAIZ, "export_presets.cfg"), "w") as f:
        f.write(txt)
    print(f"base: {len(base)} arquivos; partes: " + ", ".join(f"{k} {len(v)}" for k, v in partes.items()))
    if "--so-presets" in a: return
    os.makedirs(destino, exist_ok=True)
    def rodar(*args):
        p = subprocess.run(["godot", "--headless", "--path", RAIZ, *args], capture_output=True, text=True)
        if p.returncode != 0: print(p.stdout[-1500:], p.stderr[-1500:]); sys.exit(p.returncode)
    # As partes primeiro: o md5 de cada uma vai em data/pacotes.json, que entra no pacote base
    # (o jogo compara com o guardado no navegador para saber se precisa baixar de novo).
    import hashlib
    versoes = {}
    for pid in partes:
        arq = os.path.join(destino, f"{pid}.pck")
        rodar("--export-pack", f"Pacote {pid}", arq)
        versoes[pid] = hashlib.md5(open(arq, "rb").read()).hexdigest()
    with open(os.path.join(RAIZ, "data/pacotes.json"), "w") as f:
        json.dump(versoes, f, indent=1)
    rodar("--export-release", "Web", os.path.join(destino, "index.html"))
    for f in sorted(os.listdir(destino)):
        print(f"{os.path.getsize(os.path.join(destino, f)) / 1e6:9.2f} MB  {f}")


if __name__ == "__main__":
    main()
