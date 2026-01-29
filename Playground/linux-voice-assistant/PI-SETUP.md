# Raspberry Pi Setup & Run Instructions

**Target:** Raspberry Pi 5 with repositories already cloned
**Date:** January 28, 2026

---

## Repository Information

### 1. RunAnywhere SDKs

| Property | Value |
|----------|-------|
| **Repo** | `RunanywhereAI/runanywhere-sdks` |
| **Branch** | `smonga/rasp` |
| **Local Path** | `~/runanywhere-sdks` |

**Recent Changes:**
- `37337630` - docs: Add Raspberry Pi setup and run instructions
- `96c6b792` - feat(server): Add OpenAI-compatible HTTP server with Commons tool calling
- `8ce9bb9c` - Merge tool-calling branch into server
- Voice assistant pipeline (VAD → STT → LLM → TTS)
- OpenAI-compatible HTTP server (`/v1/chat/completions`)

**Key Components:**
```
sdk/runanywhere-commons/
├── src/server/          # OpenAI-compatible HTTP server
├── tools/               # runanywhere-server CLI
└── dist/linux/aarch64/  # Built libraries

playground/linux-voice-assistant/
├── voice_pipeline.cpp   # Voice AI pipeline
├── audio_capture.cpp    # ALSA microphone
├── audio_playback.cpp   # ALSA speaker
└── PI-SETUP.md          # This file
```

### 2. Moltbot (Clawdbot Fork)

| Property | Value |
|----------|-------|
| **Repo** | `RunanywhereAI/clawdbot` |
| **Branch** | `main` |
| **Local Path** | `~/clawdbot` (optional) |

**Recent Changes:**
- `1fae7dcdf` - feat(runanywhere): Add RunAnywhere extension for local AI inference

**Key Components:**
```
extensions/runanywhere/
├── src/index.ts         # Extension entry point
├── src/voice-bridge.ts  # Voice assistant ↔ Moltbot bridge
└── README.md            # Extension documentation

examples/
└── runanywhere-local-config.yaml  # Moltbot config for local AI
```

---

## Quick Start (If Already Built)

### Option A: Voice Assistant Only

```bash
cd ~/runanywhere-sdks
git pull origin smonga/rasp

cd playground/linux-voice-assistant
./build/voice-assistant
```

### Option B: Voice Assistant + Server

**Terminal 1 - Server:**
```bash
cd ~/runanywhere-sdks/sdk/runanywhere-commons
./build-server/tools/runanywhere-server \
    --model ~/.local/share/runanywhere/Models/LlamaCpp/qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf \
    --port 8080
```

**Terminal 2 - Voice Assistant:**
```bash
cd ~/runanywhere-sdks/playground/linux-voice-assistant
./build/voice-assistant
```

---

## Full Setup Instructions

### Prerequisites Check

```bash
# 1. Verify runanywhere-sdks branch
cd ~/runanywhere-sdks
git branch --show-current
# Should show: smonga/rasp

# 2. Pull latest changes
git pull origin smonga/rasp

# 3. Check if models exist
ls -la ~/.local/share/runanywhere/Models/
```

Expected model structure:
```
~/.local/share/runanywhere/Models/
├── ONNX/
│   ├── silero-vad/silero_vad.onnx
│   ├── whisper-tiny-en/
│   ├── vits-piper-en_US-lessac-medium/
│   ├── openwakeword/embedding_model.onnx    # Optional (wake word)
│   └── hey-jarvis/hey_jarvis_v0.1.onnx      # Optional (wake word)
└── LlamaCpp/
    └── qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

---

### Step 1: Install Build Dependencies

```bash
sudo apt update
sudo apt install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    libasound2-dev \
    libpulse-dev \
    pkg-config
```

---

### Step 2: Build RunAnywhere Commons

```bash
cd ~/runanywhere-sdks/sdk/runanywhere-commons

# Download Sherpa-ONNX if not already present
if [ ! -d "third_party/sherpa-onnx-linux" ]; then
    ./scripts/linux/download-sherpa-onnx.sh
fi

# Build with server and all backends
./scripts/build-linux.sh --shared

# Verify build
ls -la dist/linux/aarch64/
# Should see: librac_commons.so, librac_backend_*.so
```

---

### Step 3: Build Voice Assistant

```bash
cd ~/runanywhere-sdks/playground/linux-voice-assistant

# Configure
cmake -B build

# Build
cmake --build build -j4

# Verify
ls -la build/voice-assistant
```

---

### Step 4: Build RunAnywhere Server

```bash
cd ~/runanywhere-sdks/sdk/runanywhere-commons

# Build with server enabled
cmake -B build-server \
    -DCMAKE_BUILD_TYPE=Release \
    -DRAC_BUILD_SERVER=ON \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BACKEND_LLAMACPP=ON \
    -DRAC_BACKEND_ONNX=ON

cmake --build build-server -j4

# Verify
ls -la build-server/tools/runanywhere-server
```

---

### Step 5: Download Models (if not present)

```bash
cd ~/runanywhere-sdks/playground/linux-voice-assistant

# Download required models
./scripts/download-models.sh

# Optional: Download wake word models for "Hey Jarvis" activation
./scripts/download-models.sh --wakeword
```

Or manually download:

```bash
# Create directories
mkdir -p ~/.local/share/runanywhere/Models/{ONNX,LlamaCpp}

# Silero VAD
mkdir -p ~/.local/share/runanywhere/Models/ONNX/silero-vad
wget -O ~/.local/share/runanywhere/Models/ONNX/silero-vad/silero_vad.onnx \
    https://github.com/snakers4/silero-vad/raw/master/files/silero_vad.onnx

# Qwen2.5 0.5B (LLM)
mkdir -p ~/.local/share/runanywhere/Models/LlamaCpp/qwen2.5-0.5b-instruct-q4
wget -O ~/.local/share/runanywhere/Models/LlamaCpp/qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf \
    https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf

# Optional: openWakeWord models for "Hey Jarvis"
mkdir -p ~/.local/share/runanywhere/Models/ONNX/{openwakeword,hey-jarvis}
wget -O ~/.local/share/runanywhere/Models/ONNX/openwakeword/embedding_model.onnx \
    https://github.com/dscripka/openWakeWord/releases/download/v0.5.0/embedding_model.onnx
wget -O ~/.local/share/runanywhere/Models/ONNX/hey-jarvis/hey_jarvis_v0.1.onnx \
    https://github.com/dscripka/openWakeWord/releases/download/v0.5.0/hey_jarvis_v0.1.onnx
```

---

### Step 6: Run Voice Assistant

```bash
cd ~/runanywhere-sdks/playground/linux-voice-assistant

# List audio devices first
./build/voice-assistant --list-devices

# Run with default devices (always listening)
./build/voice-assistant

# Run with wake word detection (say "Hey Jarvis" to activate)
./build/voice-assistant --wakeword

# Specify audio devices
./build/voice-assistant --input plughw:1,0 --output plughw:0,0

# Combined: wake word + specific devices
./build/voice-assistant --wakeword --input plughw:1,0 --output plughw:0,0
```

**Controls:**
- Without `--wakeword`: Speak anytime to interact
- With `--wakeword`: Say "Hey Jarvis" to activate, then speak
- `Ctrl+C` to exit

---

### Step 7: Run RunAnywhere Server

In a separate terminal:

```bash
cd ~/runanywhere-sdks/sdk/runanywhere-commons

# Start server
./build-server/tools/runanywhere-server \
    --model ~/.local/share/runanywhere/Models/LlamaCpp/qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf \
    --port 8080 \
    --threads 4

# Test it
curl http://localhost:8080/health
curl http://localhost:8080/v1/models
```

---

## Moltbot Integration (Optional)

If you want to use Moltbot with local inference:

### Clone Moltbot Fork

```bash
cd ~
git clone https://github.com/RunanywhereAI/clawdbot.git moltbot
cd moltbot
```

### Configure for Local AI

```bash
# Copy the RunAnywhere config
cp examples/runanywhere-local-config.yaml ~/.moltbot/config.yaml

# Or manually add to existing config:
cat >> ~/.moltbot/config.yaml << 'EOF'
models:
  mode: merge
  providers:
    runanywhere:
      baseUrl: "http://localhost:8080/v1"
      apiKey: ""
      api: openai-completions
      models:
        - id: "qwen2.5-0.5b-instruct-q4"
          name: "Qwen2.5 0.5B (Local)"
          reasoning: false
          input: ["text"]
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
          contextWindow: 4096
          maxTokens: 2048
EOF
```

### Start Moltbot

```bash
# Make sure runanywhere-server is running first!
cd ~/moltbot
npm install
npm run start
```

---

## Troubleshooting

### No audio input detected
```bash
# Check ALSA devices
arecord -l
aplay -l

# Test recording
arecord -d 5 -f S16_LE -r 16000 -c 1 test.wav
aplay test.wav

# Adjust levels
alsamixer
```

### Permission denied for audio
```bash
sudo usermod -a -G audio $USER
# Then logout and login again
```

### Library not found errors
```bash
# Add library path
export LD_LIBRARY_PATH=~/runanywhere-sdks/sdk/runanywhere-commons/dist/linux/aarch64:$LD_LIBRARY_PATH
```

### Out of memory
```bash
# Check memory
free -h

# Close other applications
# Consider using swap
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

---

## Quick Test Commands

```bash
# Test server health
curl http://localhost:8080/health

# Test models endpoint
curl http://localhost:8080/v1/models

# Test chat completion
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-0.5b-instruct-q4",
    "messages": [{"role": "user", "content": "Hello, what can you do?"}],
    "max_tokens": 100
  }'
```

---

## Running as a Service (Optional)

Create systemd service for auto-start:

```bash
sudo tee /etc/systemd/system/runanywhere-server.service << 'EOF'
[Unit]
Description=RunAnywhere AI Server
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/runanywhere-sdks/sdk/runanywhere-commons
Environment=LD_LIBRARY_PATH=/home/pi/runanywhere-sdks/sdk/runanywhere-commons/dist/linux/aarch64
ExecStart=/home/pi/runanywhere-sdks/sdk/runanywhere-commons/build-server/tools/runanywhere-server --model /home/pi/.local/share/runanywhere/Models/LlamaCpp/qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf --port 8080
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable runanywhere-server
sudo systemctl start runanywhere-server
sudo systemctl status runanywhere-server
```

---

## Expected Performance

| Metric | Raspberry Pi 5 |
|--------|----------------|
| STT Latency | ~300-500ms |
| LLM Tokens/sec | ~5-10 tok/s |
| TTS Latency | ~100-200ms |
| Full Pipeline | ~2-3s per turn |
| Power | ~5W |

---

## Files Summary

| Component | Location |
|-----------|----------|
| Voice Assistant | `~/runanywhere-sdks/playground/linux-voice-assistant/build/voice-assistant` |
| Server | `~/runanywhere-sdks/sdk/runanywhere-commons/build-server/tools/runanywhere-server` |
| Libraries | `~/runanywhere-sdks/sdk/runanywhere-commons/dist/linux/aarch64/` |
| Models | `~/.local/share/runanywhere/Models/` |
| Moltbot Config | `examples/runanywhere-local-config.yaml` |
| Moltbot Extension | `extensions/runanywhere/` |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Raspberry Pi 5                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │            Voice Assistant                           │   │
│  │  Mic → VAD → STT → [LLM] → TTS → Speaker            │   │
│  │         (Silero) (Whisper) (Qwen) (Piper)           │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │          RunAnywhere Server (:8080)                  │   │
│  │  • /v1/chat/completions (OpenAI-compatible)         │   │
│  │  • /v1/models                                        │   │
│  │  • Tool calling support                              │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Moltbot (Optional)                      │   │
│  │  • Task planning                                     │   │
│  │  • Tool execution (shell, fs, gpio)                  │   │
│  │  • Telegram/Discord/etc integration                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```
