#!/bin/bash
# Hindsight daemon launcher — template-based env generation
set -euo pipefail

PROFILE=hermes
HERMES_ENV="$HOME/.hermes/.env"
PROFILE_ENV="$HOME/.hindsight/profiles/$PROFILE.env"
BIN="$HOME/.hermes/hermes-agent/venv/bin/hindsight-embed"
PORT=9177

DEEPSEEK_KEY=$(grep "^DEEPSEEK_API_KEY=" "$HERMES_ENV" 2>/dev/null | head -1 | cut -d= -f2)
if [ -z "$DEEPSEEK_KEY" ]; then
    echo "FATAL: Cannot find DEEPSEEK_API_KEY in $HERMES_ENV" >&2
    exit 1
fi
OR_KEY=$(grep "^OPENROUTER_API_KEY=" "$HERMES_ENV" 2>/dev/null | head -1 | cut -d= -f2)
if [ -z "$OR_KEY" ]; then
    echo "FATAL: Cannot find OPENROUTER_API_KEY in $HERMES_ENV" >&2
    exit 1
fi

# Write env — LLM via DeepSeek direct, embeddings/reranker via OpenRouter
{
  echo "HINDSIGHT_API_LLM_PROVIDER=deepseek"
  echo "HINDSIGHT_API_LLM_API_KEY=${DEEPSEEK_KEY}"
  echo "HINDSIGHT_API_LLM_MODEL=deepseek-v4-pro"
  echo "HINDSIGHT_API_LLM_BASE_URL=https://api.deepseek.com"
  echo "HINDSIGHT_API_LOG_LEVEL=info"
  echo "HINDSIGHT_API_EMBEDDINGS_PROVIDER=openrouter"
  echo "HINDSIGHT_API_EMBEDDINGS_OPENROUTER_MODEL=baai/bge-m3"
  echo "HINDSIGHT_API_EMBEDDINGS_OPENROUTER_API_KEY=${OR_KEY}"
  echo "HINDSIGHT_API_EMBEDDINGS_OPENAI_BASE_URL=https://openrouter.ai/api/v1"
  echo "EMBEDDING_DIM=1024"
  echo "HINDSIGHT_API_RERANKER_PROVIDER=openrouter"
  echo "HINDSIGHT_API_RERANKER_OPENROUTER_MODEL=cohere/rerank-v3.5"
  echo "HINDSIGHT_API_RERANKER_OPENROUTER_API_KEY=${OR_KEY}"
} > "$PROFILE_ENV"

ACTUAL=$(wc -l < "$PROFILE_ENV")
if [ "$ACTUAL" -lt 12 ]; then
    echo "FATAL: Env truncated! ${ACTUAL} lines" >&2
    exit 1
fi
echo "[launch] Env: ${ACTUAL} lines OK"

# Kill old daemon
pkill -9 -f 'python.*hindsight-(api|embed)' 2>/dev/null || true
sleep 3
fuser -k ${PORT}/tcp 2>/dev/null || true
sleep 1

# Source and launch
source "$PROFILE_ENV"
exec "$BIN" -p "$PROFILE" daemon start
