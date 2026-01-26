# Raspberry Pi 5 Voice AI Pipeline Plan (CPU-Only)

**Target Device:** Raspberry Pi 5 (8GB) + External Audio Hardware
**Goal:** Run complete voice AI pipeline (VAD → STT → LLM → TTS) on-device using CPU
**SDK:** `runanywhere-commons` (C++ core library) + thin application layer

---

## Executive Summary

The Raspberry Pi 5 requires building `runanywhere-commons` for **Linux ARM64 (aarch64)**. The current codebase already has Linux detection in CMake but lacks:
1. Linux ARM64 build scripts
2. Sherpa-ONNX Linux ARM64 integration

**Approach:** Use existing runanywhere-commons infrastructure with a thin application layer on top.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Thin Application Layer (NEW)                    │
│  • Audio capture/playback via external hardware              │
│  • Voice pipeline orchestration                              │
│  • Simple command-line or daemon interface                   │
├─────────────────────────────────────────────────────────────┤
│              runanywhere-commons (EXISTING)                  │
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

---

## Phase 1: Linux ARM64 Build Support

**Objective:** Get runanywhere-commons building on Raspberry Pi 5.

### Task 1.1: Create Linux ARM64 Build Script

- [ ] Create `sdk/runanywhere-commons/scripts/build-linux.sh`
- [ ] Support both x86_64 and aarch64 architectures

**File to create:** `sdk/runanywhere-commons/scripts/build-linux.sh`

### Task 1.2: Create Linux Dependency Download Scripts

- [ ] Create `sdk/runanywhere-commons/scripts/linux/download-sherpa-onnx.sh`

**File to create:** `sdk/runanywhere-commons/scripts/linux/download-sherpa-onnx.sh`

```bash
#!/bin/bash
# Download Sherpa-ONNX pre-built binaries for Linux

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../load-versions.sh"

VERSION="${SHERPA_ONNX_VERSION_LINUX:-1.12.18}"
ARCH=$(uname -m)
DEST_DIR="${SCRIPT_DIR}/../../third_party/sherpa-onnx-linux"

if [ "$ARCH" = "aarch64" ]; then
    URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${VERSION}/sherpa-onnx-v${VERSION}-linux-aarch64-shared.tar.bz2"
elif [ "$ARCH" = "x86_64" ]; then
    URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${VERSION}/sherpa-onnx-v${VERSION}-linux-x86_64-shared.tar.bz2"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

echo "Downloading Sherpa-ONNX v${VERSION} for ${ARCH}..."
mkdir -p "$DEST_DIR"
curl -L "$URL" | tar -xj -C "$DEST_DIR" --strip-components=1

echo "Sherpa-ONNX downloaded to: $DEST_DIR"
```

### Task 1.3: Update CMake for Linux Sherpa-ONNX Support

**File:** `sdk/runanywhere-commons/src/backends/onnx/CMakeLists.txt`

Add Linux platform support after macOS block (after line 122):

```cmake
elseif(RAC_PLATFORM_LINUX)
    set(SHERPA_ONNX_ROOT "${RUNANYWHERE_COMMONS_ROOT}/third_party/sherpa-onnx-linux")

    if(EXISTS "${SHERPA_ONNX_ROOT}/lib/libsherpa-onnx-c-api.so")
        set(SHERPA_ONNX_AVAILABLE ON)
        set(SHERPA_LIB_PATH "${SHERPA_ONNX_ROOT}/lib/libsherpa-onnx-c-api.so")
        set(SHERPA_HEADER_PATH "${SHERPA_ONNX_ROOT}/include")

        add_library(sherpa_onnx SHARED IMPORTED GLOBAL)
        set_target_properties(sherpa_onnx PROPERTIES
            IMPORTED_LOCATION "${SHERPA_LIB_PATH}"
            INTERFACE_INCLUDE_DIRECTORIES "${SHERPA_HEADER_PATH}"
        )

        # Link supporting libraries if present
        set(SHERPA_ONNX_DEPS
            "sherpa-onnx-core" "sherpa-onnx-fst" "sherpa-onnx-fstfar"
            "sherpa-onnx-kaldifst-core" "kaldi-decoder-core" "kaldi-native-fbank-core"
            "piper_phonemize" "espeak-ng" "ucd"
        )

        foreach(dep ${SHERPA_ONNX_DEPS})
            if(EXISTS "${SHERPA_ONNX_ROOT}/lib/lib${dep}.so")
                add_library(sherpa_${dep} SHARED IMPORTED GLOBAL)
                set_target_properties(sherpa_${dep} PROPERTIES IMPORTED_LOCATION "${SHERPA_ONNX_ROOT}/lib/lib${dep}.so")
                target_link_libraries(sherpa_onnx INTERFACE sherpa_${dep})
            endif()
        endforeach()
    endif()
```

### Task 1.4: Update CMake for Linux llama.cpp Support

**File:** `sdk/runanywhere-commons/src/backends/llamacpp/CMakeLists.txt`

Add Linux platform block after macOS (after line 158):

```cmake
elseif(RAC_PLATFORM_LINUX)
    message(STATUS "Configuring LlamaCPP backend for Linux")

    # Enable ARM NEON for aarch64 (Raspberry Pi 5)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
        set(GGML_NEON ON CACHE BOOL "" FORCE)
        message(STATUS "Enabling NEON for Linux aarch64")
    endif()

    # Disable GPU backends not available on Pi
    set(GGML_METAL OFF CACHE BOOL "" FORCE)
    set(GGML_CUDA OFF CACHE BOOL "" FORCE)
    set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
    set(GGML_OPENCL OFF CACHE BOOL "" FORCE)
    set(GGML_HIPBLAS OFF CACHE BOOL "" FORCE)
    set(GGML_SYCL OFF CACHE BOOL "" FORCE)

    # Linux-specific link libraries
    target_link_libraries(rac_backend_llamacpp PUBLIC pthread dl)
```

### Task 1.5: Update VERSIONS File

**File:** `sdk/runanywhere-commons/VERSIONS`

Add Linux Sherpa-ONNX version (ONNX_VERSION_LINUX already exists):

```ini
SHERPA_ONNX_VERSION_LINUX=1.12.18
```

---

## Phase 2: Build Validation on Pi 5

**Objective:** Test and validate the build on actual Raspberry Pi 5 hardware.

### Task 2.1: Prerequisites on Raspberry Pi 5

```bash
# Install build tools
sudo apt update
sudo apt install -y build-essential cmake git wget curl

# Install audio development libraries
sudo apt install -y libasound2-dev libpulse-dev portaudio19-dev

# Verify ARM64
uname -m  # Should output: aarch64
```

### Task 2.2: Build Commands for Pi 5

```bash
cd sdk/runanywhere-commons

# 1. Download Sherpa-ONNX dependencies
./scripts/linux/download-sherpa-onnx.sh

# 2. Configure build
./scripts/build-linux.sh

# OR manual CMake:
cmake -B build-linux \
    -DCMAKE_BUILD_TYPE=Release \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BACKEND_LLAMACPP=ON \
    -DRAC_BACKEND_ONNX=ON \
    -DRAC_BACKEND_WHISPERCPP=OFF \
    -DRAC_BUILD_SHARED=ON

# 3. Build
cmake --build build-linux -j4

# 4. Verify outputs
ls -la build-linux/*.so
# Expected: librac_commons.so, librac_backend_llamacpp.so, librac_backend_onnx.so
```

---

## Phase 3: Thin Application Layer

**Objective:** Create a minimal application that uses runanywhere-commons for voice AI.

### Task 3.1: Create Application Directory

```
sdk/runanywhere-commons/examples/linux-voice-assistant/
├── CMakeLists.txt            # Build config
├── main.cpp                  # Entry point
├── model_config.h            # Pre-configured model IDs and registration
├── audio_capture.h           # Audio input abstraction
├── audio_capture.cpp         # ALSA/PulseAudio implementation
├── audio_playback.h          # Audio output abstraction
├── audio_playback.cpp        # ALSA/PulseAudio implementation
├── voice_pipeline.h          # Pipeline orchestration
├── voice_pipeline.cpp        # VAD → STT → LLM → TTS flow
├── scripts/
│   └── download-models.sh    # One-time model download script
└── README.md                 # Usage instructions
```

### Task 3.2: Voice Pipeline Orchestration

**File:** `voice_pipeline.h`

```cpp
#pragma once

#include <rac/rac_commons.h>
#include <string>
#include <functional>
#include <memory>

namespace runanywhere {

struct VoicePipelineConfig {
    // Callbacks only - model paths resolved via model_config.h
    std::function<void(const std::string&)> on_transcription;
    std::function<void(const std::string&)> on_response;
    std::function<void(const int16_t*, size_t)> on_audio_out;
};

class VoicePipeline {
public:
    // Uses pre-configured models from model_config.h
    explicit VoicePipeline(const VoicePipelineConfig& config);
    ~VoicePipeline();

    // Process audio chunk (16kHz, 16-bit PCM)
    void process_audio(const int16_t* samples, size_t num_samples);

    // Start/stop continuous processing
    void start();
    void stop();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace runanywhere
```

### Task 3.3: Main Application Entry Point

**File:** `main.cpp`

```cpp
#include "voice_pipeline.h"
#include "model_config.h"
#include "audio_capture.h"
#include "audio_playback.h"
#include <iostream>
#include <csignal>
#include <atomic>

std::atomic<bool> running{true};

void signal_handler(int) {
    running = false;
}

int main(int argc, char* argv[]) {
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    // Initialize runanywhere-commons
    rac_init(nullptr);

    // Initialize model system (sets base directory, creates registry)
    runanywhere::init_model_system();

    // Configure voice pipeline with callbacks only
    // (model paths are resolved internally via model_config.h)
    runanywhere::VoicePipelineConfig config{
        .on_transcription = [](const std::string& text) {
            std::cout << "[USER] " << text << std::endl;
        },
        .on_response = [](const std::string& text) {
            std::cout << "[ASSISTANT] " << text << std::endl;
        }
    };

    // Create pipeline (uses pre-configured models from model_config.h)
    runanywhere::VoicePipeline pipeline(config);

    // Start audio capture and pipeline
    runanywhere::AudioCapture capture;
    runanywhere::AudioPlayback playback;

    capture.set_callback([&pipeline](const int16_t* samples, size_t count) {
        pipeline.process_audio(samples, count);
    });

    config.on_audio_out = [&playback](const int16_t* samples, size_t count) {
        playback.play(samples, count);
    };

    std::cout << "Voice Assistant running. Press Ctrl+C to exit." << std::endl;
    std::cout << "Using models:" << std::endl;
    std::cout << "  VAD: " << runanywhere::VAD_MODEL_ID << std::endl;
    std::cout << "  STT: " << runanywhere::STT_MODEL_ID << std::endl;
    std::cout << "  LLM: " << runanywhere::LLM_MODEL_ID << std::endl;
    std::cout << "  TTS: " << runanywhere::TTS_MODEL_ID << std::endl;

    capture.start();
    pipeline.start();

    while (running) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    pipeline.stop();
    capture.stop();

    rac_cleanup();
    return 0;
}
```

### Task 3.4: CMakeLists.txt for Application

**File:** `examples/linux-voice-assistant/CMakeLists.txt`

```cmake
cmake_minimum_required(VERSION 3.16)
project(linux-voice-assistant)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find dependencies
find_package(ALSA REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(PULSEAUDIO libpulse libpulse-simple)

# Source files
set(SOURCES
    main.cpp
    voice_pipeline.cpp
    audio_capture.cpp
    audio_playback.cpp
)

# Create executable
add_executable(voice-assistant ${SOURCES})

# Link libraries
target_link_libraries(voice-assistant PRIVATE
    rac_commons
    rac_backend_onnx
    rac_backend_llamacpp
    ALSA::ALSA
)

if(PULSEAUDIO_FOUND)
    target_link_libraries(voice-assistant PRIVATE ${PULSEAUDIO_LIBRARIES})
    target_include_directories(voice-assistant PRIVATE ${PULSEAUDIO_INCLUDE_DIRS})
    target_compile_definitions(voice-assistant PRIVATE USE_PULSEAUDIO=1)
endif()

target_include_directories(voice-assistant PRIVATE
    ${CMAKE_SOURCE_DIR}/include
)
```

---

## Hardware Requirements

| Component | Specification |
|-----------|---------------|
| **Board** | Raspberry Pi 5 (4GB or 8GB recommended) |
| **Storage** | 32GB+ microSD or NVMe SSD (for models) |
| **Audio Input** | USB Microphone (ordered) |
| **Audio Output** | USB Speaker / DAC (ordered) |
| **OS** | Raspberry Pi OS (64-bit, Bookworm) |
| **Memory** | 8GB recommended for LLM inference |

---

## Model Configuration & Pre-Registration

### Model Folder Structure on Raspberry Pi

Models are stored following the runanywhere-commons convention:

```
~/.local/share/runanywhere/
└── Models/
    ├── ONNX/
    │   ├── whisper-tiny-en/              # STT model
    │   │   ├── whisper-tiny-en-encoder.onnx
    │   │   ├── whisper-tiny-en-decoder.onnx
    │   │   └── tokens.txt
    │   ├── silero-vad/                   # VAD model
    │   │   └── silero_vad.onnx
    │   └── vits-piper-en-us/             # TTS model
    │       ├── model.onnx
    │       ├── tokens.txt
    │       └── espeak-ng-data/
    └── LlamaCpp/
        └── qwen2.5-0.5b-instruct-q4/     # LLM model
            └── qwen2.5-0.5b-instruct-q4_k_m.gguf
```

### Pre-Configured Model Registration

The application layer will register models at startup using the existing `rac_model_registry` API. **No runtime selection** - models are hardcoded in a configuration header.

**File:** `examples/linux-voice-assistant/model_config.h`

```cpp
#pragma once

#include <rac/infrastructure/model_management/rac_model_registry.h>
#include <rac/infrastructure/model_management/rac_model_paths.h>
#include <rac/infrastructure/model_management/rac_model_types.h>

namespace runanywhere {

// Pre-configured model IDs (hardcoded - no runtime selection)
constexpr const char* VAD_MODEL_ID = "silero-vad";
constexpr const char* STT_MODEL_ID = "whisper-tiny-en";
constexpr const char* LLM_MODEL_ID = "qwen2.5-0.5b-instruct-q4";
constexpr const char* TTS_MODEL_ID = "vits-piper-en-us";

// Initialize model paths and registry
inline bool init_model_system() {
    // Set base directory for model storage
    const char* home = getenv("HOME");
    std::string base_dir = std::string(home) + "/.local/share/runanywhere";
    rac_model_paths_set_base_dir(base_dir.c_str());
    return true;
}

// Register the pre-configured models
inline bool register_models(rac_model_registry_handle_t registry) {
    // VAD Model
    rac_model_info_t* vad = rac_model_info_alloc();
    vad->id = strdup(VAD_MODEL_ID);
    vad->name = strdup("Silero VAD");
    vad->framework = RAC_FRAMEWORK_ONNX;
    vad->category = RAC_MODEL_CATEGORY_AUDIO;
    vad->format = RAC_MODEL_FORMAT_ONNX;
    vad->artifact_kind = RAC_ARTIFACT_KIND_SINGLE_FILE;
    rac_model_registry_save(registry, vad);
    rac_model_info_free(vad);

    // STT Model
    rac_model_info_t* stt = rac_model_info_alloc();
    stt->id = strdup(STT_MODEL_ID);
    stt->name = strdup("Whisper Tiny English");
    stt->framework = RAC_FRAMEWORK_ONNX;
    stt->category = RAC_MODEL_CATEGORY_SPEECH_RECOGNITION;
    stt->format = RAC_MODEL_FORMAT_ONNX;
    stt->artifact_kind = RAC_ARTIFACT_KIND_ARCHIVE;
    rac_model_registry_save(registry, stt);
    rac_model_info_free(stt);

    // LLM Model
    rac_model_info_t* llm = rac_model_info_alloc();
    llm->id = strdup(LLM_MODEL_ID);
    llm->name = strdup("Qwen2.5 0.5B Instruct Q4");
    llm->framework = RAC_FRAMEWORK_LLAMACPP;
    llm->category = RAC_MODEL_CATEGORY_LANGUAGE;
    llm->format = RAC_MODEL_FORMAT_GGUF;
    llm->artifact_kind = RAC_ARTIFACT_KIND_SINGLE_FILE;
    llm->memory_required = 500 * 1024 * 1024;  // ~500MB
    llm->context_length = 4096;
    rac_model_registry_save(registry, llm);
    rac_model_info_free(llm);

    // TTS Model
    rac_model_info_t* tts = rac_model_info_alloc();
    tts->id = strdup(TTS_MODEL_ID);
    tts->name = strdup("VITS Piper English US");
    tts->framework = RAC_FRAMEWORK_ONNX;
    tts->category = RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS;
    tts->format = RAC_MODEL_FORMAT_ONNX;
    tts->artifact_kind = RAC_ARTIFACT_KIND_ARCHIVE;
    rac_model_registry_save(registry, tts);
    rac_model_info_free(tts);

    return true;
}

// Get model path by ID (using rac_model_paths utilities)
inline std::string get_model_path(const char* model_id, rac_inference_framework_t framework,
                                   rac_model_format_t format) {
    char path[4096];
    rac_model_paths_get_expected_model_path(model_id, framework, format, path, sizeof(path));
    return std::string(path);
}

} // namespace runanywhere
```

### Updated Voice Pipeline Initialization

**File:** `voice_pipeline.cpp` (updated)

```cpp
#include "voice_pipeline.h"
#include "model_config.h"

namespace runanywhere {

struct VoicePipeline::Impl {
    rac_model_registry_handle_t registry;
    rac_stt_handle_t stt;
    rac_tts_handle_t tts;
    rac_vad_handle_t vad;
    rac_llm_handle_t llm;
    // ... other members
};

VoicePipeline::VoicePipeline(const VoicePipelineConfig& config) {
    impl_ = std::make_unique<Impl>();

    // Initialize model system (sets base directory)
    init_model_system();

    // Create and populate model registry
    rac_model_registry_create(&impl_->registry);
    register_models(impl_->registry);

    // Load models using pre-configured IDs
    std::string vad_path = get_model_path(VAD_MODEL_ID, RAC_FRAMEWORK_ONNX, RAC_MODEL_FORMAT_ONNX);
    std::string stt_path = get_model_path(STT_MODEL_ID, RAC_FRAMEWORK_ONNX, RAC_MODEL_FORMAT_ONNX);
    std::string llm_path = get_model_path(LLM_MODEL_ID, RAC_FRAMEWORK_LLAMACPP, RAC_MODEL_FORMAT_GGUF);
    std::string tts_path = get_model_path(TTS_MODEL_ID, RAC_FRAMEWORK_ONNX, RAC_MODEL_FORMAT_ONNX);

    // Initialize components with resolved paths
    rac_vad_create(&impl_->vad, vad_path.c_str());
    rac_stt_create(&impl_->stt, stt_path.c_str());
    rac_llm_create(&impl_->llm, llm_path.c_str());
    rac_tts_create(&impl_->tts, tts_path.c_str());
}

// ... rest of implementation

} // namespace runanywhere
```

### Model Download Script (One-Time Setup)

**File:** `examples/linux-voice-assistant/scripts/download-models.sh`

```bash
#!/bin/bash
# Download pre-configured models for the voice assistant

set -e

MODEL_DIR="${HOME}/.local/share/runanywhere/Models"
mkdir -p "$MODEL_DIR"

echo "Downloading models to: $MODEL_DIR"

# VAD: Silero VAD
echo "Downloading Silero VAD..."
mkdir -p "$MODEL_DIR/ONNX/silero-vad"
curl -L -o "$MODEL_DIR/ONNX/silero-vad/silero_vad.onnx" \
    "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"

# STT: Whisper Tiny English (via Sherpa-ONNX)
echo "Downloading Whisper Tiny English..."
mkdir -p "$MODEL_DIR/ONNX/whisper-tiny-en"
curl -L "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2" \
    | tar -xj -C "$MODEL_DIR/ONNX/whisper-tiny-en" --strip-components=1

# LLM: Qwen2.5 0.5B Instruct Q4
echo "Downloading Qwen2.5 0.5B..."
mkdir -p "$MODEL_DIR/LlamaCpp/qwen2.5-0.5b-instruct-q4"
curl -L -o "$MODEL_DIR/LlamaCpp/qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf" \
    "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"

# TTS: VITS Piper English US
echo "Downloading VITS Piper English..."
mkdir -p "$MODEL_DIR/ONNX/vits-piper-en-us"
curl -L "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-amy-medium.tar.bz2" \
    | tar -xj -C "$MODEL_DIR/ONNX/vits-piper-en-us" --strip-components=1

echo "All models downloaded successfully!"
echo "Model directory: $MODEL_DIR"
ls -la "$MODEL_DIR/ONNX" "$MODEL_DIR/LlamaCpp"
```

---

## Model Recommendations

| Task | Model | Size | Notes |
|------|-------|------|-------|
| **STT** | Whisper Tiny | ~150MB | Best for real-time on Pi 5 |
| **LLM** | Qwen2.5-0.5B-Q4 | ~400MB | Good balance of quality/speed |
| **TTS** | VITS (Piper) | ~50MB | Fast CPU synthesis |
| **VAD** | Silero VAD | ~2MB | Lightweight, CPU-only |

---

## Expected Performance (CPU-Only)

| Metric | Expected Value |
|--------|----------------|
| **STT Latency** | ~300-500ms per utterance |
| **LLM Tokens/sec** | ~5-10 tok/s |
| **TTS Latency** | ~100-200ms |
| **Total Pipeline** | ~2-3s per conversational turn |
| **Power** | ~5W |

---

## Implementation Checklist

### Phase 1: Linux ARM64 Build Support - COMPLETED

- [x] 1.1 Create `scripts/build-linux.sh`
- [x] 1.2 Create `scripts/linux/download-sherpa-onnx.sh`
- [x] 1.3 Update `src/backends/onnx/CMakeLists.txt` for Linux
- [x] 1.4 Update `src/backends/llamacpp/CMakeLists.txt` for Linux
- [x] 1.5 Add `SHERPA_ONNX_VERSION_LINUX` to VERSIONS file

### Phase 2: Build Validation - PENDING (requires Pi 5 hardware)

- [ ] 2.1 Test build on x86_64 Linux first
- [ ] 2.2 Test build on Raspberry Pi 5
- [ ] 2.3 Verify all shared libraries created

### Phase 3: Application Layer - COMPLETED

- [x] 3.1 Create `playground/linux-voice-assistant/` directory structure
- [x] 3.2 Create `model_config.h` with pre-configured model IDs and registration
- [x] 3.3 Create `scripts/download-models.sh` for one-time model download
- [x] 3.4 Implement audio capture (ALSA)
- [x] 3.5 Implement audio playback (ALSA)
- [x] 3.6 Implement voice pipeline orchestration using Voice Agent
- [ ] 3.7 Download models to Pi 5 and test end-to-end

---

## Files Created/Modified Summary

| File | Action | Status |
|------|--------|--------|
| `sdk/runanywhere-commons/scripts/build-linux.sh` | CREATE | DONE |
| `sdk/runanywhere-commons/scripts/linux/download-sherpa-onnx.sh` | CREATE | DONE |
| `sdk/runanywhere-commons/src/backends/onnx/CMakeLists.txt` | MODIFY | DONE |
| `sdk/runanywhere-commons/src/backends/llamacpp/CMakeLists.txt` | MODIFY | DONE |
| `sdk/runanywhere-commons/VERSIONS` | MODIFY | DONE |
| `playground/linux-voice-assistant/model_config.h` | CREATE | DONE |
| `playground/linux-voice-assistant/scripts/download-models.sh` | CREATE | DONE |
| `playground/linux-voice-assistant/voice_pipeline.h` | CREATE | DONE |
| `playground/linux-voice-assistant/voice_pipeline.cpp` | CREATE | DONE |
| `playground/linux-voice-assistant/audio_capture.h` | CREATE | DONE |
| `playground/linux-voice-assistant/audio_capture.cpp` | CREATE | DONE |
| `playground/linux-voice-assistant/audio_playback.h` | CREATE | DONE |
| `playground/linux-voice-assistant/audio_playback.cpp` | CREATE | DONE |
| `playground/linux-voice-assistant/CMakeLists.txt` | CREATE | DONE |
| `playground/linux-voice-assistant/main.cpp` | CREATE | DONE |
| `playground/linux-voice-assistant/README.md` | CREATE | DONE |

---

## Design Decisions

### C API is Sufficient (No Python Bindings)

The existing C API in runanywhere-commons (`rac_*` functions) is sufficient for the thin application layer. This is the least effort approach because:

- The application layer is written in C++ and links directly against `.so` libraries
- No need for ctypes/cffi/pybind11 wrapper overhead
- Full access to all runanywhere-commons functionality
- Python bindings can be added later if needed

---

## Future Enhancement: Hailo NPU Acceleration

> Deferred - not needed for MVP

The Raspberry Pi AI Kit (Hailo 8L) can be integrated later to accelerate the STT encoder:

- STT encoder on Hailo NPU (~2x speedup)
- LLM/TTS remain on CPU (Hailo-8L not suitable for these)

---

## References

- [Sherpa-ONNX Linux Releases](https://github.com/k2-fsa/sherpa-onnx/releases)
- [ONNX Runtime Linux ARM64](https://github.com/microsoft/onnxruntime/releases)
- [Raspberry Pi 5 Documentation](https://www.raspberrypi.com/documentation/)
- [ALSA Programming Guide](https://www.alsa-project.org/alsa-doc/alsa-lib/)

---

**Last Updated:** 2026-01-25
**Author:** Claude Code
**Status:** IMPLEMENTATION COMPLETE - Ready for testing on Pi 5

### Key Decisions Made

1. **CPU-only** - No Hailo acceleration for MVP
2. **C API sufficient** - No Python bindings needed
3. **External audio hardware** - USB mic/speaker ordered
4. **Thin application layer** - C++ app consuming runanywhere-commons
5. **Pre-configured models** - Models are hardcoded in `model_config.h`, no runtime selection
6. **Standard model folder structure** - Uses `~/.local/share/runanywhere/Models/{framework}/{modelId}/`
7. **Model registry at startup** - Models registered via `rac_model_registry_*` API during initialization
