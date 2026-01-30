# Voice Assistant Setup Guide

Set up the RunAnywhere Voice Assistant on Raspberry Pi 5 (Linux aarch64).

## Quick Start Options

| Option | Best For | Time |
|--------|----------|------|
| **Standalone** | Just voice chat with local LLM | ~5 min |
| **With Moltbot** | Full AI assistant (tools, multi-channel) | ~10 min |

---

## Option 1: Standalone (Pre-built Binaries)

Simple voice assistant with local LLM. No Moltbot, no internet required.

```bash
# Download and install
curl -fsSL https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/voice-assistant-v0.1.0/runanywhere-voice-assistant-linux-aarch64.tar.gz | tar -xzf - -C /tmp
cd /tmp/runanywhere-release && ./install.sh

# Download AI models (~2.5GB)
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/Playground/linux-voice-assistant/scripts/download-models.sh | bash

# Run
~/.local/runanywhere/run.sh
```

Say **"Hey Jarvis"** to activate.

---

## Option 2: Full Moltbot Integration (Recommended)

Complete AI assistant with tool execution, task planning, and multi-channel sync (WhatsApp, Telegram, Voice all share the same conversation).

### One-Command Install

```bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/clawdbot/main/scripts/quickstart.sh | bash
```

This installs:
- **Moltbot** - AI assistant gateway
- **RunAnywhere Server** - Local LLM inference (Qwen3-1.7B)
- **Voice Assistant** - Wake word + STT + TTS

### After Installation

```bash
# First time only - configure Moltbot
cd ~/moltbot && pnpm moltbot onboard

# Start everything
~/runanywhere-sdks/Playground/linux-voice-assistant/run.sh
```

### What's Running

| Component | Port | Purpose |
|-----------|------|---------|
| runanywhere-server | 8080 | Local LLM inference |
| Moltbot gateway | 18789 | AI orchestration |
| Voice bridge | 8082 | WebSocket for voice |
| Voice assistant | - | Audio I/O |

---

## Usage

Say **"Hey Jarvis"** to activate, then speak your question.

### Command Line Options

```
voice-assistant [options]
  --list-devices    List available audio devices
  --input <device>  Audio input device (default: "default")
  --output <device> Audio output device (default: "default")
  --wakeword        Enable wake word detection
  --moltbot         Enable Moltbot integration
```

---

## Troubleshooting

### Library not found (libonnxruntime.so.1)

```bash
cd ~/.local/runanywhere/lib
for lib in *.so; do ln -sf "$lib" "${lib}.1" 2>/dev/null; done
```

### No audio input

```bash
arecord -l  # List audio devices
```

### Model not found

```bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/Playground/linux-voice-assistant/scripts/download-models.sh | bash
```

---

## Build from Source

For development or custom configurations, see [BUILD.md](BUILD.md).
