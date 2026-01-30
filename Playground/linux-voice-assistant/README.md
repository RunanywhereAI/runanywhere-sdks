# RunAnywhere Voice Assistant

On-device voice AI for Raspberry Pi 5 (Linux aarch64). Say **"Hey Jarvis"** to activate.

---

## Option 1: Full Moltbot Integration (Easiest & Recommended)

Complete AI assistant with WhatsApp, Voice, and local LLM.

### Step 1: Install Pre-built Binaries

```bash
# Download and install RunAnywhere
curl -fsSL https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/voice-assistant-v0.1.0/runanywhere-voice-assistant-linux-aarch64.tar.gz | tar -xzf - -C /tmp
cd /tmp/runanywhere-release && ./install.sh

# Fix library symlinks
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
cd ~/moltbot

# Install pnpm and dependencies
npm install -g pnpm
pnpm install
pnpm build
```

### Step 4: Run Moltbot Onboarding

```bash
cd ~/moltbot && pnpm moltbot onboard
```

**Answer the prompts as follows:**

| Prompt | Answer |
|--------|--------|
| Security warning - Continue? | **Yes** |
| Onboarding mode | **QuickStart** |
| Config handling | **Use existing values** |
| Model/auth provider | **Skip for now** |
| Filter models by provider | **All providers** |
| Default model | **Keep current** |
| Select channel | **WhatsApp (QR link)** or skip |
| Link WhatsApp now? | **Yes** (scan QR with your phone) |
| WhatsApp phone setup | **This is my personal phone number** |
| Your WhatsApp number | Enter your number (e.g., +15551234567) |
| Configure skills now? | **Yes** |
| Show Homebrew install? | **Yes** (or No) |
| Preferred node manager | **npm** |
| Install missing skill dependencies | **Skip for now** |
| API keys (GOOGLE_PLACES, etc.) | **No** for all (or add if you have them) |
| Enable hooks? | **Skip for now** |
| How to hatch your bot? | **Do this later** |

### Step 5: Configure RunAnywhere as Model Provider

Add RunAnywhere to `~/.moltbot/moltbot.json`:

```bash
# Open the config
nano ~/.moltbot/moltbot.json
```

Add this `"models"` section right after `"meta"`:

```json
{
  "meta": { ... },
  "models": {
    "providers": {
      "runanywhere": {
        "baseUrl": "http://localhost:8080/v1",
        "apiKey": "",
        "api": "openai-completions",
        "models": [
          {
            "id": "qwen3-1.7b",
            "name": "Qwen3 1.7B (Local)",
            "contextWindow": 8192,
            "maxTokens": 4096
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      ...existing config...,
      "models": {
        "default": {
          "provider": "runanywhere",
          "model": "qwen3-1.7b"
        }
      }
    }
  },
  ...rest of config...
}
```

### Step 6: Start Everything

**Terminal 1 - RunAnywhere Server:**
```bash
export LD_LIBRARY_PATH=~/.local/runanywhere/lib:$LD_LIBRARY_PATH
~/.local/runanywhere/bin/runanywhere-server \
  --model ~/.local/share/runanywhere/Models/LlamaCpp/qwen3-1.7b/Qwen3-1.7B-Q8_0.gguf \
  --port 8080 --threads 4
```

**Terminal 2 - Restart Moltbot Gateway:**
```bash
systemctl --user restart moltbot-gateway
systemctl --user status moltbot-gateway
```

**Terminal 3 - Voice Assistant (optional):**
```bash
export LD_LIBRARY_PATH=~/.local/runanywhere/lib:$LD_LIBRARY_PATH
~/.local/runanywhere/bin/voice-assistant --wakeword --moltbot
```

### Step 7: Test

- **Web UI:** http://127.0.0.1:18789 (use token from onboarding)
- **WhatsApp:** Send yourself a message
- **Voice:** Say "Hey Jarvis"

---

## Option 2: Pre-built Binaries (Standalone)

Simple voice assistant without Moltbot. No WhatsApp, no tools.

```bash
# Download and install
curl -fsSL https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/voice-assistant-v0.1.0/runanywhere-voice-assistant-linux-aarch64.tar.gz | tar -xzf - -C /tmp
cd /tmp/runanywhere-release && ./install.sh

# Fix library symlinks
cd ~/.local/runanywhere/lib && for lib in *.so; do ln -sf "$lib" "${lib}.1"; done

# Download AI models (~2.5GB)
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/Playground/linux-voice-assistant/scripts/download-models.sh | bash

# Run
~/.local/runanywhere/run.sh
```

---

## Option 3: Build from Source

For development or custom configurations.

### Prerequisites

```bash
sudo apt-get update
sudo apt-get install -y cmake build-essential libasound2-dev libpulse-dev git

# Node.js 22+ (for Moltbot)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### Build Steps

```bash
# Clone the SDK
git clone -b smonga/rasp https://github.com/RunanywhereAI/runanywhere-sdks.git ~/runanywhere-sdks
cd ~/runanywhere-sdks/sdk/runanywhere-commons

# Build SDK with shared libraries
./scripts/build-linux.sh --shared

# Build the server
mkdir -p build-server && cd build-server
cmake .. -DCMAKE_BUILD_TYPE=Release \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BUILD_SERVER=ON \
    -DRAC_BACKEND_LLAMACPP=ON \
    -DRAC_BACKEND_ONNX=ON \
    -DRAC_BACKEND_WHISPERCPP=OFF
make -j$(nproc)

# Build voice assistant
cd ~/runanywhere-sdks/Playground/linux-voice-assistant
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# Download models
cd ~/runanywhere-sdks/Playground/linux-voice-assistant
./scripts/download-models.sh
```

---

## What's Running

| Component | Port | Purpose |
|-----------|------|---------|
| runanywhere-server | 8080 | Local LLM inference |
| Moltbot gateway | 18789 | AI orchestration, WhatsApp, tools |
| Voice assistant | — | Wake word, STT, TTS |

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
  --moltbot-url     Moltbot voice bridge URL (default: "http://localhost:8081")
```

---

## Troubleshooting

### Library not found (libonnxruntime.so.1)

```bash
cd ~/.local/runanywhere/lib
for lib in *.so; do ln -sf "$lib" "${lib}.1"; done
```

### No audio input

```bash
arecord -l  # List devices
```

### Model not found

```bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/Playground/linux-voice-assistant/scripts/download-models.sh | bash
```

### Moltbot can't connect to RunAnywhere

1. Check RunAnywhere server is running: `curl http://localhost:8080/health`
2. Check config has RunAnywhere provider in `~/.moltbot/moltbot.json`
3. Restart gateway: `systemctl --user restart moltbot-gateway`

---

## License

MIT
