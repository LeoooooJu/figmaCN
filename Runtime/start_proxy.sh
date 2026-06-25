#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
ALLOW_HOSTS='^(.+\.)?figma\.com(:443)?$'

if [[ -n "${FigmaCN_LANG_URL:-}" ]]; then
  ALLOW_HOSTS='^(.+\.)?figma\.com(:443)?$|^[A-Za-z0-9-]+\.github\.io(:443)?$'
fi

python3 validate_lang.py

exec mitmdump \
  --listen-host "$HOST" \
  -p "$PORT" \
  --set keepserving=true \
  --set flow_detail=0 \
  --set termlog_verbosity=info \
  --set "allow_hosts=${ALLOW_HOSTS}" \
  -s injector.py
