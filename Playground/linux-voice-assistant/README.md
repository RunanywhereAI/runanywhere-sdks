# Linux Voice Assistant

A complete on-device voice AI pipeline for Linux (Raspberry Pi 5, x86_64, ARM64). All inference runs locally — no cloud, no API keys.

**Pipeline:** Wake Word -> VAD -> STT -> LLM -> TTS

## Architecture

```text
Microphone (ALSA)
    │
    ▼
Wake Word Detection (openWakeWord / "Hey Jarvis")  [optional]
    │
    ▼
Voice Activity Detection (Silero VAD)
    │  Buffers speech, detects silence timeout
    ▼
Speech-to-Text (Whisper Tiny EN)
    │
    ▼
Large Language Model (Qwen2.5 0.5B Q4)
    │
    ▼
Text-to-Speech (Piper Lessac Medium)
    │
    ▼
Speaker (ALSA)
```

## Project Structure

```text
linux-voice-assistant/
├── src/
│   ├── main.cpp                    # Entry point, CLI parsing, main loop
│   ├── audio/
│   │   ├── audio_capture.h/cpp     # ALSA mic input (16kHz, 16-bit PCM, mono)
│   │   └── audio_playback.h/cpp    # ALSA speaker output (multi-rate)
│   ├── pipeline/
│   │   └── voice_pipeline.h/cpp    # Full pipeline: VAD -> STT -> LLM -> TTS
│   └── config/
│       └── model_config.h          # Model paths, IDs, availability checks
├── tests/
│   └── test_pipeline.cpp           # Feed WAV file through pipeline (no mic needed)
├── scripts/
│   └── download-models.sh          # Download all required models
├── CMakeLists.txt                  # Build configuration
├── build.sh                        # End-to-end build script
└── README.md
```

## Quick Start

### Prerequisites

- Linux (Raspberry Pi 5, Ubuntu, Debian, etc.)
- CMake 3.16+
- C++20 compiler (g++ or clang++)
- ALSA development headers: `sudo apt install libasound2-dev`

### Build and Run

```bash
# 1. Build everything (SDK + models + assistant)
./build.sh

# 2. Run the voice assistant
./build/voice-assistant

# With wake word detection:
./build/voice-assistant --wakeword
```

### Manual Build

```bash
# Step 1: Download Sherpa-ONNX
cd ../../sdk/runanywhere-commons
./scripts/linux/download-sherpa-onnx.sh

# Step 2: Build runanywhere-commons
./scripts/build-linux.sh --shared

# Step 3: Download models
cd ../../Playground/linux-voice-assistant
./scripts/download-models.sh

# Step 4: Build
mkdir -p build && cd build
cmake ..
cmake --build . -j$(nproc)

# Step 5: Run
./voice-assistant
```

## Models

| Component | Model | Size | Framework |
|-----------|-------|------|-----------|
| VAD | Silero VAD | ~2 MB | ONNX |
| STT | Whisper Tiny EN | ~150 MB | ONNX (Sherpa) |
| LLM | Qwen2.5 0.5B Q4 | ~500 MB | llama.cpp |
| TTS | Piper Lessac Medium | ~65 MB | ONNX (Sherpa) |
| Wake Word | openWakeWord "Hey Jarvis" | ~20 MB | ONNX |

Download models:

```bash
# Required models (VAD, STT, LLM, TTS)
./scripts/download-models.sh

# Optional: Wake word model
./scripts/download-models.sh --wakeword

# Select a different LLM:
./scripts/download-models.sh --model qwen3-1.7b
./scripts/download-models.sh --model llama-3.2-3b
./scripts/download-models.sh --model qwen3-4b
```

## Usage

```bash
# Basic usage (always listening)
./build/voice-assistant

# With wake word ("Hey Jarvis" to activate)
./build/voice-assistant --wakeword

# Select audio devices
./build/voice-assistant --list-devices
./build/voice-assistant --input hw:1,0 --output hw:0,0

# Test pipeline with a WAV file (no microphone needed)
./build/test-pipeline path/to/audio.wav
```

## Components

### Audio Capture (`src/audio/audio_capture`)
- ALSA-based microphone input
- 16kHz, 16-bit PCM, mono (optimal for STT)
- Threaded capture with callback delivery
- Device enumeration support

### Audio Playback (`src/audio/audio_playback`)
- ALSA-based speaker output
- Dynamic sample rate reinitialization (22050Hz TTS, 16kHz, etc.)
- Underrun recovery

### Voice Pipeline (`src/pipeline/voice_pipeline`)
- **Wake Word Detection** — openWakeWord ONNX with "Hey Jarvis" model
- **Voice Activity Detection** — Silero VAD with silence timeout (1.5s)
- **Speech-to-Text** — Whisper Tiny EN via `rac_voice_agent_transcribe`
- **LLM Response** — Local inference via `rac_voice_agent_process_voice_turn`
- **Text-to-Speech** — Piper neural TTS via `rac_voice_agent_synthesize_speech`

### Model Config (`src/config/model_config`)
- Hardcoded model IDs and paths for predictable behavior
- Model availability checking before pipeline initialization
- Base directory: `~/.local/share/runanywhere/Models/`

## Troubleshooting

**"ALSA: Cannot open audio device"**
- Check available devices: `aplay -l` (output) and `arecord -l` (input)
- Try specifying a device: `--input hw:1,0`

**"Models are missing"**
- Run `./scripts/download-models.sh` to download all required models
- For wake word: `./scripts/download-models.sh --wakeword`

**No audio output**
- Check volume: `alsamixer`
- Verify output device: `speaker-test -D default -c 2`

**Slow LLM response on Raspberry Pi**
- Use a smaller model: `./scripts/download-models.sh --model qwen3-0.6b`
- Ensure adequate cooling (throttling reduces performance)
