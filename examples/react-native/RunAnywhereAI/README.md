# RunAnywhere AI - React Native Example

<p align="center">
  <img src="../../../examples/logo.svg" alt="RunAnywhere Logo" width="120"/>
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/runanywhere/id6756506307">
    <img src="https://img.shields.io/badge/App%20Store-Download-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download on the App Store" />
  </a>
  <a href="https://play.google.com/store/apps/details?id=com.runanywhere.runanywhereai">
    <img src="https://img.shields.io/badge/Google%20Play-Download-414141?style=for-the-badge&logo=google-play&logoColor=white" alt="Get it on Google Play" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2015.1%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS 15.1+" />
  <img src="https://img.shields.io/badge/Platform-Android%207.0%2B-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android 7.0+" />
  <img src="https://img.shields.io/badge/React%20Native-0.81-61DAFB?style=flat-square&logo=react&logoColor=white" alt="React Native 0.81" />
  <img src="https://img.shields.io/badge/TypeScript-5.5-3178C6?style=flat-square&logo=typescript&logoColor=white" alt="TypeScript 5.5" />
  <img src="https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square" alt="License" />
</p>

**A production-ready reference app demonstrating the [RunAnywhere React Native SDK](../../../sdk/runanywhere-react-native/) capabilities for on-device AI.** This cross-platform app showcases how to build privacy-first, offline-capable AI features with LLM chat, speech-to-text, text-to-speech, and a complete voice assistant pipeline—all running locally on your device.

---

## Running This App (Local Development)

> **Important:** This sample app consumes the [RunAnywhere React Native SDK](../../../sdk/runanywhere-react-native/) through local `file:` packages. A clean clone needs JavaScript dependencies, generated Nitro/React Native codegen output, CocoaPods, and locally staged native binaries before both platforms are reproducible.

### Clean-Clone Bring-Up

Prerequisites:

- Node.js 18+ and Corepack-enabled Yarn 3 (`corepack enable`; this project uses `nodeLinker: node-modules`).
- Xcode 15+ with iOS simulator runtimes and command line tools selected.
- CocoaPods (`pod --version` should succeed).
- Android Studio with Android SDK 24+, build tools, platform tools, CMake, and NDK; export `ANDROID_HOME` and `ANDROID_NDK_HOME`.
- JDK 17 and enough local disk for native build output plus downloaded AI models.

From a fresh checkout:

```bash
cd examples/react-native/RunAnywhereAI
corepack enable
yarn install --ignore-scripts

# Refresh local file: packages after dependency or package layout changes.
yarn install --ignore-scripts --force

# Build or refresh local SDK native artifacts when the checkout has no staged binaries.
cd ../../..
./scripts/build/android.sh arm64-v8a
./scripts/build/ios-xcframework.sh
cd examples/react-native/RunAnywhereAI

# Generate React Native/Nitro iOS codegen through the locked Bundler/CocoaPods graph.
# scripts/examples/react-native/pod-install.sh runs `bundle install` if needed, then `bundle exec pod install`.
yarn pod-install

# Android build gate.
cd android && ./gradlew :app:assembleDebug && cd ..

# iOS build gate.
xcodebuild \
  -project ios/RunAnywhereAI.xcodeproj \
  -scheme RunAnywhereAI \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Notes:

- The default install command intentionally uses `--ignore-scripts` so `patch-package` postinstall hooks do not hide clean-clone issues. If you need to apply local patches, run `yarn postinstall` after inspecting them.
- Local iOS XCFrameworks are staged by `scripts/build/ios-xcframework.sh` into the Swift SDK and synced into the React Native packages. Missing `RACommons.xcframework`, `RABackendLLAMACPP.xcframework`, `RABackendONNX.xcframework`, or `RABackendSherpa.xcframework` usually means the root native artifact step has not run.
- Generated Nitro and React Native codegen files are produced during `pod install`; remove stale `ios/build/generated` output if schema changes are not reflected.
- If formatting tools disagree after a dependency refresh, use the existing workaround: run `yarn format:fix` from this sample and review the diff before committing.
- `scripts/examples/react-native/verify.sh` runs the reproducible build gates; set `RUN_IOS=1` to include the optional iOS build.

### How It Works

This sample app's `package.json` uses workspace dependencies to reference the local React Native SDK packages:

```
This Sample App → Local RN SDK packages (sdk/runanywhere-react-native/packages/)
                          ↓
              Local XCFrameworks/JNI libs (in each package's ios/ and android/ directories)
                          ↑
        Staged by: scripts/release/package-rn.sh --natives-from PATH
```

`scripts/package-sdk.sh --natives-from PATH`:
1. Stages prebuilt natives from the owning layer (`runanywhere-commons`) into each RN package: `packages/core` gets `RACommons`, `packages/llamacpp` gets `RABackendLLAMACPP`, `packages/onnx` gets `RABackendONNX` + `RABackendSherpa`.
2. Copies XCFrameworks to `packages/*/ios/Binaries/`.
3. Copies JNI `.so` files into `packages/*/android/src/main/jniLibs/<abi>/`.
4. Type-checks each package and produces `dist/sdk-rn/*.tgz` with matching `.sha256` files.

`yarn native:local` writes the `.testlocal` marker files that enable local library consumption (use `yarn native:remote` to revert).

If you do not need to rebuild commons from source, run the per-package download helpers (`yarn core:download-ios`, `yarn core:download-android`, etc.) from `sdk/runanywhere-react-native/` to pull prebuilt natives from a GitHub release directly.

### After Modifying the SDK

- **TypeScript SDK code changes**: Metro bundler picks them up automatically (Fast Refresh)
- **C++ code changes** (in `runanywhere-commons`):
  ```bash
  # Rebuild natives in the owning layer
  ./scripts/build/ios-xcframework.sh   # iOS
  ./scripts/build/android.sh       # Android

  # Re-stage them into the RN packages
  ./scripts/release/package-rn.sh --natives-from build/native-artifacts
  ```

---

## Try It Now

<p align="center">
  <a href="https://apps.apple.com/us/app/runanywhere/id6756506307">
    <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="50"/>
  </a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://play.google.com/store/apps/details?id=com.runanywhere.runanywhereai">
    <img src="https://upload.wikimedia.org/wikipedia/commons/7/78/Google_Play_Store_badge_EN.svg" alt="Get it on Google Play" height="50"/>
  </a>
</p>

Download the app from the App Store or Google Play Store to try it out.

---

## Screenshots

<p align="center">
  <img src="../../../docs/screenshots/main-screenshot.jpg" alt="RunAnywhere AI Chat Interface" width="220"/>
</p>

---

## Features

This sample app demonstrates the full power of the RunAnywhere React Native SDK:

| Feature | Description | SDK Integration |
|---------|-------------|-----------------|
| **AI Chat** | Interactive LLM conversations with streaming responses | `RunAnywhere.generateStream()` |
| **Conversation Management** | Create, switch, and delete chat conversations | `ConversationStore` |
| **Real-time Analytics** | Token speed, generation time, inference metrics | Message analytics display |
| **Speech-to-Text** | Voice transcription with batch & live modes | `RunAnywhere.transcribe()` |
| **Text-to-Speech** | Neural voice synthesis with Piper TTS | `RunAnywhere.synthesize()` |
| **Voice Assistant** | Full STT → LLM → TTS pipeline | Voice pipeline orchestration |
| **Voice Activity Detection** | Live VAD stream demo | `RunAnywhere.streamVAD()` |
| **Model Management** | Download, load, and manage multiple AI models | `RunAnywhere.downloadModel()` |
| **Storage Management** | View storage usage and delete models | `RunAnywhere.getStorageInfo()` |
| **Offline Support** | All features work without internet | On-device inference |
| **Cross-Platform** | Single codebase for iOS and Android | React Native + Nitrogen/Nitro |

---

## Architecture

The app follows modern React Native architecture patterns with a multi-package SDK structure:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         React Native UI Layer                            │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────────┐ │
│  │   Chat   │ │   STT    │ │   TTS    │ │  Voice   │ │    Settings    │ │
│  │  Screen  │ │  Screen  │ │  Screen  │ │ Assistant│ │     Screen     │ │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └───────┬────────┘ │
├───────┼────────────┼────────────┼────────────┼───────────────┼──────────┤
│       │            │            │            │               │          │
│  ┌────▼────────────▼────────────▼────────────▼───────────────▼────────┐ │
│  │              @runanywhere/core (TypeScript API)                     │ │
│  │     RunAnywhere.initialize(), loadModel(), generate(), etc.         │ │
│  └──────────────────────────────┬──────────────────────────────────────┘ │
│                                 │                                        │
│         ┌───────────────────────┼───────────────────────┐               │
│         │                       │                       │               │
│  ┌──────▼──────┐         ┌──────▼──────┐         ┌──────▼──────┐        │
│  │@runanywhere │         │@runanywhere │         │   Native    │        │
│  │  /llamacpp  │         │    /onnx    │         │   Bridges   │        │
│  │  (LLM/GGUF) │         │  (STT/TTS)  │         │  (JSI/Nitro)│        │
│  └──────┬──────┘         └──────┬──────┘         └──────┬──────┘        │
├─────────┼───────────────────────┼───────────────────────┼───────────────┤
│         │                       │                       │               │
│  ┌──────▼───────────────────────▼───────────────────────▼──────────────┐│
│  │                    runanywhere-commons (C++)                         ││
│  │              Core inference engine, model management                 ││
│  └──────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Architecture Decisions

- **Multi-Package SDK** — Core API, LlamaCPP, and ONNX as separate packages for modularity
- **TypeScript First** — Full type safety across the entire SDK API surface
- **JSI/Nitro Bridges** — Direct native module communication for performance
- **Zustand State Management** — Lightweight, performant state for conversations
- **Tab-Based Navigation** — React Navigation bottom tabs matching iOS/Android patterns
- **Theme System** — Consistent design tokens across all components

---

## Project Structure

```
RunAnywhereAI/
├── App.tsx                           # App entry, SDK initialization, model registration
├── index.js                          # React Native entry point
├── package.json                      # Dependencies and scripts
├── tsconfig.json                     # TypeScript configuration
│
├── src/
│   ├── screens/
│   │   ├── ChatScreen.tsx            # LLM chat with streaming & conversation management
│   │   ├── ChatAnalyticsScreen.tsx   # Message analytics and performance metrics
│   │   ├── ConversationListScreen.tsx # Conversation history management
│   │   ├── MoreScreen.tsx            # More hub matching iOS navigation
│   │   ├── STTScreen.tsx             # Speech-to-text with batch/live modes
│   │   ├── TTSScreen.tsx             # Text-to-speech synthesis & playback
│   │   ├── VADScreen.tsx             # Voice activity detection stream demo
│   │   ├── VoiceAssistantScreen.tsx  # Full STT → LLM → TTS pipeline
│   │   ├── StorageScreen.tsx         # Storage management
│   │   └── SettingsScreen.tsx        # Settings and tool calling
│   │
│   ├── components/
│   │   ├── chat/
│   │   │   ├── ChatInput.tsx         # Message input with send button
│   │   │   ├── MessageBubble.tsx     # Message display with analytics
│   │   │   ├── TypingIndicator.tsx   # AI thinking animation
│   │   │   └── index.ts              # Component exports
│   │   ├── common/
│   │   │   ├── ModelStatusBanner.tsx # Shows loaded model and framework
│   │   │   ├── ModelRequiredOverlay.tsx # Prompts model selection
│   │   │   └── index.ts
│   │   └── model/
│   │       ├── ModelSelectionSheet.tsx # Model picker with download progress
│   │       └── index.ts
│   │
│   ├── navigation/
│   │   └── TabNavigator.tsx          # Bottom tab navigation
│   │
│   ├── stores/
│   │   └── conversationStore.ts      # Zustand store for chat persistence
│   │
│   ├── theme/
│   │   ├── colors.ts                 # Color palette matching iOS design
│   │   ├── typography.ts             # Font styles and text variants
│   │   └── spacing.ts                # Layout constants and dimensions
│   │
│   ├── types/
│   │   ├── chat.ts                   # Message and conversation types
│   │   ├── model.ts                  # Model info and framework types
│   │   ├── settings.ts               # Settings and storage types
│   │   ├── voice.ts                  # Voice pipeline types
│   │   └── index.ts                  # Root navigation types
│   │
│   └── utils/
│       └── AudioService.ts           # Native audio recording abstraction
│
├── ios/
│   ├── RunAnywhereAI/
│   │   ├── AppDelegate.swift         # iOS app delegate
│   │   ├── NativeAudioModule.swift   # Native audio recording/playback
│   │   └── Images.xcassets/          # iOS app icons and images
│   ├── Podfile                       # CocoaPods dependencies
│   └── RunAnywhereAI.xcworkspace/    # Xcode workspace
│
└── android/
    ├── app/
    │   ├── src/main/
    │   │   ├── java/.../MainActivity.kt
    │   │   ├── res/                   # Android resources
    │   │   └── AndroidManifest.xml
    │   └── build.gradle
    └── settings.gradle
```

---

## Quick Start

### Prerequisites

- **Node.js** 18+
- **React Native CLI** or **npx**
- **Xcode** 15+ (iOS development)
- **Android Studio** Hedgehog+ (Android development)
- **CocoaPods** (iOS)
- **~2GB** free storage for AI models

### Clone & Install

```bash
# Clone the repository
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/examples/react-native/RunAnywhereAI

# Install JavaScript dependencies
npm install

# Install iOS dependencies (bootstraps locked Bundler gemset, then runs pod install)
yarn pod-install
```

### Run on iOS

```bash
# Start Metro bundler
npm start

# In another terminal, run on iOS
npx react-native run-ios

# Or run on a specific simulator
npx react-native run-ios --simulator="iPhone 15 Pro"
```

### Run on Android

```bash
# Start Metro bundler
npm start

# In another terminal, run on Android
npx react-native run-android
```

### Run via Command Line

```bash
# iOS - Build and run
npx react-native run-ios --mode Release

# Android - Build and run
npx react-native run-android --mode release
```

---

## SDK Integration Examples

### Initialize the SDK

The SDK is initialized in `App.tsx` with a two-phase initialization pattern:

```typescript
import {
  RunAnywhere,
  SDKEnvironment,
} from '@runanywhere/core';
import {
  ModelCategory,
  InferenceFramework,
  ModelArtifactType,
  CurrentModelRequest,
  ModelLoadRequest,
} from '@runanywhere/proto-ts/model_types';
import { LlamaCPP } from '@runanywhere/llamacpp';
import { ONNX } from '@runanywhere/onnx';

// Phase 1: Initialize SDK
await RunAnywhere.initialize({
  apiKey: '',  // Empty in development mode
  baseURL: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});

// Phase 2: Register optional backends and proto-described models. Both
// `LlamaCPP.register()` and `ONNX.register()` return `Promise<boolean>` and
// must be awaited before registering models against them; a `false` result
// means the native backend was not installed and dependent models should be
// skipped.
const llamaRegistered = await LlamaCPP.register();
if (llamaRegistered) {
  await RunAnywhere.registerModel({
    id: 'smollm2-360m-q8_0',
    name: 'SmolLM2 360M Q8_0',
    url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/...',
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    memoryRequirement: 500_000_000,
  });
}

const onnxRegistered = await ONNX.register();
if (onnxRegistered) {
  await RunAnywhere.registerModel({
    id: 'sherpa-onnx-whisper-tiny.en',
    name: 'Sherpa Whisper Tiny (ONNX)',
    url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/...',
    framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
    memoryRequirement: 75_000_000,
  });
}
```

### Download & Load a Model

```typescript
// Download with progress tracking (AsyncIterable — Hermes-safe iterator loop)
const downloadIter = RunAnywhere.downloadModel(modelId)[Symbol.asyncIterator]();
let downloadResult = await downloadIter.next();
while (!downloadResult.done) {
  const progress = downloadResult.value;
  console.log(`Download: ${(progress.progress * 100).toFixed(1)}%`);
  downloadResult = await downloadIter.next();
}

// Load LLM model into memory (proto request, matches iOS Swift)
const loadResult = await RunAnywhere.loadModel(ModelLoadRequest.fromPartial({
  modelId,
  category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
}));
if (!loadResult.success) {
  throw new Error(loadResult.errorMessage || 'Model load failed');
}

// Check if model is loaded
const current = await RunAnywhere.currentModel(CurrentModelRequest.fromPartial({
  category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
  includeModelMetadata: false,
}));
const isLoaded = current.found && current.modelId.length > 0;
```

### Stream Text Generation

```typescript
import { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';

// Generate with streaming (proto-canonical: AsyncIterable<LLMStreamEvent>)
const options = LLMGenerationOptions.fromPartial({
  maxTokens: 1000,
  temperature: 0.7,
  streamingEnabled: true,
});
const stream = RunAnywhere.generateStream(prompt, options);

// Hermes constraint: `for await...of` does not work with NitroModules
// custom async iterables — use manual iterator.next() loops.
let fullResponse = '';
const iterator = stream[Symbol.asyncIterator]();
let result = await iterator.next();
while (!result.done) {
  const event = result.value;
  if (event.token) {
    fullResponse += event.token;
    updateMessage(fullResponse);
  }
  if (event.isFinal) break;
  result = await iterator.next();
}
```

### Non-Streaming Generation

```typescript
import { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';

const options = LLMGenerationOptions.fromPartial({
  maxTokens: 256,
  temperature: 0.7,
});
const result = await RunAnywhere.generate(prompt, options);

console.log('Response:', result.text);
console.log('Tokens:', result.tokensUsed);
console.log('Model:', result.modelUsed);
```

### Speech-to-Text

```typescript
import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import { STTLanguage } from '@runanywhere/proto-ts/stt_options';

// Load STT model by id (proto request, matches iOS Swift)
await RunAnywhere.loadModel(ModelLoadRequest.fromPartial({
  modelId,
  category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
}));

// Transcribe audio bytes or base64 captured by the platform recorder
const result = await RunAnywhere.transcribe(audioBase64, {
  language: STTLanguage.STT_LANGUAGE_EN,
  audioFormat: AudioFormat.AUDIO_FORMAT_WAV,
  sampleRate: 16000,
});

console.log('Transcription:', result.text);
console.log('Confidence:', result.confidence);
```

### Text-to-Speech

```typescript
import { AudioFormat } from '@runanywhere/proto-ts/model_types';

// Load TTS voice model by id
await RunAnywhere.loadModel(ModelLoadRequest.fromPartial({
  modelId,
  category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
}));

// Synthesize speech (proto-canonical TTSOptions)
const result = await RunAnywhere.synthesize(text, {
  voice: 'default',
  languageCode: '',
  speakingRate: 1.0,
  pitch: 1.0,
  volume: 1.0,
  enableSsml: false,
  audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
});

// result.audioData (Uint8Array of float32 PCM bytes)
// result.sampleRate, result.durationMs
```

### Voice Pipeline (STT → LLM → TTS)

```typescript
import RNFS from 'react-native-fs';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import { STTLanguage } from '@runanywhere/proto-ts/stt_options';

// 1. Record audio using AudioService
const audioPath = await AudioService.startRecording();

// 2. Stop and get audio
const { uri } = await AudioService.stopRecording();

// 3. Transcribe
const audioBase64 = await RNFS.readFile(uri, 'base64');
const sttResult = await RunAnywhere.transcribe(audioBase64, {
  language: STTLanguage.STT_LANGUAGE_EN,
  audioFormat: AudioFormat.AUDIO_FORMAT_WAV,
  sampleRate: 16000,
});

// 4. Generate LLM response
const llmResult = await RunAnywhere.generate(sttResult.text, {
  maxTokens: 500,
  temperature: 0.7,
});

// 5. Synthesize speech
const ttsResult = await RunAnywhere.synthesize(llmResult.text);

// 6. Play audio (using native audio module)
```

### Model Management

```typescript
import { StorageDeleteRequest } from '@runanywhere/proto-ts/storage_types';

// Get available models
const models = await RunAnywhere.listModels();
const downloaded = await RunAnywhere.downloadedModels();

// Get storage info
const storage = await RunAnywhere.getStorageInfo();
console.log('Free:', storage.device?.freeBytes ?? 0);
console.log('Models:', storage.totalModelsBytes);

// Delete a model through the canonical storage bridge
await RunAnywhere.deleteStorage(StorageDeleteRequest.fromPartial({
  modelIds: [modelId],
  deleteFiles: true,
  clearRegistryPaths: true,
  unloadIfLoaded: true,
  allowPlatformDelete: true,
}));

// Clear temporary storage through the V2 storage-plan bridge when available
await RunAnywhere.cleanTempFiles();
```

---

## Key Screens Explained

### 1. Chat Screen (`ChatScreen.tsx`)

**What it demonstrates:**
- Streaming text generation with real-time token display
- Conversation management (create, switch, delete)
- Message analytics (tokens/sec, generation time, time to first token)
- Model selection bottom sheet integration
- Model status banner showing loaded model

**Key SDK APIs:**
- `RunAnywhere.generateStream(prompt, LLMGenerationOptions)` — Streaming generation
- `RunAnywhere.loadModel(ModelLoadRequest)` — Load LLM model
- `RunAnywhere.currentModel(CurrentModelRequest)` — Check model status
- `RunAnywhere.listModels()` — List models

### 2. Speech-to-Text Screen (`STTScreen.tsx`)

**What it demonstrates:**
- **Batch mode**: Record full audio, then transcribe
- **Live mode**: Pseudo-streaming with interval-based transcription
- Audio level visualization during recording
- Transcription metrics (confidence percentage)
- Microphone permission handling

**Key SDK APIs:**
- `RunAnywhere.loadModel(ModelLoadRequest)` — Load Whisper model
- `RunAnywhere.currentModel(CurrentModelRequest)` — Check STT model status
- `RunAnywhere.transcribe()` — Transcribe audio bytes/base64
- Native audio recording via `AudioService`

### 3. Text-to-Speech Screen (`TTSScreen.tsx`)

**What it demonstrates:**
- Neural voice synthesis with Piper TTS models
- Speed, pitch, and volume controls
- Audio playback with progress tracking
- System TTS fallback support
- WAV file generation from float32 PCM

**Key SDK APIs:**
- `RunAnywhere.loadModel(ModelLoadRequest)` — Load TTS model
- `RunAnywhere.currentModel(CurrentModelRequest)` — Check TTS model status
- `RunAnywhere.synthesize()` — Generate speech audio
- Native audio playback via `NativeAudioModule` (iOS)

### 4. Voice Assistant Screen (`VoiceAssistantScreen.tsx`)

**What it demonstrates:**
- Complete voice AI pipeline (STT → LLM → TTS)
- Push-to-talk interaction with visual feedback
- Model status tracking for all 3 components
- Pipeline state machine (Idle, Listening, Processing, Thinking, Speaking)
- Conversation history display

**Key SDK APIs:**
- Full integration of STT, LLM, and TTS APIs
- `AudioService.startRecording()` / `stopRecording()`
- Sequential pipeline execution with error handling

### 5. Settings Screen (`SettingsScreen.tsx`)

**What it demonstrates:**
- Generation settings (temperature, max tokens)
- Tool calling toggle and registered demo tools
- SDK version and backend information

**Key SDK APIs:**
- `RunAnywhere.registerTool()` — Register demo tools
- `RunAnywhere.clearTools()` — Clear registered tools

### 6. Storage Screen (`StorageScreen.tsx`)

**What it demonstrates:**
- Downloaded model storage overview
- Cache and temporary file cleanup
- Typed storage delete request flags

**Key SDK APIs:**
- `RunAnywhere.downloadedModels()` — List downloaded models
- `RunAnywhere.deleteStorage(StorageDeleteRequest)` — Remove model files and registry paths
- `RunAnywhere.getStorageInfo()` — Storage metrics
- `RunAnywhere.cleanTempFiles()` — Temporary storage cleanup

---

## Development

### Run Linting

```bash
# ESLint check
npm run lint

# ESLint with auto-fix
npm run lint:fix
```

### Run Type Checking

```bash
npm run typecheck
```

### Run Formatting

```bash
# Check formatting
npm run format

# Auto-fix formatting
npm run format:fix
```

### Check for Unused Code

```bash
npm run unused
```

### Clean Build

```bash
# Full clean (removes node_modules and Pods)
npm run clean

# Just reinstall pods
npm run pod-install
```

---

## Debugging

### Enable Verbose Logging

The app uses `console.warn` with tags for debugging:

```bash
# iOS: View logs in Xcode console or use:
npx react-native log-ios

# Android: View logs with:
npx react-native log-android

# Or filter with adb:
adb logcat -s ReactNative:D
```

### Common Log Tags

| Tag | Description |
|-----|-------------|
| `[App]` | SDK initialization, model registration |
| `[ChatScreen]` | LLM generation, model loading |
| `[STTScreen]` | Speech transcription, audio recording |
| `[TTSScreen]` | Speech synthesis, audio playback |
| `[VoiceAssistant]` | Voice pipeline orchestration |
| `[Settings]` | Storage info, model management |

### Metro Bundler Issues

```bash
# Reset Metro cache
npx react-native start --reset-cache

# Clear watchman
watchman watch-del-all
```

---

## Configuration

### Environment Variables

For production builds, configure via environment variables:

```bash
# Create .env file (git-ignored)
RUNANYWHERE_API_KEY=your-api-key
RUNANYWHERE_BASE_URL=https://api.runanywhere.ai
```

### iOS Specific

- **Minimum iOS**: 15.1
- **Bridgeless Mode**: Disabled (for Nitrogen compatibility)
- **Architectures**: arm64 (device), x86_64/arm64 (simulator)

### Android Specific

- **Minimum SDK**: 24 (Android 7.0)
- **Target SDK**: 36
- **Architectures**: arm64-v8a, armeabi-v7a

---

## Supported Models

### LLM Models (LlamaCpp/GGUF)

| Model | Size | Memory | Description |
|-------|------|--------|-------------|
| SmolLM2 360M Q8_0 | ~400MB | 500MB | Fast, lightweight chat |
| Qwen 2.5 0.5B Q6_K | ~500MB | 600MB | Multilingual, efficient |
| LFM2 350M Q4_K_M | ~200MB | 250MB | LiquidAI, ultra-compact |
| LFM2 350M Q8_0 | ~350MB | 400MB | LiquidAI, higher quality |
| Llama 2 7B Chat Q4_K_M | ~4GB | 4GB | Powerful, larger model |
| Mistral 7B Instruct Q4_K_M | ~4GB | 4GB | High quality responses |

### STT Models (ONNX/Whisper)

| Model | Size | Description |
|-------|------|-------------|
| Sherpa Whisper Tiny (EN) | ~75MB | English transcription |

### TTS Models (ONNX/Piper)

| Model | Size | Description |
|-------|------|-------------|
| Piper US English (Medium) | ~65MB | Natural American voice |
| Piper British English (Medium) | ~65MB | British accent |

---

## Known Limitations

- **ARM64 Preferred** — Native libraries optimized for arm64; x86 emulators may have issues
- **Memory Usage** — Large models (7B+) require devices with 6GB+ RAM
- **First Load** — Initial model loading takes 1-3 seconds
- **iOS Bridgeless** — Disabled for Nitrogen/Nitro module compatibility
- **Live STT** — Uses pseudo-streaming (interval-based) since Whisper is batch-only

---

## Contributing

See [CONTRIBUTING.md](../../../CONTRIBUTING.md) for guidelines.

### Development Setup

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/runanywhere-sdks.git
cd runanywhere-sdks/examples/react-native/RunAnywhereAI

# Install dependencies (yarn pod-install bootstraps Bundler then runs pod install)
npm install
yarn pod-install

# Create feature branch
git checkout -b feature/your-feature

# Make changes and test
npm run lint
npm run typecheck
npm run ios  # or npm run android

# Commit and push
git commit -m "feat: your feature description"
git push origin feature/your-feature

# Open Pull Request
```

---

## License

This project is licensed under the Apache License 2.0 - see [LICENSE](../../../LICENSE) for details.

---

## Support

- **Discord**: [Join our community](https://discord.gg/N359FBbDVd)
- **GitHub Issues**: [Report bugs](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- **Email**: san@runanywhere.ai
- **Twitter**: [@RunanywhereAI](https://twitter.com/RunanywhereAI)

---

## Related Documentation

- [RunAnywhere React Native SDK](../../../sdk/runanywhere-react-native/README.md) — Full SDK documentation
- [iOS Example App](../../ios/RunAnywhereAI/README.md) — iOS native counterpart
- [Android Example App](../../android/RunAnywhereAI/README.md) — Android native counterpart
- [Main README](../../../README.md) — Project overview
