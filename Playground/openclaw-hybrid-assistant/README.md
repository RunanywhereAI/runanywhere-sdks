# OpenClaw Hybrid Assistant

A lightweight voice assistant that acts as a **channel** for OpenClaw. No local LLM - just:

- **Wake Word** → **VAD** → **ASR** → sends transcription to OpenClaw
- **TTS** ← receives speech commands from OpenClaw (any channel)

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        OpenClaw Hybrid Assistant                             │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         INPUT PIPELINE                                │   │
│  │                                                                       │   │
│  │   Microphone → Wake Word → VAD → ASR/STT → WebSocket → OpenClaw      │   │
│  │    (ALSA)     (openWW)  (Silero) (Whisper)            (Channel)      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                        OUTPUT PIPELINE                                │   │
│  │                                                                       │   │
│  │   OpenClaw → WebSocket → TTS/Piper → Speaker                         │   │
│  │  (any channel)          (local)      (ALSA)                          │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Differences from linux-voice-assistant

| Feature | linux-voice-assistant | openclaw-hybrid-assistant |
|---------|----------------------|---------------------------|
| Wake Word | ✅ | ✅ |
| VAD | ✅ | ✅ |
| ASR/STT | ✅ Local Whisper | ✅ Local Whisper |
| LLM | ✅ Local or Moltbot | ❌ None - uses OpenClaw |
| TTS | ✅ Local Piper | ✅ Local Piper |
| Integration | HTTP Voice Bridge | WebSocket to OpenClaw |

## Components

### 1. Wake Word Detector
- Model: openWakeWord "Hey Jarvis"
- Threshold: 0.5 (configurable)
- Frame size: 80ms (1280 samples at 16kHz)

### 2. Voice Activity Detection (VAD)
- Model: Silero VAD
- Silence threshold: 1.5 seconds
- Minimum speech: 0.5 seconds

### 3. Speech-to-Text (ASR)
- Model: Whisper Tiny English
- Sample rate: 16kHz mono

### 4. Text-to-Speech (TTS)
- Model: Piper VITS (Lessac US voice)
- Output rate: 22050 Hz

## OpenClaw WebSocket Protocol

### Connection
```
ws://openclaw-host:8082
```

### Messages: Assistant → OpenClaw

**Connect:**
```json
{
  "type": "connect",
  "deviceId": "pi-living-room",
  "accountId": "default",
  "capabilities": {
    "stt": true,
    "tts": true,
    "wakeWord": true
  }
}
```

**Transcription (after ASR):**
```json
{
  "type": "transcription",
  "text": "What's the weather like?",
  "sessionId": "main",
  "isFinal": true
}
```

### Messages: OpenClaw → Assistant

**Speak (for TTS):**
```json
{
  "type": "speak",
  "text": "The weather is sunny.",
  "sourceChannel": "telegram",
  "priority": 1,
  "interrupt": false
}
```

## Quick Start

### Prerequisites

- Raspberry Pi 5 (or Linux x86_64/ARM64)
- ALSA development libraries
- OpenClaw running with voice-assistant channel enabled

### Build

```bash
./build.sh
```

### Run

```bash
# Basic (connects to localhost:8082)
./build/openclaw-assistant

# With wake word enabled
./build/openclaw-assistant --wakeword

# Connect to remote OpenClaw
./build/openclaw-assistant --wakeword --openclaw-url ws://192.168.1.100:8082
```

### Test Components

```bash
# Run all tests
./build/test-components --run-all

# Test wake word detection with audio file
./build/test-components --test-wakeword tests/audio/hey-jarvis.wav

# Test that audio does NOT trigger wake word
./build/test-components --test-no-wakeword tests/audio/noise.wav

# Test VAD and STT
./build/test-components --test-vad tests/audio/speech.wav
./build/test-components --test-stt tests/audio/speech.wav

# Test full pipeline
./build/test-components --test-pipeline tests/audio/wakeword-plus-speech.wav
```

## Configuration

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--wakeword` | Enable wake word detection | Off |
| `--wakeword-threshold` | Detection threshold (0.0-1.0) | 0.5 |
| `--openclaw-url` | OpenClaw WebSocket URL | `ws://localhost:8082` |
| `--device-id` | Device identifier | hostname |
| `--input` | ALSA input device | "default" |
| `--output` | ALSA output device | "default" |
| `--list-devices` | List audio devices | - |
| `--help` | Show help | - |

## Models Required

| Model | Size | Location |
|-------|------|----------|
| Silero VAD | ~2 MB | `~/.local/share/runanywhere/Models/ONNX/silero-vad/` |
| Whisper Tiny EN | ~150 MB | `~/.local/share/runanywhere/Models/ONNX/whisper-tiny-en/` |
| Piper Lessac | ~65 MB | `~/.local/share/runanywhere/Models/ONNX/vits-piper-en_US-lessac-medium/` |
| Hey Jarvis | ~1.3 MB | `~/.local/share/runanywhere/Models/ONNX/hey-jarvis/` |
| openWakeWord Embedding | ~1.3 MB | `~/.local/share/runanywhere/Models/ONNX/openwakeword-embedding/` |
| openWakeWord Melspectrogram | ~1.1 MB | `~/.local/share/runanywhere/Models/ONNX/openwakeword-embedding/` |

### Wake Word Model Download Note

The openWakeWord `.onnx` model files are stored with Git LFS in the upstream repository.
Downloading them via `raw.githubusercontent.com` URLs will give you an HTML page instead
of the actual model binary, which causes ONNX runtime errors at load time.

Always download wake word models from **GitHub Releases**:
- `https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/embedding_model.onnx`
- `https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/melspectrogram.onnx`
- `https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/hey_jarvis_v0.1.onnx`

The `scripts/download-models.sh --wakeword` script already uses the correct URLs.

To verify your downloaded models are valid ONNX files (not HTML):
```bash
file ~/.local/share/runanywhere/Models/ONNX/openwakeword-embedding/embedding_model.onnx
# Expected: "data" (binary ONNX file)
# Bad:      "HTML document" (Git LFS redirect page)
```

## Raspberry Pi First-Time Setup

### 1. Build runanywhere-commons (shared libraries)

```bash
cd /path/to/runanywhere-sdks/sdk/runanywhere-commons
./scripts/build-linux.sh --shared
```

This builds `librac_backend_onnx.so` and other shared libraries that the hybrid assistant links against. You must rebuild this whenever the SDK's C++ backends change (e.g., wake word fixes).

### 2. Download models

```bash
cd /path/to/runanywhere-sdks/Playground/openclaw-hybrid-assistant

# Download all models (STT, TTS, VAD, wake word)
./scripts/download-models.sh --all

# Or download only wake word models
./scripts/download-models.sh --wakeword --force
```

### 3. Build the hybrid assistant

```bash
./build.sh
```

### 4. Ensure OpenClaw is running

The OpenClaw gateway must be running with the `voice-assistant` channel enabled on port 8082. Verify with:

```bash
ss -tlnp | grep 8082
```

### 5. Run the assistant

```bash
# With wake word ("Hey Jarvis")
./build/openclaw-assistant --wakeword

# Without wake word (continuous listening)
./build/openclaw-assistant
```

### 6. Run as a systemd service (optional)

To run the assistant as a background service that starts on boot, create a systemd user service and enable it. See [Viewing Logs](#viewing-logs) below for how to monitor it.

## Viewing Logs

### Hybrid Assistant logs

If running in the foreground, logs print to stdout. If running as a background process or systemd service:

```bash
# If started via systemd
journalctl --user -u openclaw-assistant -f

# If started as a background process with output redirected
tail -f /path/to/openclaw-assistant.log
```

### OpenClaw Gateway logs

The OpenClaw gateway runs as a systemd user service:

```bash
# Follow logs in real time
journalctl --user -u openclaw-gateway -f

# View last 100 lines
journalctl --user -u openclaw-gateway -n 100

# View logs since last boot
journalctl --user -u openclaw-gateway -b
```

### Watching both side-by-side

Open two terminals (or tmux panes):

```bash
# Terminal 1: OpenClaw Gateway
journalctl --user -u openclaw-gateway -f

# Terminal 2: Hybrid Assistant
journalctl --user -u openclaw-assistant -f
# (or tail -f on the output file if not using systemd)
```

## Testing on Mac

Since this is a Linux application using ALSA, you can test on Mac using:

### Option 1: Docker with WAV Files (Recommended)

```bash
# Build Docker image (from sdks root directory)
cd /path/to/sdks
docker build -t openclaw-assistant -f Playground/openclaw-hybrid-assistant/Dockerfile .

# Run all tests
docker run --rm openclaw-assistant ./build/test-components --run-all

# Run extensive test suite
docker run --rm openclaw-assistant ./tests/scripts/extensive-test.sh
```

### Option 2: Lima VM

```bash
# Install Lima
brew install lima

# Start Ubuntu VM
limactl start --name=ubuntu template://ubuntu

# SSH and build
limactl shell ubuntu
cd /path/to/openclaw-hybrid-assistant
./build.sh
```

## Troubleshooting

### Wake word not detecting
- Lower the threshold: `--wakeword-threshold 0.3`
- Check audio levels with `arecord -l`
- Ensure microphone is working: `arecord -d 5 test.wav && aplay test.wav`

### VAD too sensitive / not sensitive enough
- Adjust silence duration in code (default: 1.5s)
- Check ambient noise levels

### WebSocket connection failing
- Verify OpenClaw is running: `curl http://localhost:18789/health`
- Check voice-assistant channel is enabled in OpenClaw config
- Verify port 8082 is accessible

## License

MIT
