# Moltbot Voice Assistant Integration

This guide explains how to integrate the RunAnywhere Voice Assistant with Moltbot. There are three ways to get started, depending on your situation.

## Quick Reference

| Method | Best For | Command |
|--------|----------|---------|
| [Option 1](#option-1-fresh-install-runanywhere-fork) | New users, full setup | `git clone` + `npm install` |
| [Option 2](#option-2-existing-moltbot-users) | Already have Moltbot | `moltbot plugins install` |
| [Option 3](#option-3-one-liner-install) | Quick start | `curl ... \| bash` |

---

## Option 1: Fresh Install (RunAnywhere Fork)

Best for users who don't have Moltbot installed yet and want the complete RunAnywhere experience.

### What You Get
- Full Moltbot installation with all standard channels (WhatsApp, Telegram, Discord, etc.)
- **RunAnywhere extension** - Local LLM provider for on-device AI inference
- **Voice Assistant channel** - Voice as a first-class channel with WebSocket support

### Prerequisites
- Node.js 22 or later
- Raspberry Pi 5 (or any Linux device) for voice assistant hardware
- Microphone and speaker

### Installation Steps

```bash
# 1. Clone the RunAnywhere fork of Moltbot
git clone https://github.com/RunanywhereAI/clawdbot.git ~/moltbot
cd ~/moltbot
git checkout smonga/rasp  # Branch with voice extensions

# 2. Install pnpm (if not installed)
npm install -g pnpm

# 3. Install dependencies
pnpm install

# 4. Build the project
pnpm build

# 5. Run the onboarding wizard
pnpm moltbot onboard

# 6. Start the gateway (in a terminal or as a daemon)
pnpm moltbot gateway --port 18789 --verbose
```

### Directory Structure After Install
```
~/moltbot/
├── extensions/
│   ├── runanywhere/        # Local LLM provider
│   └── voice-assistant/    # Voice channel plugin
├── src/
└── ...
```

### Next Steps
After Moltbot is running, set up the voice assistant:

```bash
# Clone the voice assistant SDK
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git ~/runanywhere-sdks
cd ~/runanywhere-sdks && git checkout smonga/rasp
cd ~/runanywhere-sdks/playground/linux-voice-assistant

# Download models
./scripts/download-models.sh

# Build the voice assistant
mkdir -p build && cd build
cmake .. && make -j$(nproc)

# Start the voice bridge (connects to Moltbot)
cd .. && npx tsx scripts/start-voice-bridge.ts --websocket

# In another terminal, run the voice assistant
./build/voice-assistant --moltbot --wakeword
```

---

## Option 2: Existing Moltbot Users

Best for users who already have Moltbot installed via `npm install -g moltbot` and want to add RunAnywhere capabilities.

### What You Get
- **RunAnywhere extension** - Local LLM provider (replaces/complements cloud APIs)
- **Voice Assistant channel** - Adds voice as a channel alongside your existing WhatsApp, Telegram, etc.

### Prerequisites
- Moltbot already installed and working
- Node.js 22 or later

### Installation Steps

#### Step 1: Install the RunAnywhere Extension

```bash
# Option A: Install from GitHub (recommended)
moltbot plugins install https://github.com/RunanywhereAI/clawdbot/releases/download/latest/runanywhere-extension.tgz

# Option B: Install from local path (if you cloned the fork)
moltbot plugins install ~/moltbot-fork/extensions/runanywhere
```

#### Step 2: Install the Voice Assistant Extension

```bash
# Option A: Install from GitHub (recommended)
moltbot plugins install https://github.com/RunanywhereAI/clawdbot/releases/download/latest/voice-assistant-extension.tgz

# Option B: Install from local path
moltbot plugins install ~/moltbot-fork/extensions/voice-assistant
```

#### Step 3: Configure RunAnywhere Provider

Add to your Moltbot config (`~/.config/moltbot/config.yaml`):

```yaml
# Add RunAnywhere as a provider
providers:
  runanywhere:
    enabled: true
    baseUrl: "http://localhost:8080"  # RunAnywhere API server
    defaultModel: "llama-3.2-3b"

# Configure model routing (optional - use local LLM for all requests)
models:
  default:
    provider: runanywhere
    model: llama-3.2-3b
```

#### Step 4: Verify Installation

```bash
# List installed plugins
moltbot plugins list

# Should show:
# runanywhere    loaded - Local AI inference via RunAnywhere SDK
# voice-assistant loaded - Voice channel with wake word detection
```

#### Step 5: Restart Gateway

```bash
moltbot gateway restart
# Or if running manually:
moltbot gateway --port 18789 --verbose
```

---

## Option 3: One-Liner Install

Best for users who want the quickest path to a working setup.

### Full Installation (Fresh System)

```bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/playground/linux-voice-assistant/scripts/install.sh | bash
```

This script will:
1. Check prerequisites (Node.js, build tools)
2. Clone the RunAnywhere Moltbot fork
3. Install and build Moltbot
4. Clone the voice assistant SDK
5. Download AI models
6. Build the voice assistant
7. Create systemd services (optional)

### Add to Existing Moltbot

```bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/playground/linux-voice-assistant/scripts/add-to-moltbot.sh | bash
```

This script will:
1. Detect your Moltbot installation
2. Download and install the RunAnywhere extension
3. Download and install the Voice Assistant extension
4. Update your config with RunAnywhere provider
5. Prompt to restart the gateway

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Moltbot Gateway                            │
├─────────────────────────────────────────────────────────────────────┤
│  Channels:                                                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌─────────────────────────┐│
│  │ WhatsApp │ │ Telegram │ │ Discord  │ │    Voice Assistant     ││
│  │          │ │          │ │          │ │  (WebSocket :8082)     ││
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └───────────┬─────────────┘│
│       │            │            │                   │               │
│       └────────────┴────────────┴───────────────────┘               │
│                              │                                       │
│                    ┌─────────▼─────────┐                            │
│                    │   Agent/Hooks     │                            │
│                    │  (/hooks/agent)   │                            │
│                    └─────────┬─────────┘                            │
│                              │                                       │
│  Providers:                  │                                       │
│  ┌──────────────────────────▼──────────────────────────────────────┐│
│  │                    RunAnywhere Extension                         ││
│  │              (Local LLM via OpenAI-compatible API)               ││
│  └──────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
                                │
                                │ HTTP/WebSocket
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Voice Bridge                                 │
│                    (scripts/start-voice-bridge.ts)                   │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐  │
│  │ WebSocket Client│    │   Speak Queue   │    │  HTTP Endpoints │  │
│  │  (to :8082)     │◄──►│ (priority-based)│◄──►│  /speak, /chat  │  │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                │ HTTP polling
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Voice Assistant (C++)                           │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐             │
│  │ Wake    │──►│   VAD   │──►│   STT   │──►│ Moltbot │             │
│  │ Word    │   │         │   │(Whisper)│   │  POST   │             │
│  └─────────┘   └─────────┘   └─────────┘   └────┬────┘             │
│                                                  │                   │
│                    ┌─────────┐   ┌─────────┐    │                   │
│                    │   TTS   │◄──│  Poll   │◄───┘                   │
│                    │ (Piper) │   │ /speak  │                        │
│                    └────┬────┘   └─────────┘                        │
│                         │                                            │
│                    ┌────▼────┐                                       │
│                    │ Speaker │                                       │
│                    └─────────┘                                       │
└─────────────────────────────────────────────────────────────────────┘
```

## Message Flow

### Voice Input → All Channels
1. User says "Hey Jarvis" → Wake word detected
2. User speaks command → VAD detects speech
3. Speech → STT (Whisper) → Text transcription
4. Transcription → Voice Bridge → Moltbot `/hooks/agent`
5. Moltbot routes to agent, generates response
6. Response broadcasts to ALL channels (WhatsApp, Telegram, Voice, etc.)
7. Voice channel receives response → Speak queue
8. Voice assistant polls `/speak` → TTS → Speaker

### Any Channel → Voice Output
1. User sends message on WhatsApp/Telegram/Discord
2. Moltbot agent generates response
3. Response broadcasts to ALL channels including voice
4. Voice channel WebSocket sends speak command
5. Voice bridge adds to speak queue
6. Voice assistant polls → TTS → Speaker plays response

---

## Troubleshooting

### Plugins Not Loading

```bash
# Check plugin status
moltbot plugins list --verbose

# Check for errors
moltbot plugins info voice-assistant
moltbot plugins info runanywhere
```

### Voice Bridge Connection Issues

```bash
# Check if Moltbot gateway is running
curl http://localhost:18789/health

# Check if voice channel WebSocket is listening
curl http://localhost:8082/health

# Check voice bridge logs
npx tsx scripts/start-voice-bridge.ts --websocket --verbose
```

### No Audio Output

```bash
# List audio devices
./build/voice-assistant --list-devices

# Test with specific device
./build/voice-assistant --moltbot --output "plughw:0,0"
```

---

## Configuration Reference

### Voice Pipeline Config (`VoicePipelineConfig`)

| Setting | Default | Description |
|---------|---------|-------------|
| `enable_moltbot` | `false` | Enable Moltbot integration |
| `moltbot_voice_bridge_url` | `http://localhost:8081` | Voice bridge URL |
| `enable_wake_word` | `false` | Enable wake word detection |
| `wake_word` | `"Hey Jarvis"` | Wake word phrase |
| `wake_word_threshold` | `0.5` | Detection confidence threshold |

### Voice Bridge Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MOLTBOT_URL` | `http://localhost:18789` | Moltbot gateway URL |
| `MOLTBOT_WS_URL` | `ws://localhost:8082` | Voice channel WebSocket |
| `BRIDGE_PORT` | `8081` | Voice bridge HTTP port |

---

## Next Steps

- [Wake Word Customization](./WAKE_WORD.md)
- [Model Configuration](./MODELS.md)
- [Multi-Room Audio](./MULTI_ROOM.md)
