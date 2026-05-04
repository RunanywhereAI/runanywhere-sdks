# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

React Native 0.83.1 demo app showcasing the RunAnywhere on-device AI SDK. Demonstrates 8 AI capabilities (LLM chat, STT, TTS, voice assistant, RAG, VLM camera vision, YAML pipeline solutions, settings/model management) across a tab-based UI. Lives inside a Yarn workspace monorepo — consumes local workspace packages (`@runanywhere/core`, `@runanywhere/llamacpp`, `@runanywhere/onnx`, `@runanywhere/proto-ts`) plus the published `@runanywhere/genie` (Android/Snapdragon NPU only).

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
      ├─> @runanywhere/onnx     (ONNX Runtime: STT/TTS/embeddings via Sherpa)
      └─> @runanywhere/genie    (Qualcomm Snapdragon NPU, Android-only)
          └─> runanywhere-commons (C++ core, delivered as xcframeworks + .so libs)
```

All SDK packages use **NitroModules** (Nitrogen) for JSI bridging — not standard React Native bridge modules. This has critical implications:
- `bridgelessEnabled()` returns `false` in `AppDelegate.swift` — bridgeless mode explicitly disabled for NitroModules compatibility
- Several RN libraries have autolinking disabled in `react-native.config.js` due to New Architecture/Nitrogen incompatibility (`react-native-live-audio-stream` on iOS, `react-native-sound`/`react-native-tts`/`react-native-audio-recorder-player` on both)
- Android: SDK modules are manually included in `settings.gradle` and `app/build.gradle` (not autolinking)

### Hermes Async Iteration Pattern (Critical)

Hermes does not support `for await...of` with NitroModules custom async iterables. **Every** SDK method returning an `AsyncIterable` uses manual iteration:

```typescript
const iterator = asyncIterable[Symbol.asyncIterator]();
let result = await iterator.next();
while (!result.done) {
  // process result.value
  result = await iterator.next();
}
```

This pattern appears in: `ChatScreen.tsx`, `SettingsScreen.tsx`, `ModelSelectionSheet.tsx`, `VLMService.ts`, `VoiceAssistantScreen.tsx`. Always follow this pattern — never use `for await`.

### App Initialization Flow (`App.tsx`)

Three-state machine: `loading → ready | error`.

1. `initializeNitroModulesGlobally()` — sets up Nitrogen JSI bridge
2. Reads stored API key + base URL from AsyncStorage (set in Settings screen)
3. `RunAnywhere.initialize()` with config (dev or prod based on stored credentials)
4. `registerModulesAndModels()` — registers backends (LlamaCPP, Genie, ONNX) and all model URLs
5. Renders `<NavigationContainer><TabNavigator /></NavigationContainer>`

Backend registration uses dynamic `require()` with try/catch — `LlamaCPP` and `Genie` are optional.

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

| Module | iOS | Android | Purpose |
|--------|-----|---------|---------|
| `NativeAudioModule` | Swift + ObjC bridge | N/A (iOS-only) | AVFoundation recording (16kHz mono PCM), playback, AVSpeechSynthesizer TTS |
| `DocumentService` | Swift + ObjC bridge (PDFKit) | Kotlin (PdfBox-Android) | PDF/JSON/plaintext extraction for RAG |

Both use classic `RCT_EXTERN_MODULE` bridge pattern (not NitroModules).

### VLM Service Architecture

`VLMService` (class in `src/services/`) wraps `@runanywhere/llamacpp` VLM functions. `useVLMCamera` hook manages camera state, three capture modes (single capture, photo library, auto-stream at 2500ms intervals), and EOS token stripping from model output.

### Theme System

Mirrors iOS Swift app design tokens exactly:
- `colors.ts` — 36+ named constants + dark mode overrides (dark mode not yet wired to Appearance API)
- `typography.ts` — 11 text styles matching iOS Dynamic Type sizes, Platform.select for font family
- `spacing.ts` — semantic spacing, padding, icon sizes, button heights, border radii

## Build System Details

### iOS

- **Min iOS**: 15.1
- **New Architecture**: enabled (`RCT_NEW_ARCH_ENABLED=1`), Hermes + Fabric both on
- **Arch**: arm64 only (x86_64 simulator excluded in Podfile post_install)
- **Podfile post-install patches**: (1) force iOS 15.1 deployment target on all pods, (2) exclude x86_64 simulator, (3) Xcode 16 sandbox fix (`always_out_of_date`), (4) RNZipArchive `-G` flag removal, (5) `fmt` pod C++17 + `FMT_USE_CONSTEVAL=0` for Xcode/AppleClang compatibility

### Android

- **Min SDK**: 24, **Target/Compile SDK**: 36, **NDK**: 27.0.12077973, **Kotlin**: 2.1.20, **Gradle**: 9.0.0
- **ABI filter**: `arm64-v8a` only
- **`syncSdkNativeLibs` Gradle task**: copies `.so` files from `sdk/runanywhere-react-native/` into `node_modules/@runanywhere/*/android/` before each build (runs before `preBuild`)
- **16KB page alignment**: enabled for Android 15+ compatibility (`useLegacyPackaging=false`, `ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON`)
- **`packagingOptions.pickFirsts`**: resolves 12+ duplicate `.so` conflicts across SDK packages
- Qualcomm Genie: `libcdsprpc.so` declared as optional native library in AndroidManifest

### Monorepo / Metro

`metro.config.js` sets `workspaceRoot` three levels up (monorepo root). Watches entire monorepo for hot-reload of workspace package edits. Pins single instances of `react-native`, `react-native-nitro-modules`, and `react` via `extraNodeModules` to prevent duplicates. `unstable_enableSymlinks: true` for Yarn workspace symlink resolution.

### Patches (Applied Automatically via postinstall)

1. **`patches/react-native+0.83.1.patch`**: Replaces `std::format` (C++20) with `std::ostringstream` (C++17) in `graphicsConversions.h` for compiler compatibility
2. **`scripts/patch-agp-version.js`**: Downgrades AGP from 8.12.0 to 8.11.1 in `@react-native/gradle-plugin` for Android Studio compatibility

## TypeScript Path Aliases

Defined in `tsconfig.json`:
- `@/*` → `src/*`
- `@components/*`, `@screens/*`, `@hooks/*`, `@theme/*`, `@types/*`, `@services/*`, `@store/*`, `@utils/*` → corresponding `src/` subdirectories
- `@runanywhere/proto-ts` → workspace package exports

## Linting Rules

- **Unused imports**: hard error (`unused-imports/no-unused-imports: "error"`)
- **`console.log`**: warned — only `console.warn` and `console.error` allowed
- **Inline styles**: warned (`react-native/no-inline-styles: "warn"`)
- **Type imports**: prefer `import type` (`consistent-type-imports: "warn"`)
- **`any`**: warned (`no-explicit-any: "warn"`)
- **Prettier**: single quotes, 2-space tabs, trailing commas (es5), consistent quote props

## Autolinking Overrides (`react-native.config.js`)

| Package | iOS | Android | Reason |
|---------|-----|---------|--------|
| `react-native-nitro-modules` | enabled | disabled (manual) | NitroModules requires custom Gradle config |
| `react-native-live-audio-stream` | disabled | enabled | Incompatible with iOS New Architecture |
| `react-native-audio-recorder-player` | disabled | disabled | Not used directly; SDK handles audio |
| `react-native-sound` | disabled | disabled | Used only on Android via lazy require |
| `react-native-tts` | disabled | disabled | Used only on Android via lazy require |

## Key SDK API Imports

From `@runanywhere/core`: `RunAnywhere`, `SDKEnvironment`, `ModelCategory`, `LLMFramework`, `ModelArtifactType`, `initializeNitroModulesGlobally`, `getChip`, `getNPUDownloadUrl`, `ragCreatePipeline`, `ragIngest`, `ragQuery`, `VoiceAgentStreamAdapter`, `FileSystem`, `Hardware`, `requireDeviceInfoModule`, `STTLanguage`, `VLMImageFormat`, `ToolParameterType`

From `@runanywhere/llamacpp`: `LlamaCPP.register()`, `processImageStream`, `loadVLMModel`, `isVLMModelLoaded`, `cancelVLMGeneration`

From `@runanywhere/onnx`: `ONNX.register()`

From `@runanywhere/genie`: `Genie.register()` (optional, Android/Snapdragon only)

From `@runanywhere/proto-ts`: `AudioFormat`, `PipelineState`, `VADEventType`, `VoiceEvent`

## Platform-Specific Behavior

- **iOS TTS**: Uses `NativeModules.NativeAudioModule` (AVSpeechSynthesizer) for system TTS, and ONNX synthesis + WAV file creation for model TTS
- **Android TTS**: Uses lazy-loaded `react-native-tts` for system TTS, lazy-loaded `react-native-sound` for ONNX WAV playback
- **iOS STT recording**: `NativeAudioModule.startRecording()` via AVFoundation
- **Android STT recording**: `RunAnywhere.Audio.startRecording()` from SDK
- **iOS streaming generation**: Manual async iteration of `RunAnywhere.generateStream()`
- **Android streaming generation**: Falls back to non-streaming `RunAnywhere.generate()` in ChatScreen
- **Genie NPU backend**: Android-only (no iOS Podfile entry); models filtered per Qualcomm chip ID (`8elite`, `8elite-gen5`)

## After Modifying the SDK

- **TypeScript changes**: Picked up by Metro automatically (hot-reload)
- **C++ changes**: Require rebuilding native artifacts: `./scripts/build-react-native.sh --local --rebuild-commons` from the SDK directory
- **Missing xcframeworks** (`RACommons.xcframework`, `RABackendLLAMACPP.xcframework`, etc.): Means native artifact build step was skipped — run `build-core-xcframework.sh` / `build-core-android.sh`
