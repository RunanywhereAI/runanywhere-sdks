# Linux Voice Assistant

A complete voice AI pipeline for Raspberry Pi 5 (and other Linux devices) using `runanywhere-commons` as the ML backend.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Linux Voice Assistant (This App)               │
│  • Audio capture/playback via ALSA                          │
│  • Voice pipeline orchestration                             │
│  • Simple command-line interface                            │
├─────────────────────────────────────────────────────────────┤
│              runanywhere-commons                             │
│  ┌─────────────────────────────────────────────────────────┐│
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

## Prerequisites

### Raspberry Pi 5 / Linux ARM64

```bash
# Install build tools
sudo apt update
sudo apt install -y build-essential cmake git wget curl

# Install audio development libraries
sudo apt install -y libasound2-dev libpulse-dev

# Verify ARM64
uname -m  # Should output: aarch64
```

### x86_64 Linux

```bash
# Install build tools
sudo apt update
sudo apt install -y build-essential cmake git wget curl

# Install audio development libraries
sudo apt install -y libasound2-dev libpulse-dev
```

## Build Instructions

### Step 1: Build runanywhere-commons

```bash
cd sdk/runanywhere-commons

# Download Sherpa-ONNX dependencies
./scripts/linux/download-sherpa-onnx.sh

# Build for Linux (shared libraries)
./scripts/build-linux.sh --shared
```

### Step 2: Download Models

```bash
cd playground/linux-voice-assistant

# Download all required models (~600MB total)
./scripts/download-models.sh
```

This downloads:
- **Silero VAD** (~2MB) - Voice Activity Detection
- **Whisper Tiny English** (~150MB) - Speech-to-Text
- **Qwen2.5 0.5B Instruct Q4** (~400MB) - Language Model
- **VITS Piper English US** (~50MB) - Text-to-Speech

### Step 3: Build the Application

```bash
cd playground/linux-voice-assistant

# Configure
cmake -B build

# Build
cmake --build build
```

### Step 4: Run

```bash
./build/voice-assistant
```

## Usage

```
Usage: ./voice-assistant [options]

Options:
  --list-devices    List available audio devices
  --input <device>  Audio input device (default: "default")
  --output <device> Audio output device (default: "default")
  --help            Show this help message

Controls:
  Ctrl+C            Exit the application
```

### Examples

```bash
# Run with default audio devices
./build/voice-assistant

# List available audio devices
./build/voice-assistant --list-devices

# Use specific audio devices
./build/voice-assistant --input plughw:1,0 --output plughw:0,0
```

## Project Structure

```
playground/linux-voice-assistant/
├── CMakeLists.txt          # Build configuration
├── README.md               # This file
├── main.cpp                # Entry point
├── model_config.h          # Pre-configured model IDs and paths
├── voice_pipeline.h        # Pipeline orchestration interface
├── voice_pipeline.cpp      # Pipeline implementation
├── audio_capture.h         # Audio input interface
├── audio_capture.cpp       # ALSA audio capture
├── audio_playback.h        # Audio output interface
├── audio_playback.cpp      # ALSA audio playback
└── scripts/
    └── download-models.sh  # Model download script
```

## Models

Models are stored in `~/.local/share/runanywhere/Models/`:

```
~/.local/share/runanywhere/Models/
├── ONNX/
│   ├── silero-vad/
│   │   └── silero_vad.onnx
│   ├── whisper-tiny-en/
│   │   ├── whisper-tiny.en-encoder.onnx
│   │   ├── whisper-tiny.en-decoder.onnx
│   │   └── tokens.txt
│   └── vits-piper-en-us/
│       ├── en_US-amy-medium.onnx
│       └── espeak-ng-data/
└── LlamaCpp/
    └── qwen2.5-0.5b-instruct-q4/
        └── qwen2.5-0.5b-instruct-q4_k_m.gguf
```

## Expected Performance (Raspberry Pi 5, CPU-only)

| Metric | Expected Value |
|--------|----------------|
| **STT Latency** | ~300-500ms per utterance |
| **LLM Tokens/sec** | ~5-10 tok/s |
| **TTS Latency** | ~100-200ms |
| **Total Pipeline** | ~2-3s per conversational turn |
| **Power** | ~5W |

## Troubleshooting

### No audio input

1. Check if ALSA can see your microphone:
   ```bash
   arecord -l
   ```

2. Test recording:
   ```bash
   arecord -d 5 -f S16_LE -r 16000 -c 1 test.wav
   aplay test.wav
   ```

3. Adjust microphone levels:
   ```bash
   alsamixer
   ```

### Models not found

Run the download script:
```bash
./scripts/download-models.sh
```

### ALSA errors

If you see "Cannot open audio device" errors:
1. Make sure no other application is using the audio device
2. Try a different device: `--input plughw:1,0`
3. Check permissions: `sudo usermod -a -G audio $USER` (logout/login required)

### Out of memory

The Qwen2.5 0.5B model requires ~500MB RAM. If you're running low on memory:
1. Close other applications
2. Consider using a smaller model

## License

MIT License - See LICENSE file for details.
