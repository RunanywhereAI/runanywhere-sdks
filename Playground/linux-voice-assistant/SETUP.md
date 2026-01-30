# Complete Setup Guide: Linux Voice Assistant

This guide covers building and running the full voice AI stack on Raspberry Pi 5 (or other Linux devices).

**Components:**
- **RunAnywhere Commons** - Core C++ library with OpenAI-compatible server
- **Linux Voice Assistant** - Voice pipeline (Wake Word → VAD → STT → LLM → TTS)
- **Moltbot** (optional) - AI assistant framework with tool execution

---

## Quick Install Options

Choose the installation method that fits your situation:

| Method | Best For | Command |
|--------|----------|---------|
| **One-liner (Fresh)** | New users | `curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/Playground/linux-voice-assistant/scripts/install.sh \| bash` |
| **Add to Moltbot** | Existing Moltbot users | `curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/Playground/linux-voice-assistant/scripts/add-to-moltbot.sh \| bash` |
| **Manual Setup** | Developers, custom configs | Follow this guide |

For detailed Moltbot integration options, see [docs/MOLTBOT_INTEGRATION.md](docs/MOLTBOT_INTEGRATION.md).

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Directory Structure](#directory-structure)
3. [Part 1: Build RunAnywhere Commons](#part-1-build-runanywhere-commons)
4. [Part 2: Build Voice Assistant](#part-2-build-voice-assistant)
5. [Part 3: Download Models](#part-3-download-models)
6. [Part 4: Run the Voice Assistant](#part-4-run-the-voice-assistant)
7. [Part 5: Moltbot Setup (Optional)](#part-5-moltbot-setup-optional)
8. [Running the Full Stack](#running-the-full-stack)
9. [Systemd Services (Auto-start)](#systemd-services-auto-start)
10. [Troubleshooting](#troubleshooting)
11. [Architecture Overview](#architecture-overview)

---

## Prerequisites

### Hardware

**Tested Configuration (Reference):**
- **Device:** Raspberry Pi 5 Model B Rev 1.1
- **RAM:** 8GB (7.9GB usable)
- **Storage:** 128GB microSD (Class 10 / A2 recommended)
- **OS:** Raspberry Pi OS Bookworm (64-bit)
- **Kernel:** 6.12.47+rpt-rpi-2712 aarch64

**Minimum Requirements:**
- Raspberry Pi 5 (4GB RAM minimum, 8GB recommended for larger models)
- USB microphone or audio HAT (e.g., ReSpeaker)
- Speaker (3.5mm jack, HDMI, or USB)
- 32GB+ microSD card (64GB+ recommended for multiple LLM models)

**RAM Requirements by Model:**
| LLM Model | Model Size | RAM @ Runtime | Pi 4GB | Pi 8GB |
|-----------|------------|---------------|--------|--------|
| qwen3-0.6b | 639 MB | ~1.5 GB | ✅ | ✅ |
| lfm-1.2b | 1.25 GB | ~2.5 GB | ✅ | ✅ |
| qwen3-1.7b | 1.83 GB | ~3 GB | ✅ | ✅ |
| llama-3.2-3b | 2.0 GB | ~3.5 GB | ⚠️ | ✅ |
| qwen3-4b | 2.5 GB | ~4.5 GB | ❌ | ✅ |

### Software Dependencies

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install build dependencies
sudo apt install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    libasound2-dev \
    libpulse-dev \
    pkg-config

# Verify cmake version (3.16+ required)
cmake --version
```

### Node.js (For Moltbot - Optional)

```bash
# Moltbot requires Node.js v22+
node --version

# If < v22, install from nodesource:
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# Verify
node --version  # Should be v22.x.x
npm --version
```

---

## Directory Structure

After setup, you'll have:
```
~/
├── runanywhere-sdks/                    # Main SDK repository
│   ├── sdk/runanywhere-commons/
│   │   ├── build-server/                # Server build output
│   │   │   └── tools/runanywhere-server # OpenAI-compatible server
│   │   └── dist/linux/aarch64/          # Built libraries
│   └── Playground/linux-voice-assistant/
│       └── build/
│           └── voice-assistant          # Voice assistant binary
├── moltbot/                             # Moltbot fork (optional)
└── .local/share/runanywhere/Models/     # AI models
    ├── ONNX/
    │   ├── silero-vad/
    │   │   └── silero_vad.onnx
    │   ├── whisper-tiny-en/
    │   │   ├── tiny.en-encoder.int8.onnx
    │   │   ├── tiny.en-decoder.onnx
    │   │   └── tiny.en-tokens.txt
    │   ├── vits-piper-en_US-lessac-medium/
    │   │   ├── en_US-lessac-medium.onnx
    │   │   ├── tokens.txt
    │   │   └── espeak-ng-data/
    │   ├── openwakeword-embedding/      # Wake word shared models (optional)
    │   │   ├── melspectrogram.onnx
    │   │   └── embedding_model.onnx
    │   └── hey-jarvis/                  # Wake word classifier (optional)
    │       └── hey_jarvis_v0.1.onnx
    └── LlamaCpp/
        └── qwen2.5-0.5b-instruct-q4/
            └── qwen2.5-0.5b-instruct-q4_k_m.gguf
```

---

## Part 1: Build RunAnywhere Commons

### 1.1 Clone/Update Repository

```bash
cd ~
# Clone if not exists
if [ ! -d "runanywhere-sdks" ]; then
    git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
fi

cd ~/runanywhere-sdks

# Switch to the correct branch
git checkout smonga/rasp
git pull origin smonga/rasp
```

### 1.2 Download Sherpa-ONNX Dependencies

```bash
cd ~/runanywhere-sdks/sdk/runanywhere-commons

# Download Sherpa-ONNX if not present
if [ ! -d "third_party/sherpa-onnx-linux" ]; then
    ./scripts/linux/download-sherpa-onnx.sh
fi
```

### 1.3 Build the Server

```bash
cd ~/runanywhere-sdks/sdk/runanywhere-commons

# Configure with all backends (LLM + STT/TTS/VAD/WakeWord)
cmake -B build-server \
    -DCMAKE_BUILD_TYPE=Release \
    -DRAC_BUILD_SERVER=ON \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BACKEND_LLAMACPP=ON \
    -DRAC_BACKEND_ONNX=ON

# Build (use -j4 for Pi 5's 4 cores)
cmake --build build-server -j4

# Verify build succeeded
ls -la build-server/tools/runanywhere-server
# Should show executable (~5MB)
```

### 1.4 Test Server Build

```bash
cd ~/runanywhere-sdks/sdk/runanywhere-commons
export LD_LIBRARY_PATH=$PWD/dist/linux/aarch64:$LD_LIBRARY_PATH

# Show help
./build-server/tools/runanywhere-server --help
```

---

## Part 2: Build Voice Assistant

### 2.1 Build the Voice Assistant

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant

# Configure
cmake -B build

# Build
cmake --build build -j4

# Verify
ls -la build/voice-assistant
# Should show executable (~80KB)
```

### 2.2 Test Voice Assistant Build

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant

# Show help
./build/voice-assistant --help

# List audio devices
./build/voice-assistant --list-devices
```

---

## Part 3: Download Models

### 3.1 Required Models (~600MB total)

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant

# Download all required models
./scripts/download-models.sh
```

**Required models:**
| Model | Purpose | Size |
|-------|---------|------|
| Silero VAD | Voice Activity Detection | ~2MB |
| Whisper Tiny English | Speech-to-Text | ~150MB |
| Qwen2.5 0.5B Q4 | Language Model | ~400MB |
| VITS Piper Lessac | Text-to-Speech | ~50MB |

### 3.2 Wake Word Models (Optional, ~20MB)

For "Hey Jarvis" wake word activation:

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant

# Download wake word models
./scripts/download-models.sh --wakeword
```

**Wake word models (3-stage openWakeWord pipeline):**
| Model | Purpose | Size |
|-------|---------|------|
| melspectrogram.onnx | Audio → Mel spectrogram | ~1MB |
| embedding_model.onnx | Mel spectrogram → Embeddings | ~15MB |
| hey_jarvis_v0.1.onnx | Embeddings → Wake word detection | ~5MB |

**Note:** The wake word system uses a 3-stage pipeline:
1. **Melspectrogram**: Converts raw audio to mel frequency features
2. **Embeddings**: Extracts 96-dimensional feature vectors using sliding windows
3. **Classification**: Detects "Hey Jarvis" from the embedding sequence

### 3.3 Manual Model Download (Alternative)

If the script fails, download manually:

```bash
# Create directories
mkdir -p ~/.local/share/runanywhere/Models/{ONNX,LlamaCpp}

# Silero VAD
mkdir -p ~/.local/share/runanywhere/Models/ONNX/silero-vad
wget -O ~/.local/share/runanywhere/Models/ONNX/silero-vad/silero_vad.onnx \
    "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"

# Qwen2.5 0.5B (LLM)
mkdir -p ~/.local/share/runanywhere/Models/LlamaCpp/qwen2.5-0.5b-instruct-q4
wget -O ~/.local/share/runanywhere/Models/LlamaCpp/qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf \
    "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"

# Wake word models (optional) - 3-stage openWakeWord pipeline
mkdir -p ~/.local/share/runanywhere/Models/ONNX/{openwakeword-embedding,hey-jarvis}

# Melspectrogram model (Stage 1: Audio → Mel features)
wget -O ~/.local/share/runanywhere/Models/ONNX/openwakeword-embedding/melspectrogram.onnx \
    "https://github.com/dscripka/openWakeWord/releases/download/v0.5.0/melspectrogram.onnx"

# Embedding model (Stage 2: Mel → Embeddings)
wget -O ~/.local/share/runanywhere/Models/ONNX/openwakeword-embedding/embedding_model.onnx \
    "https://github.com/dscripka/openWakeWord/releases/download/v0.5.0/embedding_model.onnx"

# Wake word classifier (Stage 3: Embeddings → Detection)
wget -O ~/.local/share/runanywhere/Models/ONNX/hey-jarvis/hey_jarvis_v0.1.onnx \
    "https://github.com/dscripka/openWakeWord/releases/download/v0.5.0/hey_jarvis_v0.1.onnx"
```

### 3.4 Verify Models

```bash
# Check model structure
ls -la ~/.local/share/runanywhere/Models/ONNX/
ls -la ~/.local/share/runanywhere/Models/LlamaCpp/

# Check total size
du -sh ~/.local/share/runanywhere/Models/
```

---

## Part 4: Run the Voice Assistant

### 4.1 Test Audio Devices

```bash
# List capture devices (microphones)
arecord -l

# List playback devices (speakers)
aplay -l

# Test recording (5 seconds)
arecord -d 5 -f S16_LE -r 16000 -c 1 /tmp/test.wav

# Test playback
aplay /tmp/test.wav

# Adjust audio levels if needed
alsamixer
```

### 4.2 Run Voice Assistant (Always Listening Mode)

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant

# Run with default audio devices
./build/voice-assistant

# Or specify devices
./build/voice-assistant --input plughw:1,0 --output plughw:0,0
```

### 4.3 Run with Wake Word (Say "Hey Jarvis" to Activate)

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant

# Enable wake word detection
./build/voice-assistant --wakeword

# With specific audio devices
./build/voice-assistant --wakeword --input plughw:1,0 --output plughw:0,0
```

**Behavior:**
- **Without `--wakeword`**: Always listening, responds to any speech
- **With `--wakeword`**: Waits for "Hey Jarvis", then processes the command

### 4.4 Expected Output (Full Pipeline)

When you say "Hey Jarvis, what time is it?", you should see:

```
========================================
Voice Assistant is ready!
Say "Hey Jarvis" to activate.
Press Ctrl+C to exit.
========================================

*** Wake word detected: "Hey Jarvis" (confidence: 0.959) ***
[Listening for command...] [Processing...]
[USER] What time is it?
[ASSISTANT] I'm sorry, but I don't have access to real-time information like the current time.
```

**Pipeline stages in logs:**
```
[WakeWordONNX] DETECTED: 'Hey Jarvis' (confidence=0.959, threshold=0.500)
[VoiceAgent] Processing voice turn
[STT.Component] Transcribing audio
[ONNX.STT] Transcribing 42240 samples at 16000 Hz
[ONNX.STT] Transcription result: "What time is it?"
[LLM.LlamaCpp] Generating with prompt length: 88
[LLM.LlamaCpp] Generation complete: 20 tokens
[TTS.Component] Synthesizing text
[ONNX.TTS] Generated 99840 samples at 22050 Hz (4.53s audio)
```

---

## Part 5: Moltbot Integration (Optional)

Moltbot provides task planning, tool execution, and messaging platform integration. The voice assistant becomes **another channel** in Moltbot, just like WhatsApp, Telegram, or Discord.

### 5.0 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    CHANNELS (I/O Layer)                      │
├─────────────┬─────────────┬─────────────┬───────────────────┤
│  WhatsApp   │  Telegram   │   Discord   │ Voice Assistant   │
│  (text)     │  (text)     │  (text)     │ (STT+TTS+Wake)    │
└──────┬──────┴──────┬──────┴──────┬──────┴─────────┬─────────┘
       │             │             │               │
       └─────────────┴─────────────┴───────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│              MOLTBOT AGENT (Orchestration)                   │
│  • Session management    • Tool execution                    │
│  • Context memory        • Task planning                     │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│              RUNANYWHERE (Inference Layer)                   │
│  • LLM inference (llama.cpp)   • Always running              │
│  • Tool calling support        • OpenAI-compatible API       │
└─────────────────────────────────────────────────────────────┘
```

**Key Concepts:**
- **Voice Assistant = Channel**: Like WhatsApp or Telegram, but with speech I/O
  - STT (Whisper): Converts speech → text
  - TTS (Piper): Converts text → speech
  - Wake word ("Hey Jarvis"): Activates listening
- **Moltbot = Agent**: Orchestrates conversations, executes tools
- **RunAnywhere = Inference**: Always-running LLM backend (local, private, free)

**All channels share the same conversation** - a message from WhatsApp and a voice command both go to the same agent with shared context.

---

### Two Integration Paths

Choose based on your situation:

| Path | Best For | Setup Complexity |
|------|----------|------------------|
| **A: Fresh Install** | New users, clean setup | Simple |
| **B: Existing Moltbot** | Already have Moltbot with WhatsApp/Telegram/etc | Medium |

---

### Path A: Fresh Install (RunAnywhere Fork)

Use this if you're starting fresh or want the pre-configured setup.

#### A.1 Clone RunAnywhere Fork

```bash
cd ~
git clone https://github.com/RunanywhereAI/clawdbot.git moltbot
cd ~/moltbot
```

#### A.2 Install Dependencies

```bash
cd ~/moltbot
npm install
```

#### A.3 Configure for Local AI

```bash
# Create config directory
mkdir -p ~/.clawdbot

# Copy example config (includes RunAnywhere provider)
cp ~/moltbot/examples/runanywhere-local-config.yaml ~/.clawdbot/moltbot.yaml
```

**Edit `~/.clawdbot/moltbot.yaml`:**
```yaml
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
          contextWindow: 4096
          maxTokens: 2048

agents:
  defaults:
    model:
      primary: runanywhere/qwen2.5-0.5b-instruct-q4

gateway:
  bind: loopback
  port: 3000
  auth:
    mode: token
    token: "change-this-to-secure-token"  # IMPORTANT: Change this!
```

#### A.4 Start Moltbot

```bash
cd ~/moltbot
npm run start
```

---

### Path B: Existing Moltbot Installation

Use this if you already have Moltbot running with other channels (WhatsApp, Telegram, etc.) and want to add:
1. **RunAnywhere as LLM backend** (local inference)
2. **Voice assistant as a new channel**

#### B.1 Add RunAnywhere Provider to Config

Copy the sample config or merge with your existing config:

```bash
# Option 1: Copy sample config (review and merge manually)
cp ~/runanywhere-sdks/Playground/linux-voice-assistant/examples/moltbot-runanywhere-config.yaml \
   ~/.clawdbot/runanywhere-provider.yaml

# Option 2: Or use JSON format
cp ~/runanywhere-sdks/Playground/linux-voice-assistant/examples/moltbot-runanywhere-config.json \
   ~/.clawdbot/runanywhere-provider.json
```

#### B.2 Merge with Existing Config

Add this to your existing `~/.clawdbot/moltbot.yaml` or `moltbot.json`:

```yaml
# Add to models.providers section:
models:
  mode: merge  # Keep your existing providers!
  providers:
    # Your existing providers (anthropic, openai, etc.) stay here

    # Add RunAnywhere as a new provider:
    runanywhere:
      baseUrl: "http://localhost:8080/v1"
      apiKey: ""
      api: openai-completions
      models:
        - id: "qwen2.5-0.5b-instruct-q4"
          name: "Qwen2.5 0.5B (Local)"
          costs: { input: 0, output: 0 }  # Free - local!
          contextWindow: 4096
          maxTokens: 2048

# Option: Use RunAnywhere as primary (saves cloud API costs)
agents:
  defaults:
    model:
      primary: runanywhere/qwen2.5-0.5b-instruct-q4
      fallbacks:
        - anthropic/claude-sonnet-4-20250514  # Fallback to cloud if needed
```

#### B.3 Enable Webhooks (Required for Voice Bridge)

Standard Moltbot uses webhooks for programmatic access. Add this to your config:

```yaml
# Enable webhook endpoint for voice bridge
hooks:
  enabled: true
  token: "your-secure-webhook-token"  # Use this in --moltbot-token
  path: "/hooks"  # Default path
```

This enables the `/hooks/agent` endpoint that the voice bridge uses.

#### B.4 Verify Configuration

```bash
# Test that Moltbot recognizes RunAnywhere provider
moltbot doctor

# List available models (should show runanywhere/qwen2.5-0.5b-instruct-q4)
moltbot models list

# Test webhook endpoint (should return 401 without token, not 404)
curl -s http://localhost:3000/hooks/agent
```

---

### 5.1 Voice Bridge Setup

The voice bridge receives transcriptions from the voice assistant and forwards them to Moltbot.

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant

# Start voice bridge (requires npx/tsx)
npx tsx scripts/start-voice-bridge.ts \
    --http-port 8081 \
    --moltbot-url http://localhost:3000 \
    --moltbot-token your-secure-token
```

**Voice Bridge Options:**
| Option | Default | Description |
|--------|---------|-------------|
| `--http-port` | 8081 | HTTP port for voice assistant to connect |
| `--moltbot-url` | http://localhost:3000 | Moltbot gateway URL |
| `--moltbot-token` | (none) | Auth token from Moltbot config |

**API Compatibility:**
The voice bridge automatically detects which Moltbot API to use:

| Moltbot Version | Endpoint | Mode |
|----------------|----------|------|
| RunAnywhere Fork | `/api/chat` | Synchronous (recommended) |
| Standard Moltbot | `/hooks/agent` | Webhook (requires `hooks.enabled: true`) |

### 5.2 Run Voice Assistant with Moltbot

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant

# With Moltbot integration (no wake word)
./build/voice-assistant --moltbot

# With Moltbot AND wake word
./build/voice-assistant --wakeword --moltbot

# Custom Moltbot voice bridge URL
./build/voice-assistant --moltbot --moltbot-url http://localhost:8081
```

### 5.3 Integration Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                 VOICE ASSISTANT (Channel)                    │
│  Microphone → Wake Word → VAD → STT (Whisper)               │
└─────────────────────────┬───────────────────────────────────┘
                          │ HTTP POST /transcription
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    VOICE BRIDGE (:8081)                      │
│  Receives transcriptions, forwards to Moltbot               │
└─────────────────────────┬───────────────────────────────────┘
                          │ HTTP POST /api/chat
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    MOLTBOT (:3000)                           │
│  Agent processing, tool execution, session management       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  WhatsApp   │  │  Telegram   │  │   Voice     │  ← All  │
│  │  Channel    │  │  Channel    │  │  Channel    │  share  │
│  └─────────────┘  └─────────────┘  └─────────────┘  context│
└─────────────────────────┬───────────────────────────────────┘
                          │ HTTP POST /v1/chat/completions
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                 RUNANYWHERE SERVER (:8080)                   │
│  Local LLM inference (Qwen, Llama, etc.)                    │
│  Tool calling support                                        │
└─────────────────────────┬───────────────────────────────────┘
                          │ Response text
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                 VOICE ASSISTANT (Output)                     │
│  TTS (Piper) → Speaker                                      │
└─────────────────────────────────────────────────────────────┘
```

### 5.4 Multi-Channel Sync

When voice assistant is configured as a channel, all channels stay synchronized:

| Event | What Happens |
|-------|--------------|
| Voice: "What's on my todo list?" | Agent responds via TTS AND optionally to other channels |
| WhatsApp: "Add milk to shopping list" | Agent updates list, voice can announce it |
| Telegram: "Remind me in 5 minutes" | Timer set, voice plays reminder when triggered |

**Configuration for channel sync** (in Moltbot config):
```yaml
# Route all channels to same agent
bindings:
  - match: { channel: voice-assistant }
    agentId: main
  - match: { channel: whatsapp }
    agentId: main
  - match: { channel: telegram }
    agentId: main
```

### 5.5 Voice Assistant Channel Extension

The voice assistant is implemented as a **first-class Moltbot channel** at:
```
~/moltbot/extensions/voice-assistant/
```

This extension provides:
- **WebSocket server** (port 8082) for voice client connections
- **Bidirectional communication**: transcriptions IN, speak commands OUT
- **Multi-channel broadcast**: messages from ANY channel are spoken via TTS

**WebSocket Protocol:**

| Direction | Message Type | Purpose |
|-----------|--------------|---------|
| Voice → Moltbot | `transcription` | Send speech-to-text result |
| Voice → Moltbot | `connect` | Identify device and capabilities |
| Voice → Moltbot | `ping` | Keepalive |
| Moltbot → Voice | `speak` | Text to synthesize via TTS |
| Moltbot → Voice | `connected` | Handshake response |
| Moltbot → Voice | `pong` | Keepalive response |

**Example messages:**

```json
// Voice → Moltbot: Send transcription
{
  "type": "transcription",
  "text": "What's the weather like?",
  "sessionId": "main",
  "isFinal": true
}

// Moltbot → Voice: Speak response (from any channel)
{
  "type": "speak",
  "text": "The weather is sunny with a high of 72.",
  "sourceChannel": "telegram",
  "priority": 1
}
```

### 5.6 Voice Bridge Modes

The voice bridge (`scripts/start-voice-bridge.ts`) supports two modes:

**WebSocket Mode (Recommended):**
```bash
npx tsx scripts/start-voice-bridge.ts --mode ws \
    --ws-url ws://localhost:8082 \
    --http-port 8081
```
- Connects to Moltbot voice channel via WebSocket
- Receives speak commands for TTS playback
- Real-time bidirectional communication

**HTTP Mode (Legacy):**
```bash
npx tsx scripts/start-voice-bridge.ts --mode http \
    --moltbot-url http://localhost:3000 \
    --moltbot-token your-token
```
- Forwards transcriptions via HTTP
- No real-time outbound streaming

### 5.7 Message Flow with All Channels

**When you speak to the voice assistant:**
```
Microphone → Wake Word → STT → "What's on my todo list?"
                                        ↓
                              Voice Bridge (WebSocket)
                                        ↓
                              Moltbot Voice Channel
                                        ↓
                              Agent processes message
                                        ↓
                              RunAnywhere LLM inference
                                        ↓
                              Response: "Your list has: milk, eggs"
                                        ↓
                              Voice Channel sends "speak" command
                                        ↓
                              Voice Bridge receives
                                        ↓
                              TTS → Speaker plays response
```

**When someone sends a WhatsApp message:**
```
WhatsApp User: "Add bread to shopping list"
                    ↓
              Moltbot WhatsApp Channel
                    ↓
              Agent processes message
                    ↓
              RunAnywhere LLM inference
                    ↓
              Response: "Added bread to shopping list"
                    ↓
    ┌───────────────┴───────────────┐
    ↓                               ↓
WhatsApp sends                Voice Channel sends
text response                 "speak" command
    ↓                               ↓
WhatsApp User                 Voice Assistant
sees message                  speaks response
```

---

## Running the Full Stack

### Option A: Local-Only Mode (No Moltbot)

Simple standalone mode - voice assistant with local LLM, no external services.

**Single Terminal:**

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant

# Without wake word (always listening)
./build/voice-assistant

# With wake word (say "Hey Jarvis")
./build/voice-assistant --wakeword
```

### Option B: Full Moltbot Integration (4 Components)

Full stack with Moltbot agent - enables tool execution, multi-channel sync, and task planning.

**Start order matters!** Run these in separate terminals:

```
┌──────────────────────────────────────────────────────────────┐
│  Terminal 1: RunAnywhere Server (must start first)           │
│  Terminal 2: Moltbot Gateway                                 │
│  Terminal 3: Voice Bridge                                    │
│  Terminal 4: Voice Assistant                                 │
└──────────────────────────────────────────────────────────────┘
```

**Terminal 1: RunAnywhere Server (Inference Layer)**

```bash
cd ~/runanywhere-sdks/sdk/runanywhere-commons
export LD_LIBRARY_PATH=$PWD/dist/linux/aarch64:$LD_LIBRARY_PATH

./build-server/tools/runanywhere-server \
    --model ~/.local/share/runanywhere/Models/LlamaCpp/qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf \
    --port 8080 \
    --threads 4
```

**Terminal 2: Moltbot Gateway (Agent Layer)**

```bash
cd ~/moltbot
npm run start
```

**Terminal 3: Voice Bridge (Channel Bridge)**

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant

# WebSocket mode (recommended) - connects to Moltbot voice channel
npx tsx scripts/start-voice-bridge.ts \
    --mode ws \
    --ws-url ws://localhost:8082 \
    --http-port 8081

# Or HTTP mode (legacy) - for older Moltbot without voice channel
# npx tsx scripts/start-voice-bridge.ts \
#     --mode http \
#     --moltbot-url http://localhost:3000 \
#     --moltbot-token change-this-to-secure-token
```

**Terminal 4: Voice Assistant (Voice Channel)**

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant

# With Moltbot + Wake Word (recommended)
./build/voice-assistant --wakeword --moltbot

# Or always listening with Moltbot
./build/voice-assistant --moltbot
```

### Option C: Existing Moltbot with Other Channels

If you already have Moltbot running with WhatsApp, Telegram, etc., add voice:

**Terminal 1: Ensure RunAnywhere Server is running**
```bash
# Check if running
curl http://localhost:8080/health

# If not running, start it (see Terminal 1 above)
```

**Terminal 2: Your existing Moltbot** (should already be running)
```bash
# Verify Moltbot sees RunAnywhere provider
moltbot models list | grep runanywhere
```

**Terminal 3: Add Voice Bridge**
```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant
npx tsx scripts/start-voice-bridge.ts \
    --moltbot-url http://localhost:3000 \
    --moltbot-token your-existing-token
```

**Terminal 4: Add Voice Assistant**
```bash
./build/voice-assistant --wakeword --moltbot
```

Now voice joins your existing WhatsApp/Telegram/Discord conversations!

### Test the Server

```bash
# Health check
curl http://localhost:8080/health

# List models
curl http://localhost:8080/v1/models

# Test chat completion
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-0.5b-instruct-q4",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 50
  }'
```

---

## Systemd Services (Auto-start)

### RunAnywhere Server Service

```bash
sudo tee /etc/systemd/system/runanywhere-server.service << 'EOF'
[Unit]
Description=RunAnywhere AI Server
After=network.target

[Service]
Type=simple
User=runanywhere
WorkingDirectory=/home/runanywhere/runanywhere-sdks/sdk/runanywhere-commons
Environment=LD_LIBRARY_PATH=/home/runanywhere/runanywhere-sdks/sdk/runanywhere-commons/dist/linux/aarch64
ExecStart=/home/runanywhere/runanywhere-sdks/sdk/runanywhere-commons/build-server/tools/runanywhere-server --model /home/runanywhere/.local/share/runanywhere/Models/LlamaCpp/qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf --port 8080 --threads 4
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Voice Assistant Service

```bash
sudo tee /etc/systemd/system/voice-assistant.service << 'EOF'
[Unit]
Description=Linux Voice Assistant
After=network.target runanywhere-server.service

[Service]
Type=simple
User=runanywhere
WorkingDirectory=/home/runanywhere/runanywhere-sdks/Playground/linux-voice-assistant
ExecStart=/home/runanywhere/runanywhere-sdks/Playground/linux-voice-assistant/build/voice-assistant --wakeword
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Enable Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable runanywhere-server
sudo systemctl enable voice-assistant

# Start services
sudo systemctl start runanywhere-server
sudo systemctl start voice-assistant

# Check status
sudo systemctl status runanywhere-server
sudo systemctl status voice-assistant

# View logs
journalctl -u runanywhere-server -f
journalctl -u voice-assistant -f
```

---

## Troubleshooting

### Build Errors

```bash
# Clear build cache and rebuild
cd ~/runanywhere-sdks/sdk/runanywhere-commons
rm -rf build-server
cmake -B build-server -DCMAKE_BUILD_TYPE=Release -DRAC_BUILD_SERVER=ON -DRAC_BACKEND_LLAMACPP=ON -DRAC_BACKEND_ONNX=ON
cmake --build build-server -j4
```

### Library Not Found

```bash
# Option 1: Use dist directory (after build-linux.sh --shared)
export LD_LIBRARY_PATH="$HOME/runanywhere-sdks/sdk/runanywhere-commons/dist/linux/aarch64:$LD_LIBRARY_PATH"

# Option 2: Use build directory (after cmake build)
export LD_LIBRARY_PATH="$HOME/runanywhere-sdks/sdk/runanywhere-commons/build/lib:$LD_LIBRARY_PATH"

# Add to ~/.bashrc for persistence
echo 'export LD_LIBRARY_PATH="$HOME/runanywhere-sdks/sdk/runanywhere-commons/build/lib:$LD_LIBRARY_PATH"' >> ~/.bashrc
source ~/.bashrc
```

### No Audio Input

```bash
# Check if user is in audio group
groups
# If 'audio' not listed:
sudo usermod -a -G audio $USER
# Logout and login again
```

### Audio Device Busy

If you see "Cannot open audio device: Device or resource busy":

```bash
# Check what's using the audio device
fuser -v /dev/snd/*

# PipeWire/PulseAudio may be holding the device
# Try a different audio card - list available:
arecord -l

# Use a specific card (e.g., card 3 for USB PnP Sound Device)
./build/voice-assistant --wakeword --input plughw:3,0 --output plughw:2,0

# Or use the device name format:
./build/voice-assistant --wakeword --input plughw:CARD=Device,DEV=0 --output plughw:CARD=Audio,DEV=0
```

### Multiple USB Audio Devices

If you have multiple USB audio devices (microphone + speaker):

```bash
# List all audio devices
arecord -l  # Input devices
aplay -l    # Output devices

# Example output:
# card 2: Audio [USB Audio], device 0: USB Audio [USB Audio]
# card 3: Device [USB PnP Sound Device], device 0: USB Audio [USB Audio]

# Use specific devices:
./build/voice-assistant --wakeword \
    --input plughw:3,0 \
    --output plughw:2,0
```

### Out of Memory

```bash
# Check memory
free -h

# Create swap if needed (2GB)
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent
echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
```

### Wake Word Not Detecting

```bash
# Verify all 3 wake word models exist
ls -la ~/.local/share/runanywhere/Models/ONNX/openwakeword-embedding/
# Should contain: melspectrogram.onnx, embedding_model.onnx

ls -la ~/.local/share/runanywhere/Models/ONNX/hey-jarvis/
# Should contain: hey_jarvis_v0.1.onnx

# If missing, download them
cd ~/runanywhere-sdks/Playground/linux-voice-assistant
./scripts/download-models.sh --wakeword

# Check detection threshold (default 0.5)
# Speak clearly and close to the microphone
# Detection requires ~3-4 seconds of audio to accumulate embeddings
```

### Server Connection Issues

```bash
# Check if server is listening
ss -tlnp | grep 8080

# Check firewall
sudo ufw status
sudo ufw allow 8080/tcp  # If using UFW
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      Raspberry Pi 5                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Voice Assistant                               │  │
│  │                                                            │  │
│  │  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌────────┐  │  │
│  │  │ WakeWord│ -> │   VAD   │ -> │   STT   │ -> │  LLM   │  │  │
│  │  │(Jarvis) │    │(Silero) │    │(Whisper)│    │ (Qwen) │  │  │
│  │  └─────────┘    └─────────┘    └─────────┘    └────┬───┘  │  │
│  │       ↑                                            │      │  │
│  │       │                                            ▼      │  │
│  │  ┌─────────┐                               ┌─────────┐    │  │
│  │  │   Mic   │                               │   TTS   │    │  │
│  │  └─────────┘                               │ (Piper) │    │  │
│  │                                            └────┬────┘    │  │
│  │                                                 │         │  │
│  │                                            ┌────▼────┐    │  │
│  │                                            │ Speaker │    │  │
│  │                                            └─────────┘    │  │
│  └───────────────────────────────────────────────────────────┘  │
│                          │                                       │
│                          ▼ (optional)                            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │          RunAnywhere Server (:8080)                        │  │
│  │   • /v1/chat/completions (OpenAI-compatible)              │  │
│  │   • /v1/models                                             │  │
│  │   • Tool calling support                                   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                          │                                       │
│                          ▼ (optional)                            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Moltbot (:3000)                                │  │
│  │   • Task planning & execution                              │  │
│  │   • Tool calling (shell, fs, gpio)                         │  │
│  │   • Messaging platform integration                         │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Performance Expectations

| Component | Metric | Raspberry Pi 5 |
|-----------|--------|----------------|
| Server Startup | Model load | ~5-10s |
| Wake Word | Detection latency | ~50-100ms |
| VAD | Detection latency | ~10-20ms |
| STT | Transcription | ~300-500ms |
| LLM | Tokens/second | ~5-10 tok/s |
| TTS | Synthesis | ~100-200ms |
| Full Pipeline | End-to-end | ~2-3s per turn |
| Memory Usage | Total | ~1-2GB |
| Power | System | ~5-8W |

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `./build/voice-assistant` | Run voice assistant (always listening) |
| `./build/voice-assistant --wakeword` | Run with "Hey Jarvis" wake word |
| `./build/voice-assistant --moltbot` | Run with Moltbot integration |
| `./build/voice-assistant --wakeword --moltbot` | Wake word + Moltbot |
| `./build/voice-assistant --moltbot-url URL` | Custom Moltbot voice bridge URL |
| `./build/voice-assistant --list-devices` | List audio devices |
| `./scripts/download-models.sh` | Download required models |
| `./scripts/download-models.sh --wakeword` | Download wake word models |
| `npx tsx scripts/start-voice-bridge.ts --mode ws` | Start voice bridge (WebSocket mode) |
| `npx tsx scripts/start-voice-bridge.ts --mode http` | Start voice bridge (HTTP mode) |
| `curl http://localhost:8080/health` | Check RunAnywhere server health |
| `curl http://localhost:8080/v1/models` | List available models |
| `curl http://localhost:8081/health` | Check voice bridge health |
| `curl http://localhost:8081/speak` | Get next message to speak (polling) |
| `curl -X POST http://localhost:8081/transcription -d '{"text":"hello"}'` | Test voice bridge |
