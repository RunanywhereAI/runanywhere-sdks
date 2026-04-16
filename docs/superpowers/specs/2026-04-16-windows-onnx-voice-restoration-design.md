# Windows ONNX Voice Restoration Design

## Summary

Restore the Windows voice stack for the Flutter example so it matches the mobile architecture instead of remaining vertically sliced off. The target is an English-only first release that restores:

- Speech-to-Text
- Text-to-Speech
- Voice Activity Detection
- Voice Assistant

The implementation must continue to use the existing RunAnywhere architecture:

- `runanywhere-commons` provides the native services and backends
- `runanywhere_onnx` registers the ONNX backend with the core registry
- the Flutter example continues to call `RunAnywhere` public APIs such as `loadSTTModel`, `loadTTSVoice`, `synthesize`, and `startVoiceSession`

Windows dependencies must be obtained through `bat` scripts and integrated into the existing Windows build path rather than committed as prebuilt binaries.

## Goals

- Restore Windows ONNX backend support for STT, TTS, and VAD
- Restore the Flutter example voice pages on Windows without introducing a Windows-only business logic path
- Achieve one real English voice roundtrip on Windows:
  - microphone capture
  - STT transcription
  - LLM response
  - TTS playback
- Keep the build and packaging flow aligned with the existing monorepo design
- Use `bat`-based dependency acquisition for Windows Sherpa-ONNX artifacts

## Non-Goals

- Add new non-English voice models for the first Windows voice release
- Replace model-based STT/TTS with Windows system speech APIs
- Redesign the Voice Assistant interaction model
- Solve unrelated Flutter example analyzer warnings unless they block this work
- Commit large Windows third-party binaries into the repository

## Scope

### In Scope

- `runanywhere-commons` Windows ONNX dependency acquisition and build
- `runanywhere_onnx` Windows plugin packaging and runtime dependency staging
- Windows capability restoration for:
  - `SpeechToTextView`
  - `TextToSpeechView`
  - `VoiceAssistantView`
- English model validation for:
  - `sherpa-onnx-whisper-*.en`
  - `vits-piper-en_US-*`
  - `vits-piper-en_GB-*`

### Out of Scope

- RAG, Vision, or camera work on Windows
- Full multilingual voice matrix testing
- New public SDK API surface beyond what is required to restore existing features

## Existing State

The repository already contains most of the structural pieces needed for Windows voice support, but they are not fully wired together:

- `sdk/runanywhere-commons/scripts/windows/download-sherpa-onnx.bat` already exists and can download Sherpa-ONNX Windows prebuilts into `third_party/sherpa-onnx-windows`
- `sdk/runanywhere-commons/src/backends/onnx/CMakeLists.txt` already contains a Windows Sherpa-ONNX path branch
- `sdk/runanywhere-flutter/packages/runanywhere_onnx/windows/CMakeLists.txt` already attempts to stage `rac_backend_onnx.dll`
- the example already registers English ONNX STT and TTS models in `RunAnywhereAIApp`
- the example voice pages already use `RunAnywhere` public APIs rather than custom page-local ONNX logic

The current blocker is not feature absence in the UI. The blocker is that the Windows ONNX backend path is incomplete, so example capability gating was used to disable STT, TTS, and Voice Assistant on Windows.

## Proposed Architecture

### 1. Windows Dependency Acquisition Layer

Windows ONNX runtime support will rely on the existing `download-sherpa-onnx.bat` script instead of checking in binaries.

Responsibilities:

- download the correct Sherpa-ONNX Windows shared package version from the centralized `VERSIONS` file
- populate `sdk/runanywhere-commons/third_party/sherpa-onnx-windows`
- guarantee the expected folder layout:
  - `include/`
  - `lib/`
  - `bin/`

`build-windows.bat` becomes the authoritative entrypoint for preparing Windows native dependencies. When invoked with `onnx` or `all`, it must ensure Sherpa-ONNX is present before CMake configuration.

### 2. Native Backend Build Layer

`runanywhere-commons` remains the system of record for Windows native capability availability.

Responsibilities:

- build `rac_backend_onnx.dll`
- link it against:
  - ONNX Runtime
  - Sherpa-ONNX Windows imports
  - any required Windows runtime libraries
- produce a runnable dependency set in `sdk/runanywhere-commons/dist/windows/x64`

The output contract for Windows ONNX support is not just one DLL. It is a runnable directory containing:

- `rac_backend_onnx.dll`
- required Sherpa DLLs
- any required ONNX Runtime DLLs not already bundled elsewhere

This mirrors the existing LlamaCPP Windows path, but with broader runtime dependency staging.

### 3. Flutter Windows Plugin Distribution Layer

The `runanywhere_onnx` Windows plugin is responsible for distributing the ONNX backend runtime files into the built Windows runner directory.

Responsibilities:

- locate the ONNX runtime artifacts from `sdk/runanywhere-commons/dist/windows/x64`
- copy `rac_backend_onnx.dll` and companion runtime DLLs next to the final plugin and runner output
- leave Dart-side backend loading simple:
  - `OnnxBindings` continues to open `rac_backend_onnx`
  - Windows loader resolves the remaining colocated DLLs

This keeps runtime knowledge in the plugin packaging layer instead of spreading DLL names into Dart code.

### 4. Example Capability Restoration Layer

The Flutter example should stop using a hardcoded `Platform.isWindows` cutoff for all voice features.

Responsibilities:

- restore Windows support flags for:
  - STT
  - TTS
  - Voice Assistant
- let runtime backend registration and model readiness determine actual usability
- preserve the existing page logic:
  - `SpeechToTextView` uses SDK STT APIs
  - `TextToSpeechView` uses SDK TTS APIs
  - `VoiceAssistantView` uses `RunAnywhere.startVoiceSession`

This keeps Windows behavior aligned with mobile instead of introducing a parallel feature path.

## File Map

### Native dependency acquisition

- `sdk/runanywhere-commons/scripts/build-windows.bat`
- `sdk/runanywhere-commons/scripts/windows/download-sherpa-onnx.bat`

### Native backend build

- `sdk/runanywhere-commons/src/backends/onnx/CMakeLists.txt`
- `sdk/runanywhere-commons/cmake/FetchONNXRuntime.cmake`
- any directly impacted ONNX backend sources if Windows runtime handling requires it

### Flutter ONNX plugin

- `sdk/runanywhere-flutter/packages/runanywhere_onnx/windows/CMakeLists.txt`
- `sdk/runanywhere-flutter/packages/runanywhere_onnx/lib/native/onnx_bindings.dart`

### Example capability restoration

- `examples/flutter/RunAnywhereAI/lib/core/services/platform_capability_service.dart`
- `examples/flutter/RunAnywhereAI/lib/features/voice/speech_to_text_view.dart`
- `examples/flutter/RunAnywhereAI/lib/features/voice/text_to_speech_view.dart`
- `examples/flutter/RunAnywhereAI/lib/features/voice/voice_assistant_view.dart`

## Detailed Design

### Dependency Download Flow

When the user runs:

- `scripts/build-windows.bat onnx`
- `scripts/build-windows.bat all`

the script should:

1. load build arguments
2. determine ONNX is requested
3. check whether `third_party/sherpa-onnx-windows` is already present and valid
4. if not valid, call `scripts/windows/download-sherpa-onnx.bat`
5. continue to CMake configure and build

Validation should be file-based and lightweight. For example:

- presence of core import library
- presence of primary DLL
- presence of required C API header

This avoids accidental partial extractions being treated as valid installs.

### ONNX Backend Packaging Contract

The Windows native build must stage all runtime dependencies needed by `rac_backend_onnx.dll` into `dist/windows/x64`.

The packaging contract should be:

- `rac_commons.dll`
- `rac_backend_onnx.dll` when ONNX is enabled
- `rac_backend_llamacpp.dll` when LlamaCPP is enabled
- required Sherpa/ONNX dependency DLLs for the enabled backends

This gives Flutter plugins a stable distribution root and avoids duplicating dependency discovery logic in multiple places.

### Plugin Runtime Staging

The Windows ONNX Flutter plugin should stop assuming that only `rac_backend_onnx.dll` matters.

Instead it should:

- enumerate the required ONNX-related files from `dist/windows/x64`
- copy them after plugin build
- expose an empty staged set only when ONNX truly is not built

Warning-only continuation is acceptable when ONNX is not built, but once Windows voice restoration is enabled for the example, missing ONNX runtime files should be treated as a build correctness issue during validation.

### Example Behavior

#### Text-to-Speech

`TextToSpeechView` remains model-based and continues to:

- select a TTS model
- call `RunAnywhere.loadTTSVoice`
- call `RunAnywhere.synthesize`
- play returned PCM audio through the existing audio player service

#### Speech-to-Text

`SpeechToTextView` remains model-based and continues to:

- record audio using the existing recording service
- load an STT model through the SDK
- transcribe through `RunAnywhere`

#### Voice Assistant

`VoiceAssistantView` should no longer be blocked on Windows by capability gating.

It should behave like the mobile path:

- require STT, LLM, and TTS models to be loaded
- allow microphone permission flow
- start a voice session using the SDK
- run a real end-to-end English turn

## Error Handling

Windows voice restoration should replace hard platform disabling with capability-driven failures.

### Error classes

- dependency acquisition failure
  - Sherpa-ONNX download failed
  - extracted files missing or incomplete
- backend runtime staging failure
  - `rac_backend_onnx.dll` missing
  - required dependent DLL missing
- model readiness failure
  - STT/TTS model not downloaded
  - model download succeeded but load failed
- device or permission failure
  - microphone unavailable
  - microphone permission denied
- runtime inference failure
  - STT failure during transcription
  - TTS failure during synthesis
  - voice session error mid-turn

### Handling rules

- do not crash the app on missing ONNX runtime files
- report clear, capability-specific error messages
- keep the page reachable unless the entire feature must be blocked
- prefer runtime diagnostics over platform hard-disables

## Validation Plan

### Build validation

- `cmd /c scripts\build-windows.bat onnx`
- `cmd /c scripts\build-windows.bat all`
- `fvm flutter build windows`

### Native validation

- confirm `sdk/runanywhere-commons/dist/windows/x64` contains:
  - `rac_backend_onnx.dll`
  - required Sherpa/ONNX DLLs

### Runtime validation

- `Onnx.register()` succeeds on Windows
- TTS page:
  - English Piper model downloads
  - model loads
  - synthesis succeeds
  - playback succeeds
- STT page:
  - English Whisper ONNX model downloads
  - model loads
  - recording succeeds
  - transcription succeeds
- Voice Assistant:
  - STT + LLM + TTS models load
  - microphone session starts
  - one English conversation turn completes end-to-end

## Acceptance Criteria

The work is complete when all of the following are true:

- Windows ONNX dependencies can be prepared from `bat` scripts without manual binary check-in
- `rac_backend_onnx.dll` builds successfully on Windows
- Flutter Windows builds can stage the ONNX runtime files automatically
- Windows no longer hard-disables:
  - STT
  - TTS
  - Voice Assistant
- The Flutter example completes one English voice roundtrip on Windows:
  - microphone capture
  - STT
  - LLM response
  - TTS playback

## Risks

### 1. Runtime DLL completeness

Sherpa-ONNX Windows prebuilts may require more runtime DLLs than the plugin currently stages. Missing even one of them can make `rac_backend_onnx.dll` fail to load at runtime.

### 2. Voice session dependency coupling

Voice Assistant depends on STT, TTS, VAD, LLM, recording, playback, and permissions. Even if STT/TTS pages work independently, the full session may still fail due to coupling bugs.

### 3. Build-path fragility on Windows

Windows builds in this repository have already shown sensitivity to path length and generated asset expectations. Validation must use a stable Windows build workflow and explicitly confirm final runner startup.

## Recommended Implementation Order

1. Wire Sherpa-ONNX Windows download into `build-windows.bat`
2. Get `rac_backend_onnx.dll` building on Windows
3. Stage all ONNX runtime DLLs into `dist/windows/x64`
4. Update Flutter ONNX plugin to copy the complete runtime set
5. Restore Windows capability flags for STT, TTS, and Voice Assistant
6. Validate TTS page
7. Validate STT page
8. Validate one English Voice Assistant roundtrip
