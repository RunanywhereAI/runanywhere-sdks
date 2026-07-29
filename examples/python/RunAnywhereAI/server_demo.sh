#!/usr/bin/env bash
# Start the SDK's OpenAI-compatible server and send one chat completion.
set -euo pipefail

cd "$(dirname "$0")"
MODEL="${1:-smollm2-135m}"
PORT="${PORT:-8000}"
PYTHON=".venv/bin/python"

[ -x "$PYTHON" ] || { echo "missing venv — see README.md" >&2; exit 1; }

"$PYTHON" -m runanywhere serve --port "$PORT" --default-llm "$MODEL" &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 120); do
    curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
    sleep 1
done
curl -sf "http://127.0.0.1:$PORT/health" >/dev/null || { echo "server did not come up" >&2; exit 1; }

curl -s "http://127.0.0.1:$PORT/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "'"$MODEL"'",
        "messages": [{"role": "user", "content": "Say hello in five words or fewer."}],
        "max_tokens": 32
    }'
echo
