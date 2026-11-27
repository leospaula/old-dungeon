#!/usr/bin/env bash
# Abre o jogo direto numa seção da aventura, para testar dali em diante.
#   tools/secao.sh 3                 # aventura 1, seção 3 (grupo padrão, sem a tela de escolha)
#   tools/secao.sh 3 --escolher      # com a tela de escolha do grupo
#   tools/secao.sh 3 --grupo=tessa,durgo,caco,lianne,bento
#   AVENTURA=aventura-2 tools/secao.sh 1
#   tools/secao.sh                   # lista as seções
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
AV="${AVENTURA:-aventura-1}"
if [ $# -eq 0 ]; then
  python3 -c "import json,sys;d=json.load(open('$RAIZ/data/aventuras/$AV/aventura.json'));[print(f\"  {s['id']:>3}  {s['nome']}\") for s in d.get('secoes',[])]"
  exit 0
fi
S="$1"; shift
exec godot --path "$RAIZ" -- --aventura="$AV" --secao="$S" "$@"
