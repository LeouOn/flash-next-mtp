#!/usr/bin/env bash
# Linux / Strix Halo launcher. Vulkan/RADV is the default; ROCm is opt-in.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

PORT="${FLASH_NEXT_PORT:-8097}"
CTX="${FLASH_NEXT_CTX:-32768}"
NMAX="${FLASH_NEXT_NMAX:-3}"
HOST="${FLASH_NEXT_HOST:-127.0.0.1}"
CORS="${FLASH_NEXT_CORS:-localhost}"
MODEL="${FLASH_NEXT_MODEL:-}"
MTP="${FLASH_NEXT_MTP:-}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

KEY_FILE="$ROOT/api-key.txt"
API_KEY="${FLASH_NEXT_API_KEY:-}"
if [[ -z "$API_KEY" && -f "$KEY_FILE" ]]; then
  API_KEY="$(tr -d '\r\n' < "$KEY_FILE")"
fi
if [[ -z "$API_KEY" ]]; then
  API_KEY="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(16))
PY
)"
  printf '%s' "$API_KEY" > "$KEY_FILE"
  echo "wrote new API key to api-key.txt (gitignored)"
fi

SERVER="$(find "$ROOT/bin" -name llama-server -type f 2>/dev/null | head -n1 || true)"
if [[ -z "$SERVER" ]]; then
  echo "Engine missing. On Linux, extract Unsloth vulkan or gfx1151-rocm into bin/" >&2
  echo "  https://github.com/unslothai/llama.cpp/releases/tag/b10715-mix-86bd2d3" >&2
  exit 1
fi

if [[ -z "$MODEL" ]]; then
  echo "Set FLASH_NEXT_MODEL to the uncensored Q3_K_S (or other) GGUF." >&2
  exit 1
fi

if [[ -z "$MTP" ]]; then
  MTP="$(find "$ROOT/mtp" -name 'mtp-Qwen3.8-Flash-Next-Q8_0.gguf' ! -name '*shared*' 2>/dev/null | head -n1 || true)"
fi
if [[ -z "$MTP" ]]; then
  echo "MTP sidecar missing. Run setup or hf download unsloth MTP/mtp-Qwen3.8-Flash-Next-Q8_0.gguf" >&2
  exit 1
fi

mkdir -p "$ROOT/logs"
LOG="$ROOT/logs/server-$(date +%Y%m%d-%H%M%S).log"

# RADV wins on this APU for Flash-Next. ROCm: export FLASH_NEXT_ROCM=1
if [[ "${FLASH_NEXT_ROCM:-}" == "1" ]]; then
  export HSA_ENABLE_SDMA=0 HSA_XNACK=1
else
  export AMD_VULKAN_ICD="${AMD_VULKAN_ICD:-RADV}"
fi

echo "target  $MODEL"
echo "draft   $MTP  n-max=$NMAX"
echo "bind    ${HOST}:${PORT}  cors=$CORS"
echo "api     http://127.0.0.1:${PORT}/v1"
echo "auth    Authorization: Bearer <api-key.txt>"
echo "log     $LOG"
echo "Draft acceptance prints at the END of each completion."

exec "$SERVER" \
  -m "$MODEL" \
  --host "$HOST" --port "$PORT" \
  --api-key "$API_KEY" \
  --cors-origins "$CORS" \
  --no-cors-credentials \
  --no-webui \
  -ngl 99 -fa on --jinja --fit off \
  -c "$CTX" -np 1 -b 2048 -ub 512 \
  --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 \
  --alias qwen38-flash-next-uncensored \
  --override-tensor 'per_layer_token_embd.weight=CPU' \
  --metrics --slots \
  --log-file "$LOG" --log-timestamps --verbosity 1 \
  -md "$MTP" -ngld 99 \
  --spec-type draft-mtp,ngram-mod \
  --spec-draft-n-max "$NMAX" \
  --spec-draft-p-min 0.75 \
  --spec-ngram-mod-n-max 64 \
  --spec-ngram-mod-n-match 24
