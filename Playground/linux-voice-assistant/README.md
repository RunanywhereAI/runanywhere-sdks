# Linux Voice Assistant

A complete voice AI pipeline for Raspberry Pi 5 (and other Linux devices) using `runanywhere-commons` as the ML backend.

## Features

- **Wake Word Detection** - Say "Hey Jarvis" to activate
- **Voice Activity Detection (VAD)** - Silero VAD via Sherpa-ONNX
- **Speech-to-Text (STT)** - Whisper via Sherpa-ONNX
- **Large Language Model (LLM)** - llama.cpp with GGUF models
- **Text-to-Speech (TTS)** - Sherpa-ONNX VITS/Piper
- **Moltbot Integration** - Optional AI assistant framework with tool execution

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Linux Voice Assistant (This App)               │
│  • Audio capture/playback via ALSA                          │
│  • Voice pipeline orchestration                             │
│  • Wake word → VAD → STT → LLM → TTS                        │
├─────────────────────────────────────────────────────────────┤
│              runanywhere-commons                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Wake Word (CPU) - openWakeWord "Hey Jarvis"             ││
│  │ VAD (CPU) - Silero via Sherpa-ONNX                      ││
│  │ STT (CPU) - Whisper via Sherpa-ONNX                     ││
│  │ LLM (CPU) - llama.cpp with GGUF models                  ││
│  │ TTS (CPU) - Sherpa-ONNX VITS/Piper                      ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│              External Audio Hardware                         │
│  • USB Microphone (input)                                    │
│  • USB Speaker / DAC (output)                                │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### One-Line Install (Fresh Setup)

```bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/Playground/linux-voice-assistant/scripts/install.sh | bash
```

### Add to Existing Moltbot

```bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/Playground/linux-voice-assistant/scripts/add-to-moltbot.sh | bash
```

### Run

```bash
# Without wake word (always listening)
./build/voice-assistant

# With wake word (say "Hey Jarvis" to activate)
./build/voice-assistant --wakeword

# With Moltbot integration
./build/voice-assistant --wakeword --moltbot
```

## Documentation

| Document | Description |
|----------|-------------|
| [SETUP.md](SETUP.md) | Complete setup guide (build, models, configuration) |
| [docs/MOLTBOT_INTEGRATION.md](docs/MOLTBOT_INTEGRATION.md) | Detailed Moltbot integration guide |
| [docs/RELEASE.md](docs/RELEASE.md) | Release process documentation |

## Usage

```
Usage: ./voice-assistant [options]

Options:
  --list-devices    List available audio devices
  --input <device>  Audio input device (default: "default")
  --output <device> Audio output device (default: "default")
  --wakeword        Enable wake word detection ("Hey Jarvis")
  --moltbot         Enable Moltbot integration
  --moltbot-url     Moltbot voice bridge URL (default: "http://localhost:8081")
  --help            Show this help message

Controls:
  Ctrl+C            Exit the application
```

## Project Structure

```
Playground/linux-voice-assistant/
├── CMakeLists.txt          # Build configuration
├── README.md               # This file
├── SETUP.md                # Complete setup guide
├── main.cpp                # Entry point
├── model_config.h          # Pre-configured model IDs and paths
├── voice_pipeline.h        # Pipeline orchestration interface
├── voice_pipeline.cpp      # Pipeline implementation
├── audio_capture.h/cpp     # ALSA audio input
├── audio_playback.h/cpp    # ALSA audio output
├── docs/
│   ├── MOLTBOT_INTEGRATION.md
│   └── RELEASE.md
├── examples/
│   ├── moltbot-runanywhere-config.json
│   └── moltbot-runanywhere-config.yaml
└── scripts/
    ├── download-models.sh  # Model download script
    ├── install.sh          # One-line installer
    ├── add-to-moltbot.sh   # Add to existing Moltbot
    └── start-voice-bridge.ts
```

## Expected Performance (Raspberry Pi 5)

| Metric | Expected Value |
|--------|----------------|
| **Wake Word** | ~50-100ms detection |
| **VAD** | ~10-20ms detection |
| **STT Latency** | ~300-500ms per utterance |
| **LLM Tokens/sec** | ~5-10 tok/s |
| **TTS Latency** | ~100-200ms |
| **Total Pipeline** | ~2-3s per conversational turn |
| **Power** | ~5-8W |

## License

MIT License - See LICENSE file for details.
