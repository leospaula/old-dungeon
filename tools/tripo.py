#!/usr/bin/env python3
"""Gera um modelo 3D no Tripo a partir de texto e salva o .glb em assets/.

Uso:
    python3 tools/tripo.py saldo
    python3 tools/tripo.py gerar "goblin voxel com lança" assets/voxel/kobold.glb

A chave é lida de TRIPO_API_KEY ou de ~/.config/secrets/tripo.env.
Ela nunca deve ser colocada no repositório.
"""
import json
import os
import sys
import time
import urllib.request

API = "https://api.tripo3d.ai/v2/openapi"
SECRETS = os.path.expanduser("~/.config/secrets/tripo.env")


def chave():
    if os.environ.get("TRIPO_API_KEY"):
        return os.environ["TRIPO_API_KEY"]
    try:
        with open(SECRETS) as f:
            for linha in f:
                if linha.startswith("TRIPO_API_KEY="):
                    return linha.split("=", 1)[1].strip()
    except FileNotFoundError:
        pass
    sys.exit(f"TRIPO_API_KEY não encontrada (env ou {SECRETS})")


def chamar(metodo, caminho, corpo=None):
    req = urllib.request.Request(
        API + caminho,
        method=metodo,
        data=json.dumps(corpo).encode() if corpo is not None else None,
        headers={
            "Authorization": f"Bearer {chave()}",
            "Content-Type": "application/json",
            "User-Agent": "masmorra-classica-tools/0.1",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        resp = json.load(r)
    if resp.get("code") != 0:
        sys.exit(f"Erro da API do Tripo: {resp}")
    return resp["data"]


def esperar(task_id):
    while True:
        d = chamar("GET", f"/task/{task_id}")
        status = d.get("status")
        print(f"  {status} {d.get('progress', '')}%", flush=True)
        if status == "success":
            return d
        if status in ("failed", "cancelled", "unknown", "banned", "expired"):
            sys.exit(f"Tarefa terminou com status {status}: {d}")
        time.sleep(5)


def gerar(prompt, destino):
    print(f"Gerando: {prompt!r}")
    task = chamar("POST", "/task", {"type": "text_to_model", "prompt": prompt})
    d = esperar(task["task_id"])
    out = d.get("output", {})
    url = out.get("pbr_model") or out.get("model") or out.get("base_model")
    if not url:
        sys.exit(f"Tarefa concluída sem URL de modelo: {out}")
    os.makedirs(os.path.dirname(destino) or ".", exist_ok=True)
    urllib.request.urlretrieve(url, destino)
    print(f"Salvo em {destino}")


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "saldo":
        print(chamar("GET", "/user/balance"))
    elif len(sys.argv) == 4 and sys.argv[1] == "gerar":
        gerar(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
