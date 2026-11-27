#!/usr/bin/env python3
"""Valida uma aventura contra o esquema e contra a planta, o bestiário e o catálogo de props.

Uso: python3 tools/validar_aventura.py data/aventuras/<id>/aventura.json
Sai com código 1 se houver erros. Avisos não impedem.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from planta import Planta  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    caminho = sys.argv[1]
    av = json.load(open(caminho))
    erros, avisos = [], []
    E = lambda onde, msg: erros.append(f"{onde}: {msg}")
    A = lambda onde, msg: avisos.append(f"{onde}: {msg}")

    # 1) Esquema
    try:
        import jsonschema
        esquema = json.load(open(os.path.join(RAIZ, "data/esquemas/aventura.schema.json")))
        v = jsonschema.Draft202012Validator(esquema)
        for e in sorted(v.iter_errors(av), key=lambda e: list(e.path)):
            E("/".join(map(str, e.path)) or "(raiz)", e.message)
    except ImportError:
        A("esquema", "módulo jsonschema não instalado; validação de esquema pulada")
    if erros:
        return relatorio(caminho, erros, avisos)

    # 2) Referências
    pl = Planta(os.path.join(RAIZ, "data/masmorra/layout.json"))
    monstros = json.load(open(os.path.join(RAIZ, "data/regras/monstros.json")))
    props = json.load(open(os.path.join(RAIZ, "data/catalogos/props.json")))["props"]
    itens = av.get("itens", {})
    pdms = av.get("pdms", {})
    eventos = {e["id"] for e in av.get("eventos", [])}
    objetivos = {o["id"] for o in av.get("objetivos", [])}

    versao = int(av["planta"].split("@")[1])
    if versao != pl.dados.get("versao"):
        E("planta", f"aventura feita para a versão {versao}, mas a planta está na versão {pl.dados.get('versao')}")

    def area_ok(onde, area):
        if area not in pl.areas:
            E(onde, f"área '{area}' não existe na planta"); return False
        return True

    def pos_ok(onde, area, pos):
        try:
            return pl.coord_para_celula(area, pos)
        except ValueError as e:
            E(onde, str(e)); return None

    def item_ok(onde, nome):
        # ids de itens da aventura usam hífen; nomes livres de equipamento comum têm espaço
        if re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)+", nome) and nome not in itens:
            E(onde, f"item '{nome}' não está em 'itens'")

    ocupado = {}  # (x, y) -> o que bloqueia

    # Início
    ini = av["inicio"]
    if area_ok("inicio.area", ini["area"]) and pos_ok("inicio.pos", ini["area"], ini["pos"]):
        if ini["tipo"] == "escada":
            w, h = props["escada-entrada"]["tamanho"]
            if ini.get("giro", 0) in (90, 270): w, h = h, w
            if not pl.cabe(ini["area"], ini["pos"], w, h):
                E("inicio", f"a escada {w}×{h} não cabe em {ini['area']} a partir de {ini['pos']}")
            entradas = pl.dados.get("entradas_possiveis", {}).get("areas", [])
            if ini["area"] not in entradas:
                A("inicio.area", f"{ini['area']} não está entre as entradas principais {entradas}")
    if "equipamento_em" in ini:
        q = ini["equipamento_em"]
        if area_ok("inicio.equipamento_em.area", q["area"]):
            pos_ok("inicio.equipamento_em.pos", q["area"], q["pos"])
        if q.get("prop") and q["prop"] not in props:
            E("inicio.equipamento_em.prop", f"prop '{q['prop']}' não existe no catálogo")

    # Portas e secretas
    for pid, est in av.get("portas", {}).items():
        if pid not in pl.portas:
            E(f"portas.{pid}", "porta não existe na planta"); continue
        if pl.portas[pid]["tipo"] == "cela" and est.get("estado") == "secreta":
            E(f"portas.{pid}", "porta de cela não pode ser secreta")
        if est.get("abre_com"):
            item_ok(f"portas.{pid}.abre_com", est["abre_com"])
        if est.get("armadilha", {}).get("evento") and est["armadilha"]["evento"] not in eventos:
            E(f"portas.{pid}.armadilha.evento", f"evento '{est['armadilha']['evento']}' não existe")
    for sid in av.get("secretas", []):
        if sid not in pl.secretas:
            E(f"secretas.{sid}", "secreta não existe entre as sugeridas da planta")

    # Áreas
    for area, c in av["areas"].items():
        onde = f"areas.{area}"
        if not area_ok(onde, area): continue
        for i, pr in enumerate(c.get("props", [])):
            o = f"{onde}.props[{i}]"
            if pr["tipo"] not in props:
                E(o, f"prop '{pr['tipo']}' não existe no catálogo"); continue
            if not pos_ok(o, area, pr["pos"]): continue
            w, h = props[pr["tipo"]]["tamanho"]
            if pr.get("giro", 0) in (90, 270): w, h = h, w
            if not pl.cabe(area, pr["pos"], w, h):
                E(o, f"{pr['tipo']} ({w}×{h}) não cabe a partir de {pr['pos']}"); continue
            if props[pr["tipo"]]["bloqueia"]:
                x, y = pl.coord_para_celula(area, pr["pos"])
                for j in range(h):
                    for k in range(w):
                        if (x + k, y + j) in ocupado:
                            A(o, f"sobrepõe {ocupado[(x + k, y + j)]}")
                        ocupado[(x + k, y + j)] = f"{pr['tipo']} em {area} {pr['pos']}"
            for it in (pr.get("conteudo") or {}).get("itens", []):
                item_ok(f"{o}.conteudo", it)
        for i, m in enumerate(c.get("monstros", [])):
            o = f"{onde}.monstros[{i}]"
            if m["tipo"] not in monstros:
                E(o, f"monstro '{m['tipo']}' não existe no bestiário")
            poss = m.get("posicoes") or ([m["pos"]] if "pos" in m else [])
            for p_ in poss:
                xy = pos_ok(o, area, p_)
                if xy and xy in ocupado:
                    A(o, f"{p_} está em cima de {ocupado[xy]}")
            if m.get("posicoes") and len(m["posicoes"]) != m.get("qtd", 1):
                A(o, f"qtd={m.get('qtd', 1)} mas {len(m['posicoes'])} posições")
            for it in m.get("carrega", []):
                item_ok(f"{o}.carrega", it)
        for i, p_ in enumerate(c.get("pdms", [])):
            o = f"{onde}.pdms[{i}]"
            if p_["id"] not in pdms: E(o, f"pdm '{p_['id']}' não está em 'pdms'")
            pos_ok(o, area, p_["pos"])
        for i, t in enumerate(c.get("tesouros", [])):
            o = f"{onde}.tesouros[{i}]"
            if "pos" in t: pos_ok(o, area, t["pos"])
            for it in t.get("itens", []): item_ok(o, it)
        for i, a_ in enumerate(c.get("armadilhas", [])):
            o = f"{onde}.armadilhas[{i}]"
            if "pos" in a_: pos_ok(o, area, a_["pos"])
            else: A(o, "armadilha sem posição")
            if a_.get("evento") and a_["evento"] not in eventos:
                E(o, f"evento '{a_['evento']}' não existe")

    # Cenas: passos com área/posição, portas, PdMs e cenas citadas.
    cenas = av.get("cenas", {})
    surgem = set()
    SONS = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "sons.json")))["eventos"]
    def passos_ok(onde, passos):
        for j, p_ in enumerate(passos):
            o = f"{onde}[{j}]"
            if "area" in p_ and "pos" in p_ and area_ok(o, p_["area"]): pos_ok(o, p_["area"], p_["pos"])
            if "porta" in p_ and p_["porta"] not in pl.portas: E(o, f"porta {p_['porta']} não existe")
            if p_.get("faz") == "surgir":
                if p_.get("pdm", p_.get("quem")) not in pdms: E(o, f"pdm '{p_.get('pdm', p_.get('quem'))}' não está em 'pdms'")
                surgem.add(p_.get("pdm", p_.get("quem")))
            if p_.get("faz") == "cena" and p_.get("id") not in cenas: E(o, f"cena '{p_.get('id')}' não existe")
            if p_.get("faz") == "som" and p_.get("som") not in SONS: E(o, f"som '{p_.get('som')}' não existe em data/sons.json")
            if p_.get("faz") == "escolha":
                for k, op in enumerate(p_.get("opcoes", [])): passos_ok(f"{o}.opcoes[{k}]", op.get("faz", []))
                passos_ok(f"{o}.ao_limite", p_.get("ao_limite", []))
    for cid, passos in cenas.items(): passos_ok(f"cenas.{cid}", passos)

    # PdMs (a base pode ser do bestiário ou só um modelo de data/regras/animacoes.json)
    criaturas = json.load(open(os.path.join(RAIZ, "data/regras/animacoes.json"))).get("criaturas", {})
    for pid, p_ in pdms.items():
        for it in p_.get("carrega", []): item_ok(f"pdms.{pid}.carrega", it)
        if p_.get("base") and p_["base"] not in monstros and p_["base"] not in criaturas:
            A(f"pdms.{pid}.base", f"'{p_['base']}' não está no bestiário nem nas criaturas com modelo")
    colocados = {p_["id"] for c in av["areas"].values() for p_ in c.get("pdms", [])} | surgem
    for pid in pdms:
        if pid not in colocados: A(f"pdms.{pid}", "pdm não foi colocado em nenhuma área")

    # Eventos e objetivos
    def gatilho_ok(onde, g):
        (k, v), = g.items()
        if k == "entrar_area": area_ok(onde, v)
        elif k == "porta_aberta" and v not in pl.portas: E(onde, f"porta {v} não existe")
        elif k == "grupo_em":
            for a_ in v: area_ok(onde, a_)
        elif k == "item_pego": item_ok(onde, v)
        elif k == "evento" and v not in eventos: E(onde, f"evento '{v}' não existe")
        elif k == "prop_usado":
            if area_ok(onde, v["area"]): pos_ok(onde, v["area"], v["pos"])
    for i, ev in enumerate(av.get("eventos", [])):
        gatilho_ok(f"eventos[{i}].quando", ev["quando"])
        for j, f in enumerate(ev["faz"]):
            (k, v), = f.items(); o = f"eventos[{i}].faz[{j}]"
            if k == "cena":
                if v not in cenas: E(o, f"cena '{v}' não existe")
                continue
            if k == "acordar": area_ok(o, v)
            elif k in ("abrir_porta", "trancar_porta") and v not in pl.portas: E(o, f"porta {v} não existe")
            elif k == "revelar_secreta" and v not in pl.secretas: E(o, f"secreta {v} não existe")
            elif k == "surgir":
                if area_ok(o, v["area"]) and "pos" in v: pos_ok(o, v["area"], v["pos"])
                if v["tipo"] not in monstros: E(o, f"monstro '{v['tipo']}' não existe")
            elif k == "dar_item": item_ok(o, v)
            elif k == "objetivo" and v not in objetivos: E(o, f"objetivo '{v}' não existe")
    for i, ob in enumerate(av.get("objetivos", [])):
        gatilho_ok(f"objetivos[{i}].condicao", ob["condicao"])
    if av.get("objetivos") and not any(o.get("final") for o in av["objetivos"]):
        A("objetivos", "nenhum objetivo marcado como final")

    # Errantes
    er = av.get("errantes")
    if er:
        faixas = sorted(t["d6"] for t in er["tabela"])
        cobertos = sorted(n for a_, b_ in faixas for n in range(a_, b_ + 1))
        if cobertos != list(range(1, 7)):
            A("errantes.tabela", f"as faixas do d6 cobrem {cobertos}, não exatamente 1–6")
        for i, t in enumerate(er["tabela"]):
            tipo = t["encontro"].split()[1]
            if tipo not in monstros: E(f"errantes.tabela[{i}]", f"monstro '{tipo}' não existe")
        for a_ in er.get("areas", []): area_ok("errantes.areas", a_)

    return relatorio(caminho, erros, avisos)


def relatorio(caminho, erros, avisos):
    print(f"{caminho}")
    for e in erros: print(f"  ✗ {e}")
    for a in avisos: print(f"  ⚠ {a}")
    if not erros and not avisos: print("  ✓ tudo certo")
    elif not erros: print(f"  ✓ sem erros ({len(avisos)} aviso(s))")
    else: print(f"  {len(erros)} erro(s), {len(avisos)} aviso(s)")
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main())
