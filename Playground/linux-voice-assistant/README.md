# RunAnywhere Voice Assistant

On-device voice AI for Raspberry Pi 5. Say **"Hey Jarvis"** to activate.

**Stack:** Wake Word + VAD + STT (Whisper) + LLM (Qwen3) + TTS (Piper) — all local, no cloud.

---

## Quick Start

### Step 1: Install RunAnywhere (Pre-built Binaries)

```bash
# Download and install
curl -fsSL https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/voice-assistant-v0.1.0/runanywhere-voice-assistant-linux-aarch64.tar.gz | tar -xzf - -C /tmp
cd /tmp/runanywhere-release && ./install.sh

# Fix library symlinks (if needed)
cd ~/.local/runanywhere/lib && for lib in *.so; do ln -sf "$lib" "${lib}.1"; done
```

### Step 2: Download AI Models (~2.5GB)

```bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/Playground/linux-voice-assistant/scripts/download-models.sh | bash
```

### Step 3: Install Moltbot

```bash
# Clone
git clone https://github.com/RunanywhereAI/clawdbot.git ~/moltbot

# Install and build
cd ~/moltbot
npm install -g pnpm
pnpm install
pnpm build

# Configure (creates ~/.clawdbot/config.yaml)
pnpm moltbot onboard
```

### Step 4: Run

```bash
# Start everything (LLM server + Moltbot + Voice Assistant)
~/moltbot/scripts/run-with-voice.sh

# Or start components separately:
# Terminal 1: LLM Server
~/.local/runanywhere/bin/runanywhere-server --model ~/.local/share/runanywhere/Models/LlamaCpp/qwen3-1.7b/*.gguf --port 8080

# Terminal 2: Moltbot
cd ~/moltbot && pnpm moltbot gateway --port 18789

# Terminal 3: Voice Assistant
export LD_LIBRARY_PATH=~/.local/runanywhere/lib:$LD_LIBRARY_PATH
~/.local/runanywhere/bin/voice-assistant --wakeword --moltbot
```

---

## What's Running

| Component | Port | Purpose |
|-----------|------|---------|
| runanywhere-server | 8080 | Local LLM inference |
| Moltbot gateway | 18789 | AI orchestration, tools |
| Voice assistant | — | Wake word, STT, TTS |

---

## Standalone Mode (No Moltbot)

For simple voice chat without Moltbot:

```bash
~/.local/runanywhere/run.sh
```

---

## Troubleshooting

**Library not found:** `cd ~/.local/runanywhere/lib && for lib in *.so; do ln -sf "$lib" "${lib}.1"; done`

**No audio:** `arecord -l` to list devices, then use `--input plughw:X,0`

**Model not found:** Re-run the download script from Step 2

---

## License

MIT
