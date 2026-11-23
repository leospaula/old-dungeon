#!/usr/bin/env python3
"""Gera modelos 3D no Tripo e salva o .glb no projeto.

Uso:
    python3 tools/tripo.py saldo
    python3 tools/tripo.py gerar  "goblin voxel com lança"   assets/voxel/kobold.glb
    python3 tools/tripo.py imagem arte/final/personagens/tessa-recorte.png assets/voxel/tessa.glb [--final]
    python3 tools/tripo.py baixar <task_id> destino.glb   # baixa de novo uma tarefa já feita
    python3 tools/tripo.py v3 animations/rig '{"input": "<task_id>"}' [destino]   # qualquer endpoint v3

Sem --final, gera um rascunho (textura padrão). Com --final, gera textura
detalhada e PBR.

A chave é lida de TRIPO_API_KEY ou de ~/.config/secrets/tripo.env.
Ela nunca deve ser colocada no repositório.
"""
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

API = "https://api.tripo3d.ai/v2/openapi"
API3 = "https://openapi.tripo3d.ai/v3"
SECRETS = os.path.expanduser("~/.config/secrets/tripo.env")
UA = "masmorra-classica-tools/0.1"


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


def _abrir(req):
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            resp = json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code} em {req.full_url}: {e.read().decode(errors='replace')[:800]}")
    if resp.get("code") != 0:
        sys.exit(f"Erro da API do Tripo: {resp}")
    return resp["data"]


def chamar(metodo, caminho, corpo=None):
    req = urllib.request.Request(
        API + caminho,
        method=metodo,
        data=json.dumps(corpo).encode() if corpo is not None else None,
        headers={
            "Authorization": f"Bearer {chave()}",
            "Content-Type": "application/json",
            "User-Agent": UA,
        },
    )
    return _abrir(req)


def enviar_imagem(caminho, versao=2):
    """Faz upload de uma imagem e devolve o token (v2: image_token; v3: file_token)."""
    limite = uuid.uuid4().hex
    tipo = mimetypes.guess_type(caminho)[0] or "image/png"
    with open(caminho, "rb") as f:
        conteudo = f.read()
    corpo = (
        f"--{limite}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{os.path.basename(caminho)}"\r\n'
        f"Content-Type: {tipo}\r\n\r\n"
    ).encode() + conteudo + f"\r\n--{limite}--\r\n".encode()
    req = urllib.request.Request(
        (API + "/upload") if versao == 2 else (API3 + "/files"),
        method="POST",
        data=corpo,
        headers={
            "Authorization": f"Bearer {chave()}",
            "Content-Type": f"multipart/form-data; boundary={limite}",
            "User-Agent": UA,
        },
    )
    d = _abrir(req)
    return d["image_token"] if versao == 2 else d["file_token"]


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


def baixar_resultado(d, destino):
    out = d.get("output", {})
    url = out.get("pbr_model") or out.get("model") or out.get("base_model")
    if not url:
        sys.exit(f"Tarefa concluída sem URL de modelo: {out}")
    os.makedirs(os.path.dirname(destino) or ".", exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=300) as r, open(destino, "wb") as f:
        f.write(r.read())
    print(f"Salvo em {destino} (task {d.get('task_id')})")


def gerar(prompt, destino):
    print(f"Gerando de texto: {prompt!r}")
    task = chamar("POST", "/task", {"type": "text_to_model", "prompt": prompt})
    print(f"task_id={task['task_id']}", flush=True)
    baixar_resultado(esperar(task["task_id"]), destino)


def imagem(caminho, destino, final=False):
    print(f"Enviando {caminho}…")
    token = enviar_imagem(caminho)
    ext = os.path.splitext(caminho)[1].lstrip(".").lower().replace("jpeg", "jpg")
    corpo = {"type": "image_to_model", "file": {"type": ext, "file_token": token}, "texture": True}
    if final:
        corpo.update({"pbr": True, "texture_quality": "detailed"})
    else:
        corpo.update({"pbr": False, "texture_quality": "standard"})
    print(f"Gerando de imagem ({'final' if final else 'rascunho'})…")
    task = chamar("POST", "/task", corpo)
    print(f"task_id={task['task_id']}", flush=True)
    baixar_resultado(esperar(task["task_id"]), destino)



def v3(endpoint, corpo, destino=None):
    """Chama um endpoint da API v3, espera a tarefa e baixa o resultado (opcional)."""
    req = urllib.request.Request(
        f"{API3}/{endpoint.lstrip('/')}",
        method="POST",
        data=json.dumps(corpo).encode(),
        headers={"Authorization": f"Bearer {chave()}", "Content-Type": "application/json", "User-Agent": UA},
    )
    task_id = _abrir(req)["task_id"]
    print(f"task_id={task_id}", flush=True)
    while True:
        req = urllib.request.Request(f"{API3}/tasks/{task_id}", headers={"Authorization": f"Bearer {chave()}", "User-Agent": UA})
        d = _abrir(req)
        if d.get("status") in ("success", "failed", "cancelled", "banned", "expired", "unknown"):
            break
        time.sleep(4)
    out = d.get("output", {})
    print(json.dumps({k: (v if not str(v).startswith("http") else "<url>") for k, v in out.items()}, ensure_ascii=False))
    print(f"status={d.get('status')} créditos={d.get('credits_consumed', d.get('consumed_credit'))}")
    if destino and d.get("status") == "success":
        url = next((v for v in out.values() if isinstance(v, str) and v.startswith("http")), None)
        if url:
            os.makedirs(os.path.dirname(destino) or ".", exist_ok=True)
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=300) as r, open(destino, "wb") as f:
                f.write(r.read())
            print(f"Salvo em {destino}")
    return d


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["saldo"]:
        print(chamar("GET", "/user/balance"))
    elif len(a) == 3 and a[0] == "gerar":
        gerar(a[1], a[2])
    elif len(a) in (3, 4) and a[0] == "v3":
        v3(a[1], json.loads(a[2]), a[3] if len(a) == 4 else None)
    elif len(a) == 3 and a[0] == "baixar":
        baixar_resultado(esperar(a[1]), a[2])
    elif len(a) in (3, 4) and a[0] == "imagem":
        imagem(a[1], a[2], final="--final" in a)
    else:
        sys.exit(__doc__)
