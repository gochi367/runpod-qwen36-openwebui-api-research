#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"
}

: "${MODEL_DIR:=/tmp/models}"
: "${HF_HOME:=/tmp/hf_home}"
: "${HF_HUB_ENABLE_HF_TRANSFER:=1}"
: "${MODEL_REPO:=HauhauCS/Qwen3.6-27B-Uncensored-HauhauCS-Balanced}"
: "${MODEL_FILE:=Qwen3.6-27B-Uncensored-HauhauCS-Balanced-Q5_K_P.gguf}"
: "${MODEL_ALIAS:=qwen3.6-27b-balanced}"
: "${LLAMA_PORT:=8000}"
: "${API_KEY:=r}"
: "${CTX_SIZE:=32768}"
: "${NGL:=99}"
: "${WEBUI_PORT:=8080}"
: "${WEBUI_HOST:=0.0.0.0}"
: "${WEBUI_AUTH:=true}"
: "${WEBUI_SECRET_KEY:=change-this-in-runpod-env}"
: "${DATA_DIR:=/tmp/open-webui-data}"
: "${MIN_MODEL_BYTES:=5000000000}"

export MODEL_DIR
export HF_HOME
export HF_HUB_ENABLE_HF_TRANSFER
export DATA_DIR

mkdir -p "${MODEL_DIR}" "${HF_HOME}" "${DATA_DIR}"

MODEL_PATH="${MODEL_DIR}/${MODEL_FILE}"

if [[ ! -s "${MODEL_PATH}" ]]; then
  log "Downloading model: ${MODEL_REPO}/${MODEL_FILE}"
  python - <<'PY'
import os
from huggingface_hub import hf_hub_download

repo = os.environ["MODEL_REPO"]
filename = os.environ["MODEL_FILE"]
model_dir = os.environ["MODEL_DIR"]

path = hf_hub_download(
    repo_id=repo,
    filename=filename,
    local_dir=model_dir,
)
print(path)
PY
else
  log "Model already exists: ${MODEL_PATH}"
fi

if [[ ! -s "${MODEL_PATH}" ]]; then
  log "ERROR: model file does not exist or is empty: ${MODEL_PATH}"
  exit 31
fi

MODEL_BYTES="$(stat -c '%s' "${MODEL_PATH}")"
log "Model file size: ${MODEL_BYTES} bytes"

if (( MODEL_BYTES < MIN_MODEL_BYTES )); then
  log "ERROR: downloaded file is too small. Expected GGUF, got ${MODEL_BYTES} bytes."
  exit 32
fi

LLAMA_BIN="/app/llama-server"
if [[ ! -x "${LLAMA_BIN}" ]]; then
  LLAMA_BIN="$(command -v llama-server || true)"
fi

if [[ -z "${LLAMA_BIN}" || ! -x "${LLAMA_BIN}" ]]; then
  log "ERROR: llama-server not found"
  exit 33
fi

log "Starting llama-server on port ${LLAMA_PORT}"

"${LLAMA_BIN}" \
  -m "${MODEL_PATH}" \
  --alias "${MODEL_ALIAS}" \
  --host 0.0.0.0 \
  --port "${LLAMA_PORT}" \
  --api-key "${API_KEY}" \
  -c "${CTX_SIZE}" \
  -ngl "${NGL}" \
  --flash-attn auto \
  --jinja \
  --reasoning off \
  --reasoning-format none \
  --chat-template-kwargs '{"enable_thinking":false}' &
LLAMA_PID=$!

cleanup() {
  log "Stopping services..."
  kill "${LLAMA_PID}" "${WEBUI_PID:-}" 2>/dev/null || true
}

trap cleanup INT TERM EXIT

log "Waiting for llama-server health..."

for i in $(seq 1 180); do
  if curl -fsS "http://127.0.0.1:${LLAMA_PORT}/health" >/dev/null 2>&1; then
    log "llama-server is ready"
    break
  fi

  sleep 2

  if ! kill -0 "${LLAMA_PID}" 2>/dev/null; then
    log "ERROR: llama-server exited early"
    wait "${LLAMA_PID}" || true
    exit 34
  fi

  if [[ "${i}" == "180" ]]; then
    log "ERROR: llama-server health timeout"
    exit 35
  fi
done

export ENABLE_OPENAI_API=True
export OPENAI_API_BASE_URL="http://127.0.0.1:${LLAMA_PORT}/v1"
export OPENAI_API_KEY="${API_KEY}"
export WEBUI_AUTH="${WEBUI_AUTH}"
export WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY}"
export HOST="${WEBUI_HOST}"
export PORT="${WEBUI_PORT}"

log "Starting Open WebUI on ${WEBUI_HOST}:${WEBUI_PORT}"

open-webui serve --host "${WEBUI_HOST}" --port "${WEBUI_PORT}" &
WEBUI_PID=$!

wait -n "${LLAMA_PID}" "${WEBUI_PID}"
EXIT_CODE=$?

log "A service exited. exit_code=${EXIT_CODE}"
exit "${EXIT_CODE}"
