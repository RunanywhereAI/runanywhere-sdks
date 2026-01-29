# Raspberry Pi 5 Voice AI Pipeline Plan (CPU-Only)

**Target Device:** Raspberry Pi 5 (8GB) + External Audio Hardware + Billy Bass Animatronic Fish
**Goal:** Run complete voice AI pipeline (VAD → STT → LLM → TTS) on-device using CPU, driving a Billy Bass fish's mouth motor via GPIO + L298N motor driver
**SDK:** `runanywhere-commons` (C++ core library) + thin application layer
**Branch:** `smonga/rasp`
**Pi Details:** IP `192.168.1.91`, username `runanywhere`, OS: Raspberry Pi OS 64-bit Bookworm (Linux 6.12 aarch64)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Thin Application Layer (NEW)                    │
│  • Audio capture/playback via ALSA                          │
│  • Voice pipeline orchestration                              │
│  • Motor control via GPIO (Billy Bass fish)                  │
│  • Simple command-line interface                             │
├─────────────────────────────────────────────────────────────┤
│              runanywhere-commons (EXISTING)                  │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ VAD (CPU) - Silero via Sherpa-ONNX                      ││
│  │ STT (CPU) - Whisper via Sherpa-ONNX                     ││
│  │ LLM (CPU) - llama.cpp with GGUF models                  ││
│  │ TTS (CPU) - Sherpa-ONNX VITS/Piper                      ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│              External Hardware                               │
│  • USB Microphone (input)                                    │
│  • USB Speaker / DAC (output)                                │
│  • Billy Bass Fish (motor via L298N driver + GPIO)           │
└─────────────────────────────────────────────────────────────┘
```

---

## Directory Structure (Committed to `smonga/rasp`)

```
sdks/
├── playground/
│   └── linux-voice-assistant/          # Voice assistant application
│       ├── CMakeLists.txt              # Build config (links against runanywhere-commons)
│       ├── build.sh                    # One-click build script (all steps)
│       ├── main.cpp                    # Entry point with CLI (--list-devices, --input, --output)
│       ├── model_config.h              # Pre-configured model IDs, paths, availability checks
│       ├── voice_pipeline.h            # VoicePipeline class (wraps rac_voice_agent)
│       ├── voice_pipeline.cpp          # VAD → STT → LLM → TTS orchestration
│       ├── audio_capture.h             # AudioCapture class (ALSA mic input)
│       ├── audio_capture.cpp           # ALSA capture implementation (16kHz, mono, 16-bit)
│       ├── audio_playback.h            # AudioPlayback class (ALSA speaker output)
│       ├── audio_playback.cpp          # ALSA playback implementation
│       ├── README.md                   # Usage docs
│       └── scripts/
│           └── download-models.sh      # Downloads all 4 models (~600MB)
│
├── sdk/runanywhere-commons/
│   ├── VERSIONS                        # MODIFIED: added SHERPA_ONNX_VERSION_LINUX=1.12.23
│   ├── scripts/
│   │   ├── build-linux.sh              # NEW: Linux build script (x86_64/aarch64)
│   │   └── linux/
│   │       └── download-sherpa-onnx.sh # NEW: Downloads Sherpa-ONNX v1.12.23 + C API headers
│   └── src/backends/
│       ├── onnx/CMakeLists.txt         # MODIFIED: added RAC_PLATFORM_LINUX block
│       └── llamacpp/CMakeLists.txt     # MODIFIED: added RAC_PLATFORM_LINUX block (NEON, no GPU)
│
└── raspberry_pi5_hailo_voice_pipeline.md  # This plan document
```

---

## What Each File Does

### runanywhere-commons changes (SDK layer)

- **`sdk/runanywhere-commons/VERSIONS`** — Single source of truth for dependency versions. We added `SHERPA_ONNX_VERSION_LINUX=1.12.23`. All scripts read from this file via `source scripts/load-versions.sh`.

- **`sdk/runanywhere-commons/scripts/build-linux.sh`** — Main build script for runanywhere-commons on Linux. Detects architecture (x86_64 or aarch64), downloads Sherpa-ONNX if missing, runs CMake to build `librac_commons.so`, `librac_backend_onnx.so`, `librac_backend_llamacpp.so`, then copies them to `dist/linux/{arch}/`. Flags: `--clean`, `--shared`. LlamaCPP is fetched via CMake FetchContent (needs internet on first build).

- **`sdk/runanywhere-commons/scripts/linux/download-sherpa-onnx.sh`** — Downloads Sherpa-ONNX v1.12.23 pre-built binaries for Linux. The v1.12.23+ release uses `-shared-cpu` suffix in the tarball name and does NOT include headers — the script downloads the C API header separately from GitHub raw. Output goes to `third_party/sherpa-onnx-linux/` with `lib/` and `include/` subdirs.

- **`sdk/runanywhere-commons/src/backends/onnx/CMakeLists.txt`** — Added `elseif(RAC_PLATFORM_LINUX)` block that sets up Sherpa-ONNX as an imported shared library from `third_party/sherpa-onnx-linux/`. Links supporting libs (sherpa-onnx-core, piper_phonemize, espeak-ng, etc.) via a foreach loop checking for each `.so`.

- **`sdk/runanywhere-commons/src/backends/llamacpp/CMakeLists.txt`** — Added `elseif(RAC_PLATFORM_LINUX)` block. Enables ARM NEON for aarch64 (Pi 5 has Cortex-A76). Disables all GPU backends (Metal, CUDA, Vulkan, OpenCL, HipBLAS, SYCL). Links `pthread dl`.

### Application layer (playground/)

- **`playground/linux-voice-assistant/model_config.h`** — Header-only. Defines hardcoded model IDs (`silero-vad`, `whisper-tiny-en`, `qwen2.5-0.5b-instruct-q4`, `vits-piper-en-us`). Contains `ModelConfig` structs with metadata (name, filename, category, format, framework, memory). Provides `init_model_system()` (sets base dir to `~/.local/share/runanywhere`), `get_model_path()` helpers, `are_all_models_available()`, and `print_model_status()`.

- **`playground/linux-voice-assistant/voice_pipeline.h/cpp`** — Wraps the `rac_voice_agent` C API. Uses `rac_voice_agent_create_standalone()` to create the pipeline, then loads models via `rac_voice_agent_load_stt_model()`, `rac_voice_agent_load_llm_model()`, `rac_voice_agent_load_tts_voice()`. The `process_audio()` method converts int16→float, runs VAD via `rac_voice_agent_detect_speech()`, accumulates speech audio, and on speech-end calls `rac_voice_agent_process_voice_turn()` for the full STT→LLM→TTS pipeline. Callbacks: `on_voice_activity`, `on_transcription`, `on_response`, `on_audio_output`, `on_error`.

- **`playground/linux-voice-assistant/audio_capture.h/cpp`** — ALSA-based microphone input. Opens PCM device in capture mode (16kHz, mono, 16-bit). Runs a capture thread that calls `snd_pcm_readi()` in a loop and invokes a user callback with each audio chunk. Handles EPIPE (overrun) recovery. Provides `list_devices()` static method.

- **`playground/linux-voice-assistant/audio_playback.h/cpp`** — ALSA-based speaker output. Opens PCM device in playback mode (22050Hz default — matches TTS output). `play()` writes samples via `snd_pcm_writei()`. `reinitialize()` allows changing sample rate if TTS outputs at a different rate. Handles underrun recovery.

- **`playground/linux-voice-assistant/main.cpp`** — Entry point. Parses CLI args (`--list-devices`, `--input <dev>`, `--output <dev>`, `--help`). Initializes audio capture, audio playback, and voice pipeline. Connects them: capture callback feeds `pipeline.process_audio()`, pipeline's `on_audio_output` callback feeds `playback.play()`. Runs until Ctrl+C (SIGINT/SIGTERM handler).

- **`playground/linux-voice-assistant/CMakeLists.txt`** — Links against `rac_commons`, `rac_backend_onnx`, `rac_backend_llamacpp`, `sherpa-onnx-c-api`, `onnxruntime`, ALSA, threads, dl. Sets RPATH so the executable finds `.so` files at runtime. Optional PulseAudio support.

- **`playground/linux-voice-assistant/build.sh`** — One-click build: checks prerequisites, downloads Sherpa-ONNX, builds runanywhere-commons, downloads models, builds voice assistant. Flags: `--clean`, `--models` (download only).

- **`playground/linux-voice-assistant/scripts/download-models.sh`** — Downloads all 4 models (~600MB total) to `~/.local/share/runanywhere/Models/`. Sources: Silero VAD from GitHub, Whisper from Sherpa-ONNX releases, Qwen2.5 from HuggingFace, Piper TTS from Sherpa-ONNX releases. Supports `--force` flag.

---

## Implementation Checklist

### Phase 1: Linux ARM64 Build Support — COMPLETED

All code written and committed to `smonga/rasp`.

- [x] **1.1** Create `sdk/runanywhere-commons/scripts/build-linux.sh`
- [x] **1.2** Create `sdk/runanywhere-commons/scripts/linux/download-sherpa-onnx.sh`
- [x] **1.3** Update `src/backends/onnx/CMakeLists.txt` — added `elseif(RAC_PLATFORM_LINUX)` block
- [x] **1.4** Update `src/backends/llamacpp/CMakeLists.txt` — added Linux block with NEON, no GPU
- [x] **1.5** Update `VERSIONS` — `SHERPA_ONNX_VERSION_LINUX=1.12.23`

### Phase 2: Pi 5 Setup — COMPLETED

- [x] **2.1** Pi 5 hardware ready (monitor, keyboard, mouse connected)
- [x] **2.2** Pi OS booted, IP: `192.168.1.91`, user: `runanywhere`
- [x] **2.3** SSH set up from Mac (key: `~/.ssh/id_pi`)
- [x] **2.4** Prerequisites installed: `build-essential cmake git curl wget libasound2-dev libpulse-dev`
- [x] **2.5** Sherpa-ONNX v1.12.23 downloaded successfully (verified: `lib/libsherpa-onnx-c-api.so` + `include/sherpa-onnx/c-api/c-api.h`)
- [x] **2.6** Repo cloned on Pi via git

### Phase 3: Application Layer — COMPLETED

All code written and committed to `smonga/rasp`.

- [x] **3.1** Directory structure, CMakeLists.txt, build.sh
- [x] **3.2** `model_config.h` — pre-configured model IDs, path resolution, availability checks
- [x] **3.3** `scripts/download-models.sh` — downloads all 4 models
- [x] **3.4** ALSA audio capture (audio_capture.h/cpp)
- [x] **3.5** ALSA audio playback (audio_playback.h/cpp)
- [x] **3.6** Voice pipeline (voice_pipeline.h/cpp) — uses `rac_voice_agent_create_standalone()` API
- [x] **3.7** Main entry point (main.cpp) — CLI with device selection
- [x] **3.8** README.md

### Phase 4: Build & Test on Pi 5 — COMPLETED

All steps completed on Raspberry Pi 5 directly. Full pipeline verified.

#### 4.1 Clone the repo on Pi

```bash
cd ~
git clone <repo-url> --branch smonga/rasp runanywhere-sdks
cd runanywhere-sdks
```

#### 4.2 Download Sherpa-ONNX for Linux ARM64

```bash
cd sdk/runanywhere-commons
chmod +x scripts/linux/download-sherpa-onnx.sh scripts/build-linux.sh
bash scripts/linux/download-sherpa-onnx.sh
```

Expected: `third_party/sherpa-onnx-linux/lib/libsherpa-onnx-c-api.so` and `third_party/sherpa-onnx-linux/include/sherpa-onnx/c-api/c-api.h`

#### 4.3 Build runanywhere-commons (shared libs)

```bash
bash scripts/build-linux.sh --shared
```

Expected output in `dist/linux/aarch64/`:

- `librac_commons.so`
- `librac_backend_onnx.so`
- `librac_backend_llamacpp.so`

**Note:** This fetches llama.cpp via CMake FetchContent on first build — needs internet and may be slow.

**Likely issues:** This is the first ever build on Linux aarch64. Expect CMake errors related to:

- Missing include paths or headers in the runanywhere-commons C API
- Sherpa-ONNX header path structure not matching what CMake expects
- llama.cpp FetchContent version compatibility
- Platform-specific code guarded by `#ifdef __APPLE__` without Linux equivalents

When fixing, focus on the `sdk/runanywhere-commons/` files — the CMakeLists.txt files in `src/backends/onnx/` and `src/backends/llamacpp/`, and the main `CMakeLists.txt`. Read the full error output carefully.

#### 4.4 Download AI models (~600MB total)

```bash
cd ../../playground/linux-voice-assistant
chmod +x scripts/download-models.sh build.sh
bash scripts/download-models.sh
```

Downloads to `~/.local/share/runanywhere/Models/`:

- `ONNX/silero-vad/` (~2MB) — Silero VAD
- `ONNX/whisper-tiny-en/` (~150MB) — Whisper Tiny English (encoder + decoder + tokens)
- `LlamaCpp/qwen2.5-0.5b-instruct-q4/` (~400MB) — Qwen2.5 0.5B GGUF
- `ONNX/vits-piper-en-us/` (~50MB) — Piper TTS with espeak-ng data

#### 4.5 Build voice assistant application

```bash
cd playground/linux-voice-assistant
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . -j4
```

Expected: `build/voice-assistant` executable.

**Likely issues:** The app's CMakeLists.txt links against runanywhere-commons libs. If step 4.3 produced libs in a different location or with different names, update the paths in `playground/linux-voice-assistant/CMakeLists.txt`. The `RAC_COMMONS_DIR` and `RAC_COMMONS_DIST` variables at the top of CMakeLists.txt control where it looks.

Also the app includes headers from `sdk/runanywhere-commons/include/rac/` — particularly:

- `rac/features/voice_agent/rac_voice_agent.h`
- `rac/features/stt/rac_stt_component.h`
- `rac/features/tts/rac_tts_component.h`
- `rac/features/vad/rac_vad_component.h`
- `rac/features/llm/rac_llm_component.h`
- `rac/core/rac_error.h`
- `rac/infrastructure/model_management/rac_model_paths.h`
- `rac/infrastructure/model_management/rac_model_registry.h`

If any of these don't exist or have different names, you'll need to check what headers actually exist in `sdk/runanywhere-commons/include/rac/` and update the `#include` paths in the voice assistant code accordingly.

#### 4.6 Test the voice assistant

```bash
# List audio devices
./build/voice-assistant --list-devices

# Run with defaults
./build/voice-assistant

# Run with specific devices
./build/voice-assistant --input plughw:1,0 --output plughw:0,0
```

#### 4.7 Fix compilation errors

This is a first-time build on a new platform. Expect iterative debugging. The key files to modify when fixing errors:

| Error type | File to fix |
| --- | --- |
| runanywhere-commons CMake errors | `sdk/runanywhere-commons/src/backends/onnx/CMakeLists.txt` or `llamacpp/CMakeLists.txt` |
| Missing runanywhere-commons headers | Check `sdk/runanywhere-commons/include/rac/` for actual header names |
| Voice assistant link errors | `playground/linux-voice-assistant/CMakeLists.txt` |
| Voice assistant compile errors | The `.h/.cpp` files in `playground/linux-voice-assistant/` |
| Model path issues | `playground/linux-voice-assistant/model_config.h` |

#### 4.8 End-to-end voice test

With USB mic + speaker connected, run `./build/voice-assistant` and speak. Expected flow:

1. VAD detects speech start → prints `[Listening...]`
2. VAD detects speech end → prints `[Processing...]`
3. STT transcribes → prints `[USER] <text>`
4. LLM generates response → prints `[ASSISTANT] <text>`
5. TTS synthesizes audio → plays through speaker

---

## Known Issues & Fixes Applied

| Issue | Fix |
| --- | --- |
| Sherpa-ONNX v1.12.23 uses `-shared-cpu` suffix | Updated download URL in `download-sherpa-onnx.sh` |
| Sherpa-ONNX v1.12.23 doesn't include headers | Script downloads C API header from GitHub raw |
| rsync excluded `build-linux.sh` (matched `build*`) | Clone via git instead of rsync |
| Missing `#include <algorithm>` in `model_paths.cpp` | Added include for `std::find` |
| Code used `RAC_RESULT_SUCCESS` (doesn't exist) | Changed to `RAC_SUCCESS` (defined in `rac_types.h`) |
| Backends not registered (no providers for STT/LLM/TTS) | Added `rac_backend_onnx_register()` + `rac_backend_llamacpp_register()` in `main.cpp` |
| TTS model URL 404 (k2-fsa Amy model removed) | Switched to Lessac model from `RunanywhereAI/sherpa-onnx` releases (tar.gz) |
| STT fails with file path (decoder.onnx not found) | Pass directory path to STT (ONNX backend scans for encoder/decoder/tokens) |
| Missing `#include <cstring>` for `strdup` | Added include |
| Missing `#include <sys/stat.h>` for `stat` | Added include |
| VAD triggers on tiny chunks → empty transcription | Rewrote `process_audio()` with iOS-style debouncing: 1.5s silence timeout + 16,000 sample minimum buffer (matches `VoiceSession.swift`) |

## Build & Test Results (Phase 4)

**Date:** 2026-01-26
**Platform:** Raspberry Pi 5 (8GB), Debian Bookworm aarch64, GCC 12.2, CMake 3.25.1

### Build Output

```
dist/linux/aarch64/
  librac_commons.so         574K
  librac_backend_onnx.so    167K
  librac_backend_llamacpp.so 4.1M
  libsherpa-onnx-c-api.so   4.6M
  libonnxruntime.so          30M
```

### End-to-End Pipeline Test (synthetic WAV input)

```
Input:  espeak-ng "Hello, how are you doing today?" → 16kHz mono WAV (2.0s)
STT:    " Hello, how are you doing today?"   (Whisper Tiny, loaded in 861ms)
LLM:    "Hello! I'm just a computer program, so I don't have feelings.
         How can I assist you today?"          (Qwen2.5 0.5B Q4, 23 tokens)
TTS:    106,387 samples / 4.82s at 22050Hz    (Piper Lessac, synthesis ~4.8s)
```

### Test Tool

`test-pipeline` binary reads a WAV file and runs the full pipeline without ALSA:
```bash
./build/test-pipeline /path/to/input.wav
# Outputs: transcription, LLM response, TTS audio saved to /tmp/tts_output.wav
```

---

## Key Technical Details

### Voice Pipeline API

The app uses `rac_voice_agent_create_standalone()` which orchestrates the full pipeline:

- `rac_voice_agent_load_stt_model()` — loads Whisper model
- `rac_voice_agent_load_llm_model()` — loads Qwen2.5 GGUF model
- `rac_voice_agent_load_tts_voice()` — loads Piper TTS voice
- `rac_voice_agent_detect_speech()` — VAD on audio chunks
- `rac_voice_agent_process_voice_turn()` — full STT → LLM → TTS turn

### Model Storage

```
~/.local/share/runanywhere/Models/
├── ONNX/
│   ├── silero-vad/             # ~2MB
│   ├── whisper-tiny-en/        # ~150MB
│   └── vits-piper-en-us/       # ~50MB
└── LlamaCpp/
    └── qwen2.5-0.5b-instruct-q4/  # ~400MB
```

### Audio Config

- **Capture:** ALSA, 16kHz, mono, 16-bit PCM, 512 frame buffer
- **Playback:** ALSA, 22050Hz (TTS output rate), mono, 16-bit PCM

---

## Design Decisions

1. **CPU-only** — No Hailo NPU acceleration for MVP
2. **C API** — Direct `rac_*` C function calls, no Python bindings
3. **External audio** — USB mic/speaker via ALSA
4. **Pre-configured models** — Hardcoded in `model_config.h`, no runtime selection
5. **Voice Agent API** — Uses `rac_voice_agent_create_standalone()` (recommended high-level API)
6. **Playground directory** — App lives in `playground/linux-voice-assistant/`, not inside runanywhere-commons

---

## Hardware

| Component | Specification |
| --- | --- |
| **Board** | Raspberry Pi 5 (8GB) |
| **OS** | Raspberry Pi OS 64-bit Bookworm (Linux 6.12 aarch64) |
| **Storage** | microSD (32GB+) |
| **Audio Input** | USB Microphone |
| **Audio Output** | USB Speaker / DAC |
| **Animatronic** | Billy Bass fish (mouth motor) |
| **Motor Driver** | L298N dual H-bridge module |
| **Motor Power** | Billy Bass AA battery pack (original fish batteries) |

---

## Billy Bass Hardware Integration

### Overview

The project drives a Big Mouth Billy Bass animatronic fish using the Raspberry Pi 5. The Pi controls the fish's mouth motor through an L298N motor driver board, while the fish's original AA battery pack provides motor power. The Pi does **not** power the motor directly — it only sends GPIO control signals. The goal is to sync the fish's mouth movement with TTS audio output, making the fish "speak" the LLM's response.

### Wiring Diagram

```
┌──────────────────┐         ┌──────────────────┐         ┌──────────────┐
│  Raspberry Pi 5  │         │   L298N Motor     │         │  Billy Bass  │
│                  │         │   Driver Board    │         │  Fish Motor  │
│                  │         │                   │         │              │
│  Pin 11 (GPIO17) ├────────►│ IN1              │         │              │
│  Pin 12 (GPIO18) ├────────►│ IN2              │         │              │
│                  │         │                   │         │              │
│  Pin 6  (GND)   ├────────►│ GND    OUT1 ─────├────────►│ Motor Wire 1 │
│                  │         │        OUT2 ─────├────────►│ Motor Wire 2 │
│                  │         │                   │         │              │
└──────────────────┘         │  12V/VIN ◄───────┤         └──────────────┘
                             │  GND     ◄───────┤
                             └──────────────────┘
                                     ▲
                             ┌───────┴───────┐
                             │ AA Battery Pack│
                             │  (from fish)   │
                             │  + → 12V/VIN   │
                             │  - → GND       │
                             └───────────────┘
```

### Wiring Connections (Exact)

#### Pi → L298N (control signals + shared ground)

| Pi Pin | Pi Function | L298N Pin | Purpose |
| --- | --- | --- | --- |
| **Pin 6** | GND | GND | Common ground (required for GPIO signals to work) |
| **Pin 11** | GPIO17 | IN1 | Motor direction control line 1 |
| **Pin 12** | GPIO18 | IN2 | Motor direction control line 2 |

#### Battery → L298N (motor power)

| Battery | L298N Pin | Purpose |
| --- | --- | --- |
| **+ (positive)** | 12V / VIN | Motor power supply input |
| **- (negative)** | GND | Motor power ground (shared with Pi GND) |

#### L298N → Fish Motor (output)

| L298N Pin | Motor | Purpose |
| --- | --- | --- |
| **OUT1** | Motor wire 1 | Motor output A |
| **OUT2** | Motor wire 2 | Motor output B |

### How It Works

1. **Power isolation**: The Pi is powered by its own USB-C supply. The fish motor is powered by the fish's original AA battery pack through the L298N. They share a common ground so GPIO signals have a correct voltage reference.

2. **Motor control via IN1/IN2**: The L298N interprets the two input lines to control the motor:
   - `IN1=HIGH, IN2=LOW` → Motor spins one direction (mouth open)
   - `IN1=LOW, IN2=HIGH` → Motor spins other direction (mouth close)
   - `IN1=LOW, IN2=LOW` → Motor stopped (coast)
   - `IN1=HIGH, IN2=HIGH` → Motor braked

3. **Direction note**: If the mouth moves the wrong way (e.g., opens when it should close), either swap the two motor wires on OUT1/OUT2, or swap the IN1/IN2 logic in software.

4. **ENA/ENB jumper**: The L298N has enable jumpers (ENA for Motor A channel). With the jumper in place (default), the channel is always enabled at full speed. Removing the jumper and connecting it to a PWM-capable GPIO pin would allow speed control.

5. **5V pin on L298N**: Not connected in this setup. The Pi stays powered from USB-C. The L298N's onboard voltage regulator handles its own logic-level power from the battery input (when VIN > 7V and the 5V jumper is in place).

### Ground Chain

All three ground references are tied together for the circuit to function:

```
Battery (-) ──► L298N GND ──► Pi Pin 6 (GND)
```

Without this common ground, the Pi's GPIO HIGH/LOW signals would have no reference relative to the L298N's logic inputs, causing erratic or no motor response.

---

## Expected Performance (CPU-Only)

| Metric | Expected Value |
| --- | --- |
| **STT Latency** | ~300-500ms per utterance |
| **LLM Tokens/sec** | ~5-10 tok/s |
| **TTS Latency** | ~100-200ms |
| **Total Pipeline** | ~2-3s per conversational turn |
| **Power** | ~5W |

---

## Future: Hailo NPU Acceleration

> Deferred — not needed for MVP

The Raspberry Pi AI Kit (Hailo 8L) can accelerate the STT encoder (~2x speedup). LLM/TTS remain on CPU.

---

**Last Updated:** 2026-01-26
**Branch:** `smonga/rasp`
**Status:** Full pipeline verified on Pi 5. STT→LLM→TTS working end-to-end with synthetic audio. VAD debouncing fix applied (iOS-style 1.5s silence timeout). Billy Bass fish wired via L298N motor driver (GPIO17/GPIO18 → IN1/IN2, OUT1/OUT2 → motor, AA battery pack for motor power).
