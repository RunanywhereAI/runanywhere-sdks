# Voice Assistant Setup Guide

This guide covers different ways to set up the RunAnywhere Voice Assistant on Linux (Raspberry Pi 5 / aarch64).

## Option 1: Pre-built Binaries (Fastest)

Download pre-built binaries - no compilation needed.

```bash
# Download and extract
curl -fsSL https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/voice-assistant-v0.1.0/runanywhere-voice-assistant-linux-aarch64.tar.gz | tar -xzf - -C /tmp

# Install to ~/.local/runanywhere
cd /tmp/runanywhere-release && ./install.sh

# Download AI models (~2.5GB)
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/playground/linux-voice-assistant/scripts/download-models.sh | bash

# Run
~/.local/runanywhere/run.sh
```

## Option 2: Full Moltbot Integration (Recommended)

One command to set up Moltbot + Voice Assistant + RunAnywhere:

```bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/clawdbot/main/scripts/quickstart.sh | bash
```

This installs:
- Moltbot (AI assistant gateway)
- RunAnywhere Server (local LLM inference)
- Voice Assistant (wake word + STT + TTS)
- AI Models (Whisper, Piper, Qwen3-1.7B)

After installation:
```bash
# First time only - configure Moltbot
cd ~/moltbot && pnpm moltbot onboard

# Start everything
~/runanywhere-sdks/playground/linux-voice-assistant/run.sh
```

## Option 3: Build from Source

For development or custom configurations.

### Prerequisites

```bash
# Install build tools
sudo apt-get update
sudo apt-get install -y cmake build-essential libasound2-dev libpulse-dev git

# Install Node.js 22+
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
cd ~/runanywhere-sdks/playground/linux-voice-assistant
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# Download models
cd ~/runanywhere-sdks/playground/linux-voice-assistant
./scripts/download-models.sh
```

## Running

### Standalone (no Moltbot)

```bash
~/.local/runanywhere/run.sh
# Or if built from source:
~/runanywhere-sdks/playground/linux-voice-assistant/run.sh
```

### With Moltbot

```bash
~/runanywhere-sdks/playground/linux-voice-assistant/run.sh
```

This starts:
1. **runanywhere-server** on port 8080 (LLM inference)
2. **Moltbot gateway** on port 18789
3. **Voice bridge** (WebSocket)
4. **Voice assistant** (wake word + STT + TTS)

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

## Troubleshooting

### Library not found errors (e.g., libonnxruntime.so.1)

If you see errors like `libonnxruntime.so.1: cannot open shared object file`:

1. **Create versioned symlinks** (if install.sh didn't create them):
   ```bash
   cd ~/.local/runanywhere/lib
   for lib in *.so; do ln -sf "$lib" "${lib}.1" 2>/dev/null; done
   ```

2. **Ensure LD_LIBRARY_PATH is set** (run.sh does this automatically):
   ```bash
   export LD_LIBRARY_PATH=~/.local/runanywhere/lib:$LD_LIBRARY_PATH
   ```

### No audio input

Check ALSA devices:
```bash
arecord -l
```

### Model not found

Download models:
```bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/playground/linux-voice-assistant/scripts/download-models.sh | bash
```
