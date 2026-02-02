# Raspberry Pi Moltbot Voice Pipeline

**Target Device:** Raspberry Pi 5 (8GB)
**Goal:** Complete on-device AI assistant with voice, Telegram, and WhatsApp channels powered by local LLM inference
**Date:** 2026-02-02
**Status:** Telegram configured, RunAnywhere server running, troubleshooting LLM connection

---

## Overview

This document describes the complete voice AI pipeline implementation on Raspberry Pi, integrating:

1. **RunAnywhere SDKs** - On-device AI inference (LLM, STT, TTS, VAD)
2. **RunAnywhere Server** - OpenAI-compatible HTTP API for chat completions
3. **Moltbot** - Multi-channel AI assistant gateway (Telegram, WhatsApp, Voice, etc.)
4. **Linux Voice Assistant** - Wake word + voice pipeline client

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           USER INTERFACES                                    │
├──────────────────┬──────────────────┬──────────────────┬───────────────────┤
│     Telegram     │     WhatsApp     │  Voice Assistant │    Other Channels │
│   @claw_san_bot  │   +15858314795   │  "Hey Jarvis"    │   Discord, etc.   │
└────────┬─────────┴────────┬─────────┴────────┬─────────┴─────────┬─────────┘
         │                  │                  │                   │
         └──────────────────┴──────────────────┴───────────────────┘
                                     │
                    ┌────────────────▼────────────────┐
                    │       MOLTBOT GATEWAY           │
                    │       Port 18789 (HTTP/WS)      │
                    │                                 │
                    │  - Channel routing              │
                    │  - Agent orchestration          │
                    │  - Session management           │
                    │  - Message delivery             │
                    └────────────────┬────────────────┘
                                     │
                    ┌────────────────▼────────────────┐
                    │     RUNANYWHERE SERVER          │
                    │       Port 8080 (HTTP)          │
                    │                                 │
                    │  - OpenAI-compatible API        │
                    │  - /v1/chat/completions         │
                    │  - /v1/models                   │
                    │  - Streaming support            │
                    └────────────────┬────────────────┘
                                     │
                    ┌────────────────▼────────────────┐
                    │     RUNANYWHERE COMMONS         │
                    │       (C++ Core Library)        │
                    │                                 │
                    │  - LlamaCPP backend (LLM)       │
                    │  - Sherpa-ONNX backend (STT/TTS)│
                    │  - Voice Agent pipeline         │
                    └─────────────────────────────────┘
```

---

## Project Locations

### Primary Directories

| Component | Location | Description |
|-----------|----------|-------------|
| **Moltbot** | `/home/runanywhere/moltbot` | AI assistant gateway (Node.js/TypeScript) |
| **RunAnywhere SDKs** | `/home/runanywhere/runanywhere-sdks` | Cross-platform AI SDKs |
| **RunAnywhere Commons** | `/home/runanywhere/runanywhere-sdks/sdk/runanywhere-commons` | C++ core library |
| **Linux Voice Assistant** | `/home/runanywhere/runanywhere-sdks/Playground/linux-voice-assistant` | Voice client application |
| **Moltbot Config** | `~/.clawdbot/moltbot.json` | Moltbot configuration |
| **Agent Sessions** | `~/.clawdbot/agents/main/sessions` | Agent conversation history |
| **Auth Profiles** | `~/.clawdbot/agents/main/agent/auth-profiles.json` | Provider authentication |
| **AI Models** | `~/.local/share/runanywhere/Models` | Downloaded LLM/STT/TTS models |
| **RunAnywhere Binaries** | `~/.local/runanywhere/bin` | Compiled server and voice assistant |
| **RunAnywhere Libraries** | `~/.local/runanywhere/lib` | Shared libraries (.so files) |

### Moltbot Structure

```
/home/runanywhere/moltbot/
├── src/
│   ├── telegram/              # Telegram channel implementation
│   ├── channels/              # Channel routing and plugins
│   ├── agents/                # AI agent logic
│   ├── config/                # Configuration schemas
│   └── gateway/               # Gateway server
├── extensions/
│   ├── telegram/              # Telegram extension
│   ├── voice-assistant/       # Voice channel extension
│   ├── voice-call/            # Voice call extension
│   └── ...                    # Other channel extensions
├── bin/
│   └── moltbot.js             # CLI entry point
└── package.json
```

### RunAnywhere SDKs Structure

```
/home/runanywhere/runanywhere-sdks/
├── sdk/
│   ├── runanywhere-commons/   # C++ core library
│   │   ├── src/
│   │   │   ├── backends/
│   │   │   │   ├── llamacpp/  # LLM inference backend
│   │   │   │   └── onnx/      # Sherpa-ONNX backend (STT/TTS/VAD)
│   │   │   └── server/        # HTTP server implementation
│   │   ├── build-server/      # Server build output
│   │   │   └── tools/
│   │   │       └── runanywhere-server  # Server binary
│   │   ├── include/rac/       # C API headers
│   │   └── scripts/
│   │       └── build-linux.sh # Linux build script
│   ├── runanywhere-swift/     # iOS/macOS SDK
│   ├── runanywhere-kotlin/    # Android SDK
│   └── runanywhere-flutter/   # Flutter SDK
├── Playground/
│   └── linux-voice-assistant/ # Voice assistant application
│       ├── main.cpp           # Entry point
│       ├── voice_pipeline.cpp # VAD → STT → LLM → TTS orchestration
│       ├── audio_capture.cpp  # ALSA microphone input
│       ├── audio_playback.cpp # ALSA speaker output
│       ├── build.sh           # Build script
│       └── scripts/
│           └── download-models.sh
└── examples/                  # Demo apps for each platform
```

---

## Component Details

### 1. RunAnywhere Commons (C++ Core)

**Location:** `/home/runanywhere/runanywhere-sdks/sdk/runanywhere-commons`

The unified C/C++ core that powers all platform SDKs:

- **LlamaCPP Backend**: LLM inference with GGUF models
- **Sherpa-ONNX Backend**: STT (Whisper), TTS (Piper), VAD (Silero)
- **HTTP Server**: OpenAI-compatible REST API
- **Voice Agent**: Orchestrated STT → LLM → TTS pipeline

**Build Output:**
```
~/.local/runanywhere/
├── bin/
│   ├── runanywhere-server     # HTTP server binary
│   └── voice-assistant        # Voice client binary
└── lib/
    ├── librac_commons.so
    ├── librac_backend_onnx.so
    ├── librac_backend_llamacpp.so
    ├── libsherpa-onnx-c-api.so
    └── libonnxruntime.so
```

### 2. RunAnywhere Server

**Location:** `~/.local/runanywhere/bin/runanywhere-server`

OpenAI-compatible HTTP server for local LLM inference:

**Endpoints:**
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/models` | GET | List available models |
| `/v1/chat/completions` | POST | Chat completion (streaming/non-streaming) |
| `/health` | GET | Health check |

**Configuration:**
```bash
runanywhere-server \
  --model <path-to-gguf>  # Required: GGUF model file
  --host 0.0.0.0          # Bind address
  --port 8080             # HTTP port
  --threads 4             # CPU threads
  --context 16384         # Context window size
```

### 3. Moltbot Gateway

**Location:** `/home/runanywhere/moltbot`

Multi-channel AI assistant that connects to various messaging platforms:

**Channels:**
- Telegram (configured)
- WhatsApp (configured, needs re-login)
- Voice Assistant (extension available)
- Discord, Slack, Signal, iMessage, etc.

**Key Files:**
| File | Purpose |
|------|---------|
| `~/.clawdbot/moltbot.json` | Main configuration |
| `~/.clawdbot/agents/main/agent/auth-profiles.json` | Provider credentials |
| `~/.clawdbot/agents/main/sessions/*.jsonl` | Conversation history |

### 4. Linux Voice Assistant

**Location:** `/home/runanywhere/runanywhere-sdks/Playground/linux-voice-assistant`

Standalone voice assistant application:

- **Wake Word**: "Hey Jarvis" activation
- **STT**: Whisper transcription
- **TTS**: Piper synthesis
- **Moltbot Integration**: WebSocket connection for multi-channel sync

---

## AI Models

**Location:** `~/.local/share/runanywhere/Models/`

### LLM Models (LlamaCpp)

| Model | Size | Path |
|-------|------|------|
| LFM 2.5 1.2B (Q8) | ~1.2GB | `LlamaCpp/lfm2.5-1.2b/LFM2.5-1.2B-Instruct-Q8_0.gguf` |
| Qwen3 1.7B (Q8) | ~1.8GB | `LlamaCpp/qwen3-1.7b/Qwen3-1.7B-Q8_0.gguf` |
| Qwen 2.5 0.5B (Q4) | ~400MB | `LlamaCpp/qwen2.5-0.5b-instruct-q4/*.gguf` |

### Speech Models (ONNX)

| Model | Size | Path |
|-------|------|------|
| Silero VAD | ~2MB | `ONNX/silero-vad/` |
| Whisper Tiny EN | ~150MB | `ONNX/whisper-tiny-en/` |
| Piper TTS | ~50MB | `ONNX/vits-piper-en-us/` |

---

## Configuration

### Moltbot Configuration (`~/.clawdbot/moltbot.json`)

```json
{
  "models": {
    "providers": {
      "runanywhere": {
        "baseUrl": "http://127.0.0.1:8080/v1",
        "apiKey": "local",
        "api": "openai-completions",
        "models": [
          {
            "id": "LFM2.5-1.2B-Instruct-Q8_0",
            "name": "Lobster Brain (LFM 1.2B)",
            "contextWindow": 16384,
            "maxTokens": 4096
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "runanywhere/LFM2.5-1.2B-Instruct-Q8_0"
      },
      "promptMode": "local"
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "<your-telegram-bot-token>",
      "dmPolicy": "allowlist",
      "allowFrom": [<your-telegram-user-id>]
    }
  },
  "gateway": {
    "mode": "local"
  }
}
```

### Auth Profiles (`~/.clawdbot/agents/main/agent/auth-profiles.json`)

```json
{
  "version": 2,
  "profiles": {
    "runanywhere:default": {
      "type": "api_key",
      "provider": "runanywhere",
      "key": "local"
    }
  }
}
```

---

## Setup Instructions

### Prerequisites

- Raspberry Pi 5 (8GB recommended)
- Raspberry Pi OS 64-bit (Bookworm)
- Node.js 22+
- pnpm package manager
- Build tools: `build-essential cmake git curl wget`

### Step 1: Install RunAnywhere Binaries

```bash
# Download and install pre-built binaries
curl -fsSL https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/voice-assistant-v0.1.0/runanywhere-voice-assistant-linux-aarch64.tar.gz | tar -xzf - -C /tmp
cd /tmp/runanywhere-release && ./install.sh

# Fix library symlinks (REQUIRED)
cd ~/.local/runanywhere/lib && for lib in *.so; do ln -sf "$lib" "${lib}.1"; done
```

### Step 2: Download LLM Model

```bash
mkdir -p ~/.local/share/runanywhere/Models/LlamaCpp/lfm2.5-1.2b
curl -L -o ~/.local/share/runanywhere/Models/LlamaCpp/lfm2.5-1.2b/LFM2.5-1.2B-Instruct-Q8_0.gguf \
  "https://huggingface.co/lmstudio-community/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q8_0.gguf"
```

### Step 3: Clone and Build Moltbot

```bash
git clone https://github.com/RunanywhereAI/clawdbot.git ~/moltbot
cd ~/moltbot
npm install -g pnpm
pnpm install
pnpm build
```

### Step 4: Configure Moltbot

```bash
# Set gateway mode
pnpm moltbot config set gateway.mode local

# Configure RunAnywhere provider
pnpm moltbot config set models.providers.runanywhere.baseUrl "http://127.0.0.1:8080/v1"
pnpm moltbot config set models.providers.runanywhere.apiKey "local"
pnpm moltbot config set models.providers.runanywhere.api "openai-completions"

# Set default model
pnpm moltbot config set agents.defaults.model.primary "runanywhere/LFM2.5-1.2B-Instruct-Q8_0"
pnpm moltbot config set agents.defaults.promptMode "local"
```

### Step 5: Setup Telegram Channel

1. **Create bot with @BotFather:**
   - Message @BotFather on Telegram
   - Send `/newbot` and follow prompts
   - Copy the bot token

2. **Configure in Moltbot:**
   ```bash
   pnpm moltbot config set channels.telegram.enabled true
   pnpm moltbot config set channels.telegram.botToken "<your-bot-token>"
   pnpm moltbot config set channels.telegram.dmPolicy allowlist
   ```

3. **Get your Telegram User ID:**
   - Message @userinfobot on Telegram
   - Copy your numeric user ID

4. **Add yourself to allowlist:**
   ```bash
   pnpm moltbot config set channels.telegram.allowFrom "[<your-user-id>]"
   ```

### Step 6: Start Services

**Terminal 1 - RunAnywhere Server:**
```bash
export LD_LIBRARY_PATH=~/.local/runanywhere/lib:$LD_LIBRARY_PATH
~/.local/runanywhere/bin/runanywhere-server \
  --model ~/.local/share/runanywhere/Models/LlamaCpp/lfm2.5-1.2b/LFM2.5-1.2B-Instruct-Q8_0.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --threads 4 \
  --context 16384
```

**Terminal 2 - Moltbot Gateway:**
```bash
cd ~/moltbot
pnpm moltbot gateway run
# Or via systemd: systemctl --user start moltbot-gateway
```

**Terminal 3 - Voice Assistant (optional):**
```bash
export LD_LIBRARY_PATH=~/.local/runanywhere/lib:$LD_LIBRARY_PATH
~/.local/runanywhere/bin/voice-assistant --wakeword --moltbot
```

### Step 7: Verify Setup

```bash
# Check LLM server
curl http://localhost:8080/v1/models

# Check Moltbot gateway
pnpm moltbot channels status

# Test LLM completion
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "LFM2.5-1.2B-Instruct-Q8_0", "messages": [{"role": "user", "content": "Hello"}]}'
```

---

## Voice Assistant Channel

The voice assistant connects to Moltbot as a first-class channel (like Telegram or WhatsApp):

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│          Linux Voice Assistant (Standalone App)              │
│                                                              │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐     │
│  │ Wake    │ → │ Audio   │ → │  STT    │ → │ WebSocket│     │
│  │ Word    │   │ Capture │   │ Whisper │   │ Client  │     │
│  └─────────┘   └─────────┘   └─────────┘   └────┬────┘     │
│                                                   │          │
│  ┌─────────┐   ┌─────────┐                       │          │
│  │ Audio   │ ← │  TTS    │ ←─────────────────────┘          │
│  │ Playback│   │ Piper   │                                  │
│  └─────────┘   └─────────┘                                  │
└─────────────────────────────────────────────────────────────┘
                              ↕ WebSocket (port 8082)
┌─────────────────────────────────────────────────────────────┐
│                    Moltbot Gateway                           │
│              (voice-assistant extension)                     │
└─────────────────────────────────────────────────────────────┘
```

### WebSocket Protocol

**Voice → Moltbot:**
```json
{"type": "transcription", "text": "What's the weather?", "isFinal": true}
```

**Moltbot → Voice:**
```json
{"type": "speak", "text": "The weather is sunny.", "sourceChannel": "telegram"}
```

---

## Troubleshooting

### Connection Error from Moltbot to RunAnywhere Server

**Symptom:** Agent returns "Connection error." in session logs.

**Diagnosis:**
```bash
# Check if server is running
curl http://127.0.0.1:8080/v1/models

# Check moltbot config
pnpm moltbot config get models.providers.runanywhere

# Check session logs
tail -20 ~/.clawdbot/agents/main/sessions/*.jsonl | grep -i error
```

**Solutions:**
1. Ensure RunAnywhere server is started BEFORE Moltbot gateway
2. Use `127.0.0.1` instead of `localhost` in baseUrl
3. Restart gateway after starting server:
   ```bash
   pnpm moltbot gateway stop && pnpm moltbot gateway start
   ```
4. Clear session cache:
   ```bash
   mv ~/.clawdbot/agents/main/sessions/*.jsonl ~/.clawdbot/agents/main/sessions/backup/
   ```

### Telegram Not Responding

**Symptom:** Bot receives messages but doesn't reply.

**Diagnosis:**
```bash
# Check channel status
pnpm moltbot channels status

# Check gateway logs
journalctl --user -u moltbot-gateway.service --since "5 min ago"
```

**Solutions:**
1. Verify bot token: `curl https://api.telegram.org/bot<TOKEN>/getMe`
2. Check allowFrom includes your user ID
3. Ensure dmPolicy is "allowlist" or "open"

### Model Context Window Error

**Symptom:** "Model context window too small (8192 tokens). Minimum is 16000"

**Solution:**
1. Start server with `--context 16384`
2. Set `contextWindow: 16384` in moltbot.json model config
3. Restart gateway

---

## Service Management

### Systemd Services

**Moltbot Gateway:**
```bash
# Start/stop/restart
systemctl --user start moltbot-gateway
systemctl --user stop moltbot-gateway
systemctl --user restart moltbot-gateway

# View logs
journalctl --user -u moltbot-gateway.service -f
```

**RunAnywhere Server (manual):**
```bash
# Start in background
nohup ~/.local/runanywhere/bin/runanywhere-server \
  --model ~/.local/share/runanywhere/Models/LlamaCpp/lfm2.5-1.2b/LFM2.5-1.2B-Instruct-Q8_0.gguf \
  --port 8080 --threads 4 --context 16384 > /tmp/runanywhere-server.log 2>&1 &

# View logs
tail -f /tmp/runanywhere-server.log

# Stop
pkill -f runanywhere-server
```

---

## Current Status (2026-02-02)

### Working
- RunAnywhere server running with LFM 1.2B model
- Moltbot gateway running with Telegram channel
- Telegram bot configured (@claw_san_bot)
- User allowlisted (ID: 6715735812)
- Direct API calls to RunAnywhere server work

### In Progress
- Debugging connection between Moltbot agent and RunAnywhere server
- Agent returns "Connection error." despite server being reachable via curl

### Next Steps
1. Resolve Moltbot → RunAnywhere connection issue
2. Test end-to-end Telegram → LLM → response flow
3. Configure voice assistant channel
4. Test multi-channel message sync

---

## References

- [Moltbot Documentation](https://docs.molt.bot)
- [RunAnywhere SDKs](https://github.com/RunanywhereAI/runanywhere-sdks)
- [Linux Voice Assistant README](/home/runanywhere/runanywhere-sdks/Playground/linux-voice-assistant/README.md)
- [Raspberry Pi 5 Voice Pipeline Plan](/home/runanywhere/runanywhere-sdks/raspberry_pi5_hailo_voice_pipeline.md)

---

**Last Updated:** 2026-02-02
**Author:** RunAnywhere AI Team
