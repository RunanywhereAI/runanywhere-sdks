#!/bin/bash
# Start the complete RunAnywhere + Moltbot Voice Assistant stack
# This starts: 1) LLM Server  2) Moltbot Gateway  3) Voice Bridge  4) Voice Assistant

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="$HOME/runanywhere-sdks"
MOLTBOT_DIR="$HOME/moltbot"
MODEL_DIR="$HOME/.local/share/runanywhere/Models"

# Find the default LLM model
find_default_model() {
    # Preference order: qwen3-1.7b > qwen3-0.6b > lfm-1.2b > llama-3.2-3b > qwen3-4b
    for model in qwen3-1.7b qwen3-0.6b lfm-1.2b llama-3.2-3b qwen3-4b qwen2.5-0.5b-instruct-q4; do
        local model_path="$MODEL_DIR/LlamaCpp/$model"
        if [ -d "$model_path" ]; then
            local gguf=$(ls "$model_path"/*.gguf 2>/dev/null | head -1)
            if [ -n "$gguf" ]; then
                echo "$gguf"
                return 0
            fi
        fi
    done
    return 1
}

cleanup() {
    echo ""
    echo "Shutting down..."
    kill $SERVER_PID $MOLTBOT_PID $BRIDGE_PID 2>/dev/null
    exit 0
}
trap cleanup INT TERM

# Find runanywhere-server binary
SERVER_BIN="$SDK_DIR/sdk/runanywhere-commons/build-server/tools/runanywhere-server"
if [ ! -x "$SERVER_BIN" ]; then
    echo "Error: runanywhere-server not found at $SERVER_BIN"
    echo "Please build it first: cd $SDK_DIR/sdk/runanywhere-commons && mkdir build-server && cd build-server && cmake .. -DBUILD_SERVER=ON && make -j\$(nproc)"
    exit 1
fi

# Find LLM model
MODEL_PATH=$(find_default_model)
if [ -z "$MODEL_PATH" ]; then
    echo "Error: No LLM model found. Please run: $SCRIPT_DIR/scripts/download-models.sh"
    exit 1
fi

echo "==================================="
echo "  Starting RunAnywhere Stack"
echo "==================================="
echo ""
echo "LLM Model: $(basename "$MODEL_PATH")"
echo ""

# 1. Start RunAnywhere Server (LLM inference)
echo "[1/4] Starting LLM server on port 8080..."
$SERVER_BIN --model "$MODEL_PATH" --port 8080 --threads 4 &
SERVER_PID=$!
sleep 3

# Check if server started
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "Error: Failed to start LLM server"
    exit 1
fi

# 2. Start Moltbot gateway
echo "[2/4] Starting Moltbot gateway on port 18789..."
cd "$MOLTBOT_DIR"
pnpm moltbot gateway --port 18789 &
MOLTBOT_PID=$!
sleep 3

# 3. Start voice bridge
echo "[3/4] Starting voice bridge..."
cd "$SCRIPT_DIR"
npx tsx scripts/start-voice-bridge.ts --websocket &
BRIDGE_PID=$!
sleep 2

# 4. Start voice assistant
echo "[4/4] Starting voice assistant..."
echo ""
echo "==================================="
echo "  Voice Assistant Ready!"
echo "  Say \"Hey Jarvis\" to activate"
echo "==================================="
echo ""

./build/voice-assistant --moltbot --wakeword

cleanup
