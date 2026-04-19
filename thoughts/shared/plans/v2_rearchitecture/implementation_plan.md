# RunAnywhere v2 — Implementation Plan

> Companion to MASTER_PLAN.md. This document is the execution guide: exactly what to build,
> in what order, which files, and how agents should divide the work.
> Start immediately. Phases are ordered by dependency, not by calendar.
> Last updated: 2026-04-18

---

## How to Use This Document

Every agent working on this rewrite should:

1. Read MASTER_PLAN.md in full first (architecture, rationale, reference implementations).
2. Read only the phase section assigned to them.
3. Use the go/no-go gate as the completion criterion — not "I finished writing code."
4. Reference RCLI and FastVoice source files at the exact line numbers given; do not guess.
5. Do not advance to the next phase until the current phase gate passes.

---

## Immediate Pre-Phase Actions

These actions fix active problems in the current SDK and must be done NOW, in parallel with
Phase 0. They do not require any v2 infrastructure. Assign one engineer per item.

### IMM-1: Fix CI — Remove All 46 `continue-on-error: true` Directives

**Files:** `.github/workflows/*.yml` (all 11 workflows)

For each directive:

1. If the step is a real build step: remove `continue-on-error: true` and let it fail natively.
2. If the step is diagnostic/reporting and is allowed to fail: document why in a comment
   and add `if: always()` so it still runs but does not gate the pipeline.
3. If the step is dead code: remove the step entirely.

**Outcome:** Green CI means the build actually passed. No more silent failures.

### IMM-2: Fix the macOS-Only `stat -f %m` Bug

**File:** `scripts/build-kotlin.sh:215-237`

Function `check_commons_changed()` currently uses:

```bash
stat -f %m sdk/runanywhere-commons/
```

`stat -f` is macOS-only. On Linux CI it errors silently and rebuilds every time.

**Fix:** Replace with:

```bash
git diff --quiet HEAD -- sdk/runanywhere-commons/ 2>/dev/null || COMMONS_CHANGED=true
```

Or use a cross-platform approach:

```bash
if [[ "$(uname)" == "Darwin" ]]; then
    MOD_TIME=$(stat -f %m "$dir")
else
    MOD_TIME=$(stat -c %Y "$dir")
fi
```

**Outcome:** Linux CI stops rebuilding commons on every run.

### IMM-3: Make MetalRT Silent Stub a Loud Failure

**File:** `sdk/runanywhere-commons/src/backends/metalrt/CMakeLists.txt`

Currently when `METALRT_ROOT` is not set and `RAC_BUILD_METALRT=ON`, the build succeeds with
empty stubs and no warning.

**Fix:** Add to the CMakeLists.txt:

```cmake
if(RAC_BUILD_METALRT AND NOT DEFINED METALRT_ROOT)
    message(FATAL_ERROR
        "RAC_BUILD_METALRT=ON but METALRT_ROOT is not set. "
        "Set METALRT_ROOT to the MetalRT SDK path or disable with RAC_BUILD_METALRT=OFF")
endif()
```

**Outcome:** No more "successful" builds that silently produce empty stubs.

### IMM-4: Fix Placeholder API Keys in Examples

**Files:**

- `examples/android/RunAnywhereAI/app/src/main/java/.../MainActivity.kt`
- `examples/ios/RunAnywhereAI/AppDelegate.swift` (or `ContentView.swift`)

Currently ship with `"YOUR_PRODUCTION_API_KEY"`, `"YOUR_API_KEY_HERE"`, `"demo-api-key"`.

**Android fix:**

```kotlin
// In local.properties (git-ignored):
// runanywhere.api.key=YOUR_KEY_HERE

// In build.gradle.kts:
val localProps = Properties().apply {
    load(rootProject.file("local.properties").inputStream())
}
buildConfigField("String", "RA_API_KEY", "\"${localProps["runanywhere.api.key"]}\"")

// In MainActivity.kt:
RunAnywhere.init(BuildConfig.RA_API_KEY)
```

**iOS fix:**

```bash
# Create Config.xcconfig (git-ignored):
RA_API_KEY = YOUR_KEY_HERE
```

```swift
// Read from Info.plist:
let apiKey = Bundle.main.infoDictionary?["RA_API_KEY"] as? String ?? ""
```

Add `local.properties` and `Config.xcconfig` to `.gitignore`. Add `.example` versions showing the
format.

**Outcome:** First run authenticates correctly when the dev has configured their key.

### IMM-5: Single NDK Version Source

**Current state:** `27.0.12077973` appears in 5 locations:

1. `sdk/runanywhere-kotlin/build.gradle.kts`
2. `sdk/runanywhere-android/build.gradle`
3. `.github/workflows/android-sdk.yml`
4. `.github/workflows/android-app.yml`
5. `scripts/build-kotlin.sh`

**Fix:**

```toml
# gradle/libs.versions.toml
[versions]
ndkVersion = "27.0.12077973"
```

In each `.gradle.kts`:

```kotlin
ndkVersion = libs.versions.ndkVersion.get()
```

In CI YAML:

```yaml
env:
  NDK_VERSION: ${{ vars.NDK_VERSION }}  # Set in GitHub repo variables
```

**Outcome:** NDK version bumped in one place only.

### IMM-6: Add `iosMain` Source Set to KMP

**File:** `sdk/runanywhere-kotlin/build.gradle.kts`

Currently there is no `iosMain` source set despite the declared `expect` declarations.

**Fix:**

```kotlin
kotlin {
    iosArm64()
    iosSimulatorArm64()
    iosX64()

    sourceSets {
        val iosMain by creating {
            dependsOn(commonMain.get())
        }
        val iosArm64Main by getting { dependsOn(iosMain) }
        val iosSimulatorArm64Main by getting { dependsOn(iosMain) }
        val iosX64Main by getting { dependsOn(iosMain) }
    }
}
```

Create `src/iosMain/kotlin/` with stub `actual` implementations for all `expect` declarations
that currently have no iOS actualization.

**Outcome:** KMP SDK can actually target iOS.

### IMM-7: Consolidate Duplicate JNI Copy Logic

**Current state:** 484 LOC duplicated across:

- `build-kotlin.sh:285-430`
- `build-flutter.sh:335-533`
- `build-react-native.sh:373-514`

**Fix:** Extract to `scripts/copy_jni_libs.sh`:

```bash
#!/usr/bin/env bash
# copy_jni_libs.sh — called by build-kotlin.sh, build-flutter.sh, build-react-native.sh
# Usage: copy_jni_libs.sh <COMMONS_BUILD_DIR> <DEST_JNI_DIR>
set -euo pipefail

COMMONS_BUILD="$1"
DEST_JNI="$2"

for ABI in arm64-v8a armeabi-v7a x86_64 x86; do
    src="$COMMONS_BUILD/android/$ABI"
    dst="$DEST_JNI/$ABI"
    if [ -d "$src" ]; then
        mkdir -p "$dst"
        cp -f "$src"/*.so "$dst/" || {
            echo "ERROR: Failed to copy JNI libs for $ABI" >&2
            exit 1  # Hard fail, not WARN
        }
    fi
done
```

Source it from all three build scripts:

```bash
source "$(dirname "$0")/copy_jni_libs.sh" "$COMMONS_BUILD_DIR" "$JNI_DEST"
```

**Outcome:** Single copy function. Missing `.so` is a hard failure, not a warning.

---

## Phase 0: C++ Core + VoiceAgent

**Goal:** A working streaming VoiceAgent running fully in C++ core, benchmarked on macOS. No
frontends. No L6. The VoiceAgent pipeline is concrete — not abstracted into a general DAG yet.

**Do NOT extract the L4 DAG abstraction from the concrete VoiceAgent pipeline until the Phase 0
gate passes.** Build the concrete pipeline first; abstract afterwards.

Assign 5 agents in parallel (A through E). Each agent's work is independent. All work targets
the NEW `core/` directory in the repo root — not the existing `sdk/` tree.

---

### Agent A: proto3 IDL Schemas + CMake Build Skeleton

**Deliverables:**

```text
idl/
  voice_events.proto
  pipeline.proto
  solutions.proto
CMakeLists.txt          (root)
cmake/
  platform.cmake        (platform detection and compiler flags)
  vcpkg.cmake           (vcpkg integration)
  plugins.cmake         (helpers for building static vs dlopen plugins)
  protobuf.cmake        (protoc codegen integration)
vcpkg.json              (dependency manifest)
```

**`voice_events.proto` must define:**

```protobuf
syntax = "proto3";
package runanywhere;

message VoiceEvent {
    oneof event {
        UserSaidEvent      user_said       = 1;
        AssistantToken     assistant_token = 2;
        AudioFrame         audio           = 3;
        InterruptedEvent   interrupted     = 4;
        ErrorEvent         error           = 5;
    }
}

message UserSaidEvent     { string text = 1; bool is_final = 2; }
message AssistantToken    { string token = 1; bool is_final = 2; }
message AudioFrame        { bytes pcm_f32_le = 1; int32 sample_rate = 2; int32 channels = 3; }
message InterruptedEvent  { string reason = 1; }
message ErrorEvent        { int32 code = 1; string message = 2; }

message VoiceAgentConfig {
    string llm_model_id  = 1;
    string stt_model_id  = 2;
    string tts_model_id  = 3;
    string vad_model_id  = 4;
    int32  sample_rate   = 5;  // default 16000
    int32  chunk_ms      = 6;  // default 20
}
```

**`pipeline.proto` must define:**

```protobuf
syntax = "proto3";
package runanywhere;

message PipelineSpec {
    repeated OperatorConfig operators = 1;
    repeated EdgeConfig     edges     = 2;
}

message OperatorConfig {
    string             name   = 1;
    string             type   = 2;
    map<string,string> params = 3;
}

message EdgeConfig {
    string from_op   = 1;
    string from_port = 2;
    string to_op     = 3;
    string to_port   = 4;
}
```

**Root CMakeLists.txt:**

```cmake
cmake_minimum_required(VERSION 3.22)
project(RunAnywhere CXX OBJCXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(cmake/platform.cmake)
include(cmake/vcpkg.cmake)
include(cmake/plugins.cmake)
include(cmake/protobuf.cmake)

add_subdirectory(core)
add_subdirectory(engines/llamacpp)
add_subdirectory(engines/sherpa)
add_subdirectory(engines/wakeword)
add_subdirectory(solutions/voice-agent)

if(RA_BUILD_FRONTENDS)
    add_subdirectory(frontends/swift)
    add_subdirectory(frontends/kotlin)
    add_subdirectory(frontends/dart)
    add_subdirectory(frontends/ts)
endif()

if(RA_BUILD_TOOLS)
    add_subdirectory(tools/benchmark)
    add_subdirectory(tools/pipeline-validator)
endif()
```

**`cmake/platform.cmake` must handle:**

```cmake
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(RA_PLATFORM "IOS")
    set(RA_USE_GCD ON)
    set(RA_STATIC_PLUGINS ON)
elseif(ANDROID)
    set(RA_PLATFORM "ANDROID")
    set(RA_USE_ASIO ON)
    set(RA_STATIC_PLUGINS OFF)
elseif(EMSCRIPTEN)
    set(RA_PLATFORM "WASM")
    set(RA_USE_ASYNCIFY ON)
    set(RA_STATIC_PLUGINS ON)
elseif(APPLE)
    set(RA_PLATFORM "MACOS")
    set(RA_USE_ASIO ON)
    set(RA_STATIC_PLUGINS OFF)
else()
    set(RA_PLATFORM "LINUX")
    set(RA_USE_ASIO ON)
    set(RA_STATIC_PLUGINS OFF)
endif()

add_compile_options(-Wall -Wextra -Wpedantic -Werror)
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    add_compile_options(-fsanitize=address,undefined,thread)
    add_link_options(-fsanitize=address,undefined,thread)
endif()
```

**`vcpkg.json`:**

```json
{
    "name": "runanywhere",
    "version": "2.0.0",
    "dependencies": ["protobuf", "boost-asio", "usearch", "gtest"]
}
```

**Gate for Agent A:**

- `cmake --preset macos-debug && cmake --build --preset macos-debug` succeeds cleanly
- `protoc --cpp_out=. voice_events.proto` generates `.pb.h` and `.pb.cc` without error
- CI builds the CMake skeleton on macOS and Linux

---

### Agent B: L4 Typed Channels + Concrete VoiceAgent Pipeline

**Reference files:**

- `RCLI/src/core/memory_pool.h` (port as-is)
- `RCLI/src/core/ring_buffer.h` (port as-is)
- `FastVoice/VoiceAI/src/pipeline/sentence_detector.h:9-52` (port as-is)
- `FastVoice/VoiceAI/src/pipeline/orchestrator.cpp:183-287` (algorithm reference only)
- `RCLI/src/pipeline/orchestrator.h:215-218` (barge-in atomics — port exactly)

**Deliverables:**

```text
core/
  graph/
    memory_pool.h        ← ported from RCLI as-is, C++20 adjusted
    ring_buffer.h        ← ported from RCLI as-is, C++20 adjusted
    stream_edge.h        ← NEW: typed async edge
    cancel_token.h       ← NEW: hierarchical cancel propagation
    pipeline_node.h      ← NEW: abstract base for all L3 operators
  voice_pipeline/
    voice_pipeline.h     ← concrete VoiceAgent pipeline declaration
    voice_pipeline.cpp   ← CONCRETE mic→VAD→STT→SentenceDetector→LLM→TTS→AudioSink
    sentence_detector.h  ← ported from FastVoice
```

**`stream_edge.h` spec:**

```cpp
#pragma once
#include "ring_buffer.h"
#include "cancel_token.h"

template <typename T>
class StreamEdge {
public:
    explicit StreamEdge(size_t capacity, std::shared_ptr<CancelToken> token);

    // Producer side — blocks if full
    void push(T value);
    bool try_push(T value, std::chrono::milliseconds timeout);

    // Consumer side — blocks until available or cancelled
    std::optional<T> pop();
    std::optional<T> try_pop(std::chrono::milliseconds timeout);

    void close();
    bool is_closed() const;
    bool is_cancelled() const;

private:
    RingBuffer<T>                buf_;
    std::shared_ptr<CancelToken> cancel_token_;
    std::mutex                   mu_;
    std::condition_variable      cv_push_, cv_pop_;
};
```

**`cancel_token.h` spec:**

```cpp
#pragma once
#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <vector>

class CancelToken {
public:
    static std::shared_ptr<CancelToken> create();

    void cancel();
    bool is_cancelled() const;

    // Cancelling parent propagates to all children
    std::shared_ptr<CancelToken> child();
    void on_cancel(std::function<void()> cb);

private:
    std::atomic<bool>                         cancelled_{false};
    std::vector<std::shared_ptr<CancelToken>> children_;
    std::vector<std::function<void()>>        callbacks_;
    std::mutex                                mu_;
};
```

**`voice_pipeline.cpp` — concrete VoiceAgent:**

```cpp
class VoiceAgentPipeline {
public:
    struct Config {
        std::string llm_model_id;
        std::string stt_model_id;
        std::string tts_model_id;
        std::string vad_model_id;
        int         sample_rate = 16000;
        int         chunk_ms    = 20;
    };

    explicit VoiceAgentPipeline(Config cfg, PluginRegistry& registry);

    void run(StreamEdge<VoiceEvent>& out, std::shared_ptr<CancelToken> token);

private:
    void mic_capture_loop(StreamEdge<AudioFrame>& out);
    void vad_loop(StreamEdge<AudioFrame>& in, StreamEdge<VADEvent>& out);
    void stt_loop(StreamEdge<AudioFrame>& audio_in,
                  StreamEdge<VADEvent>&   control_in,
                  StreamEdge<TranscriptChunk>& out);
    void llm_loop(StreamEdge<TranscriptChunk>& in,
                  StreamEdge<std::string>&      token_out,
                  CancelToken&                  llm_cancel);
    void sentence_detector_loop(StreamEdge<std::string>& token_in,
                                StreamEdge<std::string>& sentence_out);
    void tts_loop(StreamEdge<std::string>& sentence_in,
                  StreamEdge<AudioFrame>&  audio_out,
                  CancelToken&             tts_cancel);
    void audio_sink_loop(StreamEdge<AudioFrame>& in);

    // Barge-in — transactional cancel boundary (see MASTER_PLAN.md)
    void on_barge_in();

    std::atomic<bool>       barge_in_flag_{false};
    StreamEdge<std::string> sentence_queue_{32, nullptr};
    RingBuffer<float>       playback_rb_{48000 * 2};  // 2s at 48kHz

    LlmEngine* llm_engine_ = nullptr;
    SttEngine* stt_engine_ = nullptr;
    TtsEngine* tts_engine_ = nullptr;
    VadEngine* vad_engine_ = nullptr;
    Config     cfg_;
};
```

**The barge-in implementation must match MASTER_PLAN.md exactly:**

```cpp
void VoiceAgentPipeline::on_barge_in() {
    barge_in_flag_.store(true, std::memory_order_release);
    llm_engine_->cancel();
    playback_rb_.drain();
    sentence_queue_.clear_locked();
}

// In tts_loop:
while (true) {
    auto sentence = sentence_queue_.pop();
    if (!sentence.has_value()) break;
    if (barge_in_flag_.load(std::memory_order_acquire)) break;
    tts_engine_->synthesize_to_ring_buffer(*sentence, playback_rb_);
}
```

**Gate for Agent B:**

- `VoiceAgentPipeline::run()` produces `VoiceEvent::audio` frames within 100ms of end of
  utterance on a test audio file on M-series MacBook
- `on_barge_in()` stops TTS within 50ms
- `StreamEdge<T>` correctly blocks producer when full and unblocks when consumer pops
- `CancelToken::cancel()` propagates to all children within one event loop tick

---

### Agent C: llama.cpp L2 Engine Plugin

**Reference files:**

- `RCLI/src/engines/llm_engine.h` and `.cpp` (port as concrete L2 plugin)
- `RCLI/src/engines/model_profile.h` (port chat template + tool-call parsing)
- `FastVoice/VoiceAI/src/core/types.h:79-83` (TokenCallback type definition)

**Deliverables:**

```text
engines/llamacpp/
  llamacpp_engine.h
  llamacpp_engine.cpp    ← llama.cpp integration: generate_text + embed
  llamacpp_plugin.h      ← LlamaCppVTable definition
  llamacpp_plugin.cpp    ← ra_plugin_fill_vtable(LlamaCppVTable*)
  CMakeLists.txt
```

**`LlamaCppVTable` — the plugin ABI contract:**

```cpp
struct LlamaCppVTable {
    int         (*ra_plugin_abi_version)();
    const char* (*ra_plugin_name)();
    const char* (*ra_plugin_version)();

    void (*ra_capabilities)(ra_primitive_t* out, int* count);
    void (*ra_supported_formats)(ra_model_format_t* out, int* count);
    void (*ra_supported_runtimes)(ra_runtime_id_t* out, int* count);

    ra_session_t* (*ra_create_session)(const ra_model_spec_t*, const ra_session_config_t*);
    void          (*ra_destroy_session)(ra_session_t*);

    ra_status_t (*ra_generate)(ra_session_t*, const ra_prompt_t*,
                                ra_token_callback_t, void* user_data);
    void        (*ra_cancel)(ra_session_t*);

    ra_status_t (*ra_embed)(ra_session_t*, const char* text, float* out_vec, int dims);
};

extern "C" void ra_plugin_fill_vtable(LlamaCppVTable* vt);
```

**Key implementation constraints:**

- MUST implement `TokenCallback` pattern from FastVoice: `std::function<void(const TokenOutput&)>`
  fired synchronously on the llama decode thread.
- MUST NOT call back into the LLM session from within the callback (re-entrant crash).
- MUST support graceful cancellation: `ra_cancel()` sets an atomic flag checked in the llama
  eval loop. Session cleanup must NOT call `llama_free_model()` concurrently.
- Context window: retain KV cache between calls within the same session (multi-turn support).
  `ra_cancel()` does NOT clear the KV cache.
- Model loading: use `llama_load_model_from_file()` with `n_gpu_layers` set based on
  `HardwareProfile` (delivered by Agent E).
- Thread count: `std::thread::hardware_concurrency() / 2` on macOS/Linux; 4 on Android; 1 on
  WASM.

**CMakeLists.txt:**

```cmake
add_library(llamacpp_engine SHARED llamacpp_engine.cpp llamacpp_plugin.cpp)
target_include_directories(llamacpp_engine PRIVATE
    ${CMAKE_SOURCE_DIR}/core/abi ${LLAMA_CPP_INCLUDE_DIR})
target_link_libraries(llamacpp_engine PRIVATE llama)
target_compile_definitions(llamacpp_engine PRIVATE RA_PLUGIN_ABI_VERSION=1)

# iOS: static only
if(RA_PLATFORM STREQUAL "IOS")
    set_target_properties(llamacpp_engine PROPERTIES TYPE STATIC_LIBRARY)
endif()
```

**Gate for Agent C:**

- `llama_load_model_from_file()` loads a 4-bit GGUF model
- `ra_generate()` fires `TokenCallback` for every token; streaming visible in test
- `ra_cancel()` stops generation within 2 llama eval steps
- `ra_embed()` returns a non-zero vector of the declared dimension
- Plugin passes ABI version handshake via `PluginLoader<LlamaCppVTable>`

---

### Agent D: sherpa-onnx L2 Engine Plugin (STT + TTS + VAD + Wake Word)

**Reference files:**

- `RCLI/src/engines/stt_engine.h/.cpp`
- `RCLI/src/engines/tts_engine.h/.cpp`
- `RCLI/src/engines/vad_engine.h/.cpp`
- FastVoice same files in `VoiceAI/src/engines/`

**Deliverables:**

```text
engines/sherpa/
  sherpa_engine.h
  sherpa_engine.cpp
  sherpa_plugin.h        ← SherpaVTable
  sherpa_plugin.cpp
  CMakeLists.txt
engines/wakeword/
  wakeword_engine.h
  wakeword_engine.cpp    ← Real sherpa-onnx wake word (replaces 100% stub)
  wakeword_plugin.cpp
  CMakeLists.txt
```

**`SherpaVTable`:**

```cpp
struct SherpaVTable {
    int         (*ra_plugin_abi_version)();
    const char* (*ra_plugin_name)();

    // STT — transcribe (streaming, 20ms chunks)
    ra_stt_session_t* (*ra_stt_create)(const ra_model_spec_t*);
    void              (*ra_stt_destroy)(ra_stt_session_t*);
    ra_status_t       (*ra_stt_feed_audio)(ra_stt_session_t*,
                                            const float* pcm_f32, int n, int sr);
    ra_status_t       (*ra_stt_get_result)(ra_stt_session_t*, ra_transcript_chunk_t* out);
    void              (*ra_stt_flush)(ra_stt_session_t*);

    // TTS — synthesize (sentence-chunked)
    ra_tts_session_t* (*ra_tts_create)(const ra_model_spec_t*);
    void              (*ra_tts_destroy)(ra_tts_session_t*);
    ra_status_t       (*ra_tts_synthesize)(ra_tts_session_t*,
                                            const char* text, float* pcm_out,
                                            int* n_out, int max_n);

    // VAD — detect_voice (three event types)
    ra_vad_session_t* (*ra_vad_create)(const ra_model_spec_t*);
    void              (*ra_vad_destroy)(ra_vad_session_t*);
    ra_status_t       (*ra_vad_feed)(ra_vad_session_t*, const float* pcm_f32, int n,
                                      ra_vad_event_t* events_out, int* n_events_out);

    // Wake word
    ra_ww_session_t* (*ra_ww_create)(const char* model_path, const char* keyword);
    void             (*ra_ww_destroy)(ra_ww_session_t*);
    ra_status_t      (*ra_ww_feed)(ra_ww_session_t*, const float* pcm_f32, int n,
                                    bool* detected_out);
};
```

**Key implementation constraints:**

- STT MUST support streaming: `ra_stt_feed_audio()` called repeatedly with 20ms chunks.
  Partial results tagged `is_partial = true`.
- TTS MUST support sentence-chunked synthesis. The 60-73ms first audio target assumes ~40ms
  TTS latency per sentence.
- VAD MUST emit `RA_VAD_VOICE_START`, `RA_VAD_VOICE_END_OF_UTTERANCE`, `RA_VAD_BARGE_IN`.
- Wake word MUST call actual sherpa-onnx keyword spotting via `SherpaOnnxCreateKeywordSpotter()`
  C API. The current stub at `wakeword_service.cpp:210,233,477-498` is deleted entirely.

**Gate for Agent D:**

- STT transcribes a 5-second test WAV file to correct text
- TTS synthesizes "Hello world" to a non-silent PCM buffer within 100ms
- VAD detects voice and end-of-utterance on a 2-second speech+silence test file
- Wake word returns `true` for the keyword and `false` for random speech

---

### Agent E: PluginRegistry + HardwareProfile + C ABI

**Reference files:**

- `RCLI/src/engines/metalrt_loader.h/.cpp` (template for PluginLoader)
- `RCLI/src/core/hardware_profile.h` (port HardwareProfile / detect_hardware)

**Deliverables:**

```text
core/
  registry/
    plugin_registry.h/.cpp
    plugin_loader.h            ← PluginLoader<VTABLE> template
  router/
    engine_router.h/.cpp
    hardware_profile.h/.cpp    ← ported from RCLI
  abi/
    ra_primitives.h            ← extern "C" ABI
    ra_pipeline.h
    ra_version.h
```

**`plugin_registry.h`:**

```cpp
class PluginRegistry {
public:
    static PluginRegistry& global();

    // Static registration (iOS / WASM)
    template <typename Engine>
    void register_static();

    // Dynamic loading (Android / macOS / Linux)
    bool load_plugin(std::string_view dylib_path);

    // Lookup
    Engine* find_engine(PrimitiveId primitive, ModelFormat format, HardwareCaps hw);
    void enumerate(std::function<void(const EngineInfo&)> cb) const;

private:
    std::vector<std::unique_ptr<EngineEntry>> engines_;
    std::mutex                                mu_;
};
```

**`plugin_loader.h`:**

```cpp
template <typename VTABLE>
class PluginLoader {
public:
    using CapabilityCheckFn = std::function<bool()>;

    bool load(std::string_view dylib_path,
              const std::vector<std::string>& required_symbols,
              int required_abi_version,
              CapabilityCheckFn capability_gate = nullptr);

    VTABLE& vtable();
    bool is_loaded() const { return handle_ != nullptr; }
    void unload();
    ~PluginLoader() { unload(); }

private:
    void*   handle_ = nullptr;
    VTABLE  vtable_ = {};

    bool resolve_symbols(const std::vector<std::string>& names);
};
```

**`hardware_profile.h`:**

```cpp
struct HardwareCaps {
    std::string cpu_brand;
    int         cpu_cores;
    bool        has_metal;
    bool        has_ane;       // Apple Neural Engine
    bool        has_cuda;
    bool        has_vulkan;
    size_t      total_ram;
    size_t      available_ram;
    int         gpu_memory_mb;
};

HardwareCaps detect_hardware();  // port from RCLI/src/core/hardware_profile.h
```

**`ra_primitives.h` (extern "C" ABI):**

```c
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#define RA_ABI_VERSION 1

typedef int ra_status_t;
#define RA_OK           0
#define RA_ERR_CANCEL  -1
#define RA_ERR_MODEL   -2
#define RA_ERR_RUNTIME -3

typedef struct ra_session_t     ra_session_t;
typedef struct ra_stt_session_t ra_stt_session_t;
typedef struct ra_tts_session_t ra_tts_session_t;
typedef struct ra_vad_session_t ra_vad_session_t;
typedef struct ra_ww_session_t  ra_ww_session_t;

typedef enum {
    RA_PRIMITIVE_GENERATE_TEXT = 0,
    RA_PRIMITIVE_TRANSCRIBE    = 1,
    RA_PRIMITIVE_SYNTHESIZE    = 2,
    RA_PRIMITIVE_DETECT_VOICE  = 3,
    RA_PRIMITIVE_EMBED         = 4,
    RA_PRIMITIVE_RERANK        = 5,
} ra_primitive_t;

typedef enum {
    RA_FORMAT_GGUF           = 0,
    RA_FORMAT_ONNX           = 1,
    RA_FORMAT_COREML         = 2,
    RA_FORMAT_MLX_SAFETENSOR = 3,
} ra_model_format_t;

typedef struct {
    const char*       model_id;
    const char*       model_path;
    ra_model_format_t format;
} ra_model_spec_t;

typedef struct {
    const char* text;
    bool        is_partial;
    float       confidence;
} ra_transcript_chunk_t;

typedef enum {
    RA_VAD_VOICE_START            = 0,
    RA_VAD_VOICE_END_OF_UTTERANCE = 1,
    RA_VAD_BARGE_IN               = 2,
} ra_vad_event_type_t;

typedef struct {
    ra_vad_event_type_t type;
    int32_t             frame_offset;
} ra_vad_event_t;

typedef struct {
    const char* text;
    bool        is_final;
} ra_token_output_t;

typedef void (*ra_token_callback_t)(const ra_token_output_t* token, void* user_data);

typedef struct {
    int n_gpu_layers;
    int n_threads;
    int context_size;
} ra_session_config_t;

typedef struct {
    const char* text;
    int         conversation_id;  // -1 for stateless
} ra_prompt_t;

#ifdef __cplusplus
}
#endif
```

**Gate for Agent E:**

- `PluginLoader<LlamaCppVTable>::load()` loads the Agent C plugin correctly
- `PluginRegistry::load_plugin()` discovers all engines
- `EngineRouter::route(RA_PRIMITIVE_GENERATE_TEXT, RA_FORMAT_GGUF, hw, budget)` returns
  the llama.cpp engine
- `detect_hardware().has_metal` is `true` on M-series Mac, `false` on Intel Mac
- ABI version mismatch is caught and logged before any vtable call

---

### Phase 0 Go/No-Go Gate

**ALL of the following must pass before Phase 1 begins:**

1. `VoiceAgentPipeline::run()` on M-series MacBook with a test audio file produces:
   - `VoiceEvent::user_said` within 500ms of end of utterance
   - `VoiceEvent::assistant_token` streaming within 200ms of STT final result
   - `VoiceEvent::audio` within **100ms of first LLM token** (target: 60-73ms matching
     FastVoice benchmark)

2. Barge-in: `on_barge_in()` while TTS is synthesizing stops audio within 50ms. New
   utterance resumes cleanly with `barge_in_flag_` cleared.

3. All three engines (llama.cpp, sherpa STT, sherpa TTS) run through `PluginRegistry` and
   `EngineRouter` — NOT hard-coded directly in the pipeline.

4. All CI runs pass with ASan + TSan + UBSan on Phase 0 code. Zero suppressions.

5. `cmake --build --preset macos-debug --target voice_agent_test` builds and runs without
   crashes.

**If the gate fails:** root-cause and fix before Phase 1. Do not start Phase 1 until passing.

---

## Phase 1: Swift L6 + iOS XCFramework

**Goal:** A Swift developer clones the repo and runs streaming VoiceAgent on iPhone in under 30
minutes, writing ~20 lines of Swift. No `pod install`, no GitHub release downloads.

**Prerequisite:** Phase 0 gate passed.

### Sub-task 1A: proto3 Codegen for Swift

**Files:**

```text
idl/codegen/
  generate_swift.sh
  templates/
    swift_event_stream.swift.j2
```

**`generate_swift.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail

PROTO_DIR="$(dirname "$0")/../"
OUT_DIR="$(dirname "$0")/../../frontends/swift/Sources/RunAnywhere/Generated"
mkdir -p "$OUT_DIR"

protoc \
    --proto_path="$PROTO_DIR" \
    --swift_out=Visibility=Public:"$OUT_DIR" \
    "$PROTO_DIR"voice_events.proto \
    "$PROTO_DIR"pipeline.proto \
    "$PROTO_DIR"solutions.proto

echo "Swift proto3 codegen complete → $OUT_DIR"
```

Verify `swift-protobuf` generates idiomatic Swift types with `Sendable` conformance (Swift 6).

**Gate:** `swift build` in `frontends/swift/` succeeds after running `generate_swift.sh`.

### Sub-task 1B: Swift Platform Adapter

**Files:**

```text
frontends/swift/
  Sources/RunAnywhere/
    Generated/                ← output of generate_swift.sh (NEVER hand-edited)
    Adapter/
      RunAnywhere.swift       ← public entry point
      VoiceSession.swift      ← AsyncThrowingStream<VoiceEvent, Error> wrapper
      AudioSession.swift      ← AVAudioSession lifecycle + interruption handling
      MicrophoneCapture.swift ← AVAudioEngine mic at 16kHz mono float32
      PermissionManager.swift ← microphone permission request + status
  Package.swift
```

**`RunAnywhere.swift` public API:**

```swift
@MainActor
public final class RunAnywhere {
    public static func solution(_ config: SolutionConfig) async throws -> VoiceSession {
        let session = try await VoiceSession(config: config)
        return session
    }
}

public enum SolutionConfig {
    case voiceAgent(VoiceAgentConfig)
    case rag(RAGConfig)
}

public struct VoiceAgentConfig {
    public var llm: String = "qwen3-4b"
    public var stt: String = "whisper-base"
    public var tts: String = "kokoro"
    public var vad: String = "silero-v5"
}
```

**`VoiceSession.swift`:**

```swift
public final class VoiceSession: Sendable {
    private let pipeline: OpaquePointer

    public func run() -> AsyncThrowingStream<VoiceEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let ctx = Unmanaged.passRetained(continuation)
                ra_pipeline_run(pipeline, { event, userData in
                    let cont = Unmanaged<AsyncThrowingStream<VoiceEvent, Error>.Continuation>
                        .fromOpaque(userData!).takeUnretainedValue()
                    cont.yield(/* decode proto3 VoiceEvent */)
                }, ctx.toOpaque())
                ctx.release()
                continuation.finish()
            }
        }
    }

    public func stop() { ra_pipeline_cancel(pipeline) }
}
```

**`AudioSession.swift` must handle:**

- `AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat)`
- Route change notifications (headphones plugged/unplugged)
- Interruption notifications (phone call, Siri)
- Background audio entitlement

**`MicrophoneCapture.swift` must:**

- Use `AVAudioEngine` with `inputNode` tap at 16kHz, mono, `float32`
- Resample if hardware sample rate differs from 16kHz
- Feed 20ms chunks to `ra_stt_feed_audio()`

**`Package.swift`:**

```swift
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "RunAnywhere",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "RunAnywhere", targets: ["RunAnywhere"])],
    targets: [
        .target(name: "RunAnywhere",
                dependencies: ["RunAnywhereCore"],
                path: "Sources/RunAnywhere"),
        .binaryTarget(name: "RunAnywhereCore",
                      path: "build/ios-static/RunAnywhereCore.xcframework"),
    ]
)
```

### Sub-task 1C: CMake XCFramework Build

**`CMakePresets.json` must include:**

```json
{
    "configurePresets": [{
        "name": "ios-release",
        "generator": "Xcode",
        "cacheVariables": {
            "CMAKE_SYSTEM_NAME": "iOS",
            "CMAKE_OSX_DEPLOYMENT_TARGET": "16.0",
            "CMAKE_OSX_ARCHITECTURES": "arm64",
            "RA_PLATFORM": "IOS",
            "RA_STATIC_PLUGINS": "ON",
            "RA_BUILD_FRONTENDS": "OFF",
            "CMAKE_BUILD_TYPE": "Release"
        }
    }]
}
```

After build:

```bash
xcodebuild -create-xcframework \
    -library build/ios-arm64/libRunAnywhereCore.a \
    -headers core/abi/ \
    -library build/ios-simulator/libRunAnywhereCore.a \
    -headers core/abi/ \
    -output build/ios-static/RunAnywhereCore.xcframework
```

### Phase 1 Go/No-Go Gate

1. Engineer NOT on team: `git clone` → `swift package resolve` → open Xcode → run on iPhone
   15 or later → first voice response in under 30 minutes.
2. First audio ≤80ms on iPhone 15.
3. Zero `pod install`, zero `fix_pods_sandbox.sh`, zero GitHub release download.
4. `swift build` completes without warnings on Swift 6.
5. Barge-in stops audio on iPhone within 50ms.

---

## Phase 2: Kotlin L6 + RAG Solution

**Goal:** Android developer has parity with Swift. RAG pipeline ships.
**Prerequisite:** Phase 1 gate passed.

### Sub-task 2A: Kotlin Platform Adapter

**Files:**

```text
frontends/kotlin/
  src/main/kotlin/com/runanywhere/
    generated/           ← Wire-generated (NEVER hand-edited)
    adapter/
      RunAnywhere.kt
      VoiceSession.kt    ← Flow<VoiceEvent> wrapper
      AudioFocus.kt      ← AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
      MicrophoneCapture.kt ← AudioRecord 16kHz mono PCM_FLOAT
      PermissionHelper.kt
  src/main/cpp/
    jni_bridge.cpp       ← JNI → C ABI bridge
  CMakeLists.txt
```

**`VoiceSession.kt`:**

```kotlin
class VoiceSession internal constructor(private val nativeHandle: Long) {
    fun run(): Flow<VoiceEvent> = callbackFlow {
        val callback = object : VoiceEventCallback {
            override fun onEvent(event: VoiceEvent) { trySend(event) }
            override fun onError(code: Int, message: String) { close(VoiceException(code, message)) }
            override fun onComplete() { close() }
        }
        nativeRun(nativeHandle, callback)
        awaitClose { nativeCancel(nativeHandle) }
    }

    private external fun nativeRun(handle: Long, callback: VoiceEventCallback)
    private external fun nativeCancel(handle: Long)
}
```

**`AudioFocus.kt`:**

- Request `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` before mic capture
- Abandon focus when pipeline stops
- Handle `AUDIOFOCUS_LOSS` by calling `VoiceSession.stop()`

**`jni_bridge.cpp`:** Maps C ABI callbacks → Kotlin `VoiceEventCallback` methods via JNI.

### Sub-task 2B: RAG Solution

**Reference files:**

- `FastVoice/RAG/temp/src/rag/bm25_index.h:9-74`
- `FastVoice/RAG/temp/src/rag/vector_index.h:8-37`
- `FastVoice/RAG/temp/src/rag/hybrid_retriever.h:11-76`
- `FastVoice/RAG/temp/src/rag/embedding_cache.h:14-162`
- `FastVoice/RAG/temp/src/pipeline/rag_orchestrator.cpp:159-193` (parallel fan-out)

**Files:**

```text
solutions/rag/
  src/
    bm25_index.h/.cpp        ← ported from FastVoice (zero-alloc, pre-allocated score buf)
    vector_index.h/.cpp      ← ported from FastVoice (USearch v2.16.5 HNSW mmap)
    hybrid_retriever.h/.cpp  ← ported from FastVoice (BM25 + HNSW + RRF, zero-alloc)
    embedding_cache.h/.cpp   ← ported from FastVoice (freq-weighted LRU)
    reranker.h/.cpp          ← NEW: bge-reranker-v2-m3 via llama.cpp embed
    document_processor.h/.cpp ← semantic chunker (plain text + HTML only; NO pdftotext)
    index_builder.h/.cpp     ← flat binary HNSW + BM25 + chunk store
    rag_pipeline.cpp         ← RAG DAG wired via L4 StreamEdge
  rag_plugin.h
  CMakeLists.txt
```

**Porting constraints:**

- `BM25Index`: port as-is. Do NOT remove the pre-allocated score buffer.
- `VectorIndex`: port as-is. Keep `mmap`-based USearch load.
- `HybridRetriever`: port as-is. Keep parallel BM25+embedding thread pattern.
- `EmbeddingCache`: port as-is. Frequency-weighted LRU with `sqrt(freq) / (1 + age)`.
- `DocumentProcessor`: remove `pdftotext` entirely. Use sentence-boundary chunking for plain
  text. Use `libxml2` for HTML tag stripping. PDF is optional behind `RA_ENABLE_PDF=ON`.

**Neural reranker (`reranker.h`) — greenfield:**

```cpp
class NeuralReranker {
public:
    explicit NeuralReranker(const std::string& model_path, LlmEngine* llm);
    std::vector<RankedDocument> rerank(const std::string& query,
                                        const std::vector<Document>& candidates,
                                        int top_k);
private:
    LlmEngine*  llm_;
    std::string model_path_;
};
```

### Phase 2 Go/No-Go Gate

1. Android VoiceAgent: first audio ≤100ms on Pixel 9.
2. RAG retrieval: `HybridRetriever::retrieve()` returns top-6 results in ≤5ms on Pixel 9 over
   10K chunks.
3. Kotlin developer writes the same ~20 lines as Swift to get streaming VoiceAgent.
4. Neural reranker produces a different ordering than RRF-only on a test query (proves the
   cross-encoder is running, not just returning RRF order).

---

## Phase 3: Remaining Frontends + Production CI

**Goal:** All 5 frontends parity. L4 DAG abstraction. L3 router complete. L1 runtimes. Full CI.
**Prerequisite:** Phase 2 gate passed.

### Sub-task 3A: Dart/Flutter L6 Adapter

Replace 22,838 LOC Flutter bridge:

```text
frontends/dart/
  lib/
    generated/               ← protobuf.dart output (NEVER hand-edited)
    adapter/
      runanywhere.dart
      voice_session.dart     ← Stream<VoiceEvent> via Dart FFI
      audio_capture.dart
  pubspec.yaml
```

Flutter already calls C directly (FFI) — preserve this. No method channels for capability
calls. `protobuf.dart` codegen via `generate_dart.sh`.

### Sub-task 3B: React Native / TS L6 Adapter

Replace 21,250 LOC Nitro bridge. Delete `HybridRunAnywhereCore` C++ dispatcher (10,908 LOC):

```text
frontends/ts/
  src/
    generated/               ← ts-proto output (NEVER hand-edited)
    adapter/
      RunAnywhere.ts
      VoiceSession.ts        ← AsyncIterable<VoiceEvent> via JSI TurboModule
      NativeRunAnywhere.ts   ← JSI TurboModule spec
  cpp/
    jsi_bridge.cpp           ← JSI → C ABI bridge (~300 LOC)
  package.json
```

### Sub-task 3C: Web / WASM L6 Adapter

```text
frontends/web/
  src/
    generated/               ← ts-proto output
    adapter/
      RunAnywhere.ts
      VoiceSession.ts        ← AsyncIterable<VoiceEvent> via asyncify callbacks
      WasmBridge.ts
  wasm/
    CMakeLists.txt           ← Emscripten build (--preset wasm-release)
```

All engines compiled in at WASM build time. Emscripten asyncify transforms synchronous C ABI
into JavaScript-awaitable callbacks.

### Sub-task 3D: L4 DAG Abstraction (Extracted from VoiceAgent)

**Only after Phase 0 gate passes.**

Extract the generic typed graph scheduler from the concrete `VoiceAgentPipeline`:

```text
core/
  graph/
    pipeline_graph.h/.cpp    ← Generic DAG: nodes + typed edges
    graph_builder.h          ← Fluent API for constructing DAGs from YAML spec
    scheduler.h              ← Assigns threads/strands to nodes, manages lifecycle
```

The concrete `voice_pipeline.cpp` MUST continue to work after this extraction — it becomes an
instance of `PipelineGraph` configured by the VoiceAgent YAML.

### Sub-task 3E: L3 Router (Complete)

Agent E (Phase 0) built the skeleton. Phase 3 completes:

```text
core/
  router/
    engine_router.cpp        ← full routing logic
    format_matcher.h         ← detects model format from file magic bytes + extension
    memory_estimator.h       ← estimates engine memory footprint before loading
    routing_table.h          ← priority: capability > format > hw > memory
```

Routing priority (highest first):

1. Exact capability match (`generate_text` → llama.cpp)
2. Model format match (GGUF → llama.cpp, ONNX → sherpa)
3. Hardware match (Apple Silicon → prefer MLX or MetalRT)
4. Memory budget fit (refuse gracefully if model exceeds available RAM)

### Sub-task 3F: L1 Runtime Wrappers

- **ORT** (~200 LOC, `runtimes/ort/ort_runtime.cpp`): wrap `OrtApi`. sherpa-onnx already uses
  ORT — do NOT reimplement ONNX graph loading.
- **ExecuTorch** (~200 LOC, `runtimes/executorch/et_runtime.cpp`): wrap
  `torch::executor::Module`. PyTorch-native `.pte` files with CoreML/MPS delegation.
- **MLX** (~500 LOC, `runtimes/mlx/mlx_runtime.cpp`): custom C++ wrapper. Required for Apple
  Silicon open-model performance.
- **CoreML** (~200 LOC Obj-C++, `runtimes/coreml/coreml_runtime.mm`): wrap `MLModel` C API.

### Sub-task 3G: Production CI

**`.github/workflows/core.yml`:**

```yaml
name: C++ Core CI
on:
  push:
    paths: ['core/**', 'engines/**', 'solutions/**']
jobs:
  sanitizers:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Configure
        run: cmake --preset macos-debug -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined,thread"
      - name: Build
        run: cmake --build --preset macos-debug
      - name: Test
        run: ctest --preset macos-debug --output-on-failure
```

**Benchmark regression gate:**

```yaml
- name: Latency Benchmark
  run: |
    ./tools/benchmark/run_benchmark.sh --preset macos-release voice_agent
    # Fails if first_audio_ms > baseline_ms * 1.10
```

### Phase 3 Go/No-Go Gate

1. All 5 frontends (Swift, Kotlin, Dart, TS, WASM) produce streaming VoiceAgent with first
   audio ≤120ms on their platforms.
2. All CI workflows pass with zero `continue-on-error` directives anywhere.
3. ASan + TSan + UBSan on core: zero errors.
4. Benchmark regression gate: first audio does not regress >10% from Phase 1 baseline.
5. Developer can `git clone` → follow one README → have VoiceAgent running in under 30 minutes
   on any of the 5 frontends.
6. L3 router correctly selects the right engine for any (primitive, format, hw) combination.

---

## Agent Workstream Summary

| Agent | Phase | Deliverable | Depends on |
| ----- | ----- | ----------- | ---------- |
| IMM-1 | Now | Fix 46 CI `continue-on-error` | Nothing |
| IMM-2 | Now | Fix `stat -f %m` | Nothing |
| IMM-3 | Now | MetalRT loud failure | Nothing |
| IMM-4 | Now | Fix placeholder API keys | Nothing |
| IMM-5 | Now | Single NDK version source | Nothing |
| IMM-6 | Now | KMP `iosMain` source set | Nothing |
| IMM-7 | Now | Consolidate JNI copy logic | Nothing |
| A | 0 | proto3 IDL + CMake skeleton | Nothing |
| B | 0 | L4 channels + VoiceAgent pipeline | A (CMake/ABI headers) |
| C | 0 | llama.cpp L2 plugin | A (ABI headers) |
| D | 0 | sherpa-onnx L2 plugin + wake word | A (ABI headers) |
| E | 0 | PluginRegistry + HardwareProfile + C ABI | A (ABI headers) |
| 1A | 1 | Swift proto3 codegen | A |
| 1B | 1 | Swift platform adapter | 1A, Phase 0 gate |
| 1C | 1 | CMake XCFramework build | B, C, D, E |
| 2A | 2 | Kotlin adapter | Phase 1 gate |
| 2B | 2 | RAG solution | Phase 1 gate, C (llama.cpp embed) |
| 3A | 3 | Dart/Flutter adapter | Phase 2 gate |
| 3B | 3 | RN/TS adapter | Phase 2 gate |
| 3C | 3 | Web/WASM adapter | Phase 2 gate |
| 3D | 3 | L4 DAG abstraction | Phase 0 gate ONLY |
| 3E | 3 | L3 router complete | E skeleton, Phase 2 gate |
| 3F | 3 | L1 runtime wrappers | Phase 0 gate |
| 3G | 3 | Production CI | All Phase 3 sub-tasks |

**IMM agents: run immediately, in parallel.
Phase 0 agents (A-E): run immediately, in parallel (agents B-E depend only on A's headers).
Phase 1: starts after Phase 0 gate passes.
Phase 2: starts after Phase 1 gate passes.
Phase 3: starts after Phase 2 gate passes.
3D must NOT start before Phase 0 gate — the DAG abstraction depends on a proven concrete VoiceAgent.**
