#!/usr/bin/env bash
# Copia o ateliê para a pasta de rascunho da sessão do Claude, de onde o Artifact é publicado.
set -euo pipefail
DEST="${1:?uso: publicar.sh <pasta-de-destino>}"
mkdir -p "$DEST"
rsync -a --delete "$(dirname "$0")/" "$DEST/" --exclude publicar.sh
