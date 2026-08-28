# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

React Native 0.85.3 demo app showcasing the RunAnywhere on-device AI SDK. Demonstrates 8 AI capabilities (LLM chat, STT, TTS, voice assistant, RAG, VLM camera vision, YAML pipeline solutions, settings/model management) across a tab-based UI. Lives inside a Yarn workspace monorepo — consumes local workspace packages (`@runanywhere/core`, `@runanywhere/llamacpp`, `@runanywhere/mlx`, `@runanywhere/onnx`, `@runanywhere/qhexrt`, `@runanywhere/proto-ts`).

## Common Commands

```bash
# Start Metro bundler
yarn start

# Run on iOS / Android
yarn ios
yarn android

# TypeScript type-check (primary verification gate)
yarn typecheck

# Lint
yarn lint          # check
yarn lint:fix      # auto-fix

# Format
yarn format        # check
yarn format:fix    # auto-fix

# Dead code detection
yarn unused

# Install iOS CocoaPods
yarn pod-install

# Full clean rebuild (watchman + node_modules + Pods + reinstall + patch + pod install)
yarn clean

# Smoke test (grep-based SDK API coverage check + typecheck)
./scripts/smoke.sh

# Full build verification (typecheck + optional Gradle assembleDebug + optional Xcode build)
./scripts/verify.sh
# Control via env vars: RUN_ANDROID=1 RUN_IOS=0 RUN_PODS=1 REFRESH_ANDROID_NATIVE=0 REFRESH_IOS_NATIVE=0
```

**No test files exist.** `yarn test` is declared (jest) but no tests have been written. Verification relies on `yarn typecheck` and `scripts/smoke.sh`.

## Architecture

### SDK Integration (Three-Tier Local Dependency Chain)

```
UI Screens (this app)
  └─> @runanywhere/core        (TypeScript API + NitroModules C++ bridge)
      ├─> @runanywhere/llamacpp (llama.cpp LLM/VLM backend)
      ├─> @runanywhere/mlx      (Apple MLX LLM/VLM/speech/embedding backend)
      ├─> @runanywhere/onnx     (ONNX Runtime: STT/TTS/embeddings via Sherpa)
      └─> @runanywhere/qhexrt   (Qualcomm Hexagon NPU, Android-only)
          └─> runanywhere-commons (C++ core, delivered as xcframeworks + .so libs)
```

All SDK packages use **NitroModules** (Nitrogen) for JSI bridging — not standard React Native bridge modules:
- `bridgelessEnabled()` returns `false` in `AppDelegate.swift` — bridgeless mode explicitly disabled for NitroModules compatibility
- A few RN libraries have autolinking disabled/overridden in `react-native.config.js` (see Autolinking Overrides below)
- Android: SDK modules are manually included in `settings.gradle` and `app/build.gradle` (not autolinking)

### Hermes Async Iteration (inherited constraint)

Same manual-iterator rule as the parent SDK (`bindings/react-native/AGENTS.md`) — Hermes can't `for await...of` a NitroModules async iterable. Appears in this app's `ChatScreen.tsx`, `SettingsScreen.tsx`, `ModelSelectionSheet.tsx`, `VLMService.ts`, `VoiceAssistantScreen.tsx`. Always use a manual `iterator.next()` loop there.

### App Initialization Flow (`App.tsx`)

Three-state machine: `loading → ready | error`.

1. Reads optional build-time configuration from the gitignored `.env`; Settings
   can apply an API key for the current process without persisting it
2. `registerBackends()` — registers LlamaCPP, physical-device-only MLX, QHexRT,
   and ONNX; MLX reports unavailable in the iOS Simulator
3. `RunAnywhere.initialize()` with validated HTTPS configuration, or development
   mode when no usable configuration exists
4. `registerAll(backendState)` — seeds only the successfully registered
   backends' model catalogs
5. Renders `<NavigationContainer><TabNavigator /></NavigationContainer>`

Backend registration uses dynamic `require()` with try/catch — `LlamaCPP` and `QHexRT` are optional.

### Navigation (8 Tabs)

| Tab | Screen | Purpose |
|-----|--------|---------|
| Chat | `ChatScreen` | LLM chat with tool calling, streaming, thinking mode |
| STT | `STTScreen` | Speech-to-text (batch + pseudo-live via 3s intervals) |
| TTS | `TTSScreen` | Text-to-speech (ONNX Piper + system TTS) |
| Voice | `VoiceAssistantScreen` | Full voice pipeline (STT + LLM + TTS) |
| RAG | `RAGScreen` | Document Q&A with embedding + LLM |
| Vision | `VisionStackScreen` | Nested stack: VisionHub → VLM (camera vision) |
| Solutions | `SolutionsScreen` | YAML pipeline demo runner |
| Settings | `SettingsScreen` | API config, model downloads, generation params, tools |

### State Management

**Zustand** store (`src/stores/conversationStore.ts`) with file-based JSON persistence at `DocumentDirectoryPath/Conversations/{uuid}.json`. Serializes Date objects to ISO strings. `updateMessage()` is in-memory only (no disk write during streaming).

### Custom Native Modules

`DocumentService` (Swift + ObjC bridge with PDFKit on iOS; Kotlin with PdfBox-Android on Android) extracts PDF/JSON/plaintext text for RAG, using the classic `RCT_EXTERN_MODULE`/`@ReactMethod` bridge pattern (not NitroModules). This is the **only** custom native module left in the app — audio capture/playback and TTS now go entirely through the SDK (see Platform-Specific Behavior below), so don't reintroduce a bespoke native audio module for those.

### VLM Service Architecture

`VLMService` (class in `src/services/`) wraps `@runanywhere/llamacpp` VLM functions. `useVLMCamera` hook manages camera state, three capture modes (single capture, photo library, auto-stream at 2500ms intervals), and EOS token stripping from model output.

### Theme System

Single source of truth: `src/theme/system/` (a Material-3 style scheme consumed via `useTheme()`; brand values mirror `../../../docs/DESIGN_GUIDELINE.md`). Brand primary is RunAnywhere orange `#FF6900` in both light and dark schemes.
- `system/colors.ts` — `brand` constants, primary tonal ramp anchored to `#FF6900`, `lightScheme`/`darkScheme` semantic roles, `frameworkColors` badge hues
- `system/typography.ts` — Material-3 type scale (Figtree UI / MapleMono code; brand fonts per the design guideline are a documented follow-up)
- `system/dimens.ts` / `system/motion.ts` — spacing, radii, motion tokens
- `system/themedStyles.ts` — `useThemedStyles(createStyles)` helper for color-bearing StyleSheets, cached per light/dark scheme

## Build System Details

### iOS

- **Min iOS**: 17.5
- **New Architecture**: enabled (`RCT_NEW_ARCH_ENABLED=1`), Hermes + Fabric both on
- **Arch**: arm64 only (x86_64 simulator excluded in Podfile post_install)
- **Podfile post-install patches**: (1) force iOS 17.5 deployment target on all pods, (2) exclude x86_64 simulator, (3) Xcode sandbox fix (`always_out_of_date`), (4) RNZipArchive `-G` flag removal, (5) `fmt` pod C++17 + `FMT_USE_CONSTEVAL=0` for AppleClang compatibility

### Android

- **Min SDK**: 24, **Target/Compile SDK**: 36, **NDK**: 27.3.13750724, **Kotlin**: 2.1.20, **Gradle**: 9.0.0
- **ABI filter**: `arm64-v8a` only
- **`syncSdkNativeLibs` Gradle task**: copies `.so` files from `bindings/react-native/` into `node_modules/@runanywhere/*/android/` before each build (runs before `preBuild`)
- **`packaging.jniLibs.useLegacyPackaging = true`** (deliberately, not the modern `false`): required for QHexRT/QNN — FastRPC `fopen()`s the Hexagon HTP skel `.so`s (`libQnnHtpV*Skel.so`) to offload to the cDSP, and modern packaging (`extractNativeLibs=false`) page-maps `.so`s straight from the APK with no on-disk file, which fails DSP load with `"cannot open libQnnHtpV81Skel.so, errno 2"`. Legacy packaging extracts them to `nativeLibraryDir` instead. The Android 15+ 16KB-page requirement is covered separately by `ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON` (CMake) — the shipped `.so`s are already 16KB-aligned, so legacy packaging doesn't conflict with it.
- **`packagingOptions.pickFirsts`**: resolves 12+ duplicate `.so` conflicts across SDK packages
- QHexRT/QNN: the QHexRT package declares FastRPC libraries and installs DSP skels from assets

### Monorepo / Metro

`metro.config.js` sets `workspaceRoot` three levels up (monorepo root). Watches entire monorepo for hot-reload of workspace package edits. Pins single instances of `react-native`, `react-native-nitro-modules`, and `react` via `extraNodeModules` to prevent duplicates. `unstable_enableSymlinks: true` for Yarn workspace symlink resolution.

### Patches

`scripts/patch-agp-version.js` (downgrades AGP from 8.12.0 to 8.11.1 in `@react-native/gradle-plugin` for Android Studio compatibility) exists but **is not currently invoked anywhere** — not from `postinstall.js`, `package.json`, or any Gradle file. Verify with a repo-wide grep before assuming it runs; if AGP version mismatches with Android Studio resurface, this is the script to wire back in or run by hand. `postinstall.js` itself only runs `sync-solutions-yamls.js`, generates a debug keystore if missing, then (outside CI) `patch-package` and `pod-install.sh`.

## TypeScript Path Aliases

Defined in `tsconfig.json`:
- `@/*` → `src/*`
- `@components/*`, `@screens/*`, `@hooks/*`, `@theme/*`, `@types/*`, `@services/*`, `@store/*`, `@utils/*` → corresponding `src/` subdirectories
- `@runanywhere/proto-ts` resolves as a normal workspace package, not a tsconfig path alias

## Linting Rules

- **Unused imports**: hard error (`unused-imports/no-unused-imports: "error"`)
- **`console.log`**: warned — only `console.warn` and `console.error` allowed
- **Inline styles**: warned (`react-native/no-inline-styles: "warn"`)
- **Type imports**: prefer `import type` (`consistent-type-imports: "warn"`)
- **`any`**: warned (`no-explicit-any: "warn"`) — softer than the parent SDK packages, which treat it as an error
- **Prettier**: single quotes, 2-space tabs, trailing commas (es5), consistent quote props

## Autolinking Overrides (`react-native.config.js`)

Only one override is currently declared:

| Package | iOS | Android | Reason |
|---------|-----|---------|--------|
| `react-native-nitro-modules` | enabled | disabled (manual) | NitroModules requires custom Gradle config; included by hand in `android/settings.gradle` instead |

(`react-native-live-audio-stream`, `react-native-sound`, `react-native-tts`, and `react-native-audio-recorder-player` are **not** dependencies of this app — an older revision of this doc listed autolinking overrides for them; don't reintroduce that from memory.)

## Key SDK API Imports

From `@runanywhere/core`: `RunAnywhere`, `SDKEnvironment`, the v3 public types (`LlmOptions`, `GenerationResult`, `Transcription`, `DownloadEvent`, `VoiceEvent`, …), the input factories `AudioInputs` / `ImageInputs`, and the helpers `formatFramework`, `AudioConvert`, `AudioCaptureManager`, `AudioPlaybackManager`, `createPushableAudioStream`, `SDKException`.

Every capability is reached through a namespace: `RunAnywhere.llm`, `.vlm`, `.stt`, `.tts`, `.vad`, `.embeddings`, `.rerank`, `.images`, `.diarization`, `.segmentation`, `.voice`, `.rag`, `.models`, `.lora`, plus the platform namespaces `.storage`, `.logging`, `.auth`, `.pluginLoader`, `.solutions`. Options and results use the spec names, so do not reach for the proto request/result messages in app code.

Generated enums still come from `@runanywhere/proto-ts/*`: `ModelCategory`, `InferenceFramework`, `ModelInfo`, `ToolDefinition`, `ToolParameterType`, `ModelArtifactType`.

Backend packages are optional registration adapters. Register example models through `RunAnywhere.models.register()` (one builder for single-url, archive, and multi-file rows) using generated proto enum values.

From `@runanywhere/llamacpp`: `LlamaCPP.register()`. From `@runanywhere/onnx`: `ONNX.register()`. From `@runanywhere/qhexrt`: `QHexRT.register()` (optional, Android/Snapdragon only).

Voice sessions are SDK-owned: `RunAnywhere.voice.createSession(...)` captures the microphone, segments turns, and plays replies, so the app never drives a mic driver or maps the proto `VoiceEvent` oneof by hand.

## Platform-Specific Behavior

Audio, TTS, STT, and LLM streaming are unified across iOS/Android through the SDK — there is no per-platform branch in the screens for any of these (a prior revision of this doc described a `NativeAudioModule` and Android-only streaming fallbacks; neither exists in the current source — don't recreate them):
- **STT recording**: `AudioCaptureManager` (`@runanywhere/core`) captures on both platforms; `RunAnywhere.stt.transcribe()` does the rest
- **TTS**: `RunAnywhere.tts.speak()` / `.synthesize()` / `.stop()` handle synthesis and playback natively on both platforms
- **LLM streaming**: `ChatScreen` drives `RunAnywhere.llm.generateStream()` with the manual iterator (see Hermes Async Iteration above) on both platforms — no non-streaming fallback
- **QHexRT NPU backend**: still Android-only; model registration uses SDK QNN-context metadata and native arch resolution

## After Modifying the SDK

- **TypeScript changes**: Picked up by Metro automatically (hot-reload)
- **C++ changes**: Rebuild commons in the owning layer (`./bindings/swift/scripts/build-core-xcframework.sh` / `./scripts/build/build-core-android.sh` from the repo root) and re-stage into the RN packages with `bindings/react-native/scripts/package-sdk.sh --natives-from <build/native-artifacts>`
- **Missing xcframeworks** (`RACommons.xcframework`, `RABackendLLAMACPP.xcframework`, etc.): Means the native artifact build step was skipped — run `build-core-xcframework.sh` / `build-core-android.sh`, then re-run `scripts/package-sdk.sh --natives-from PATH`
