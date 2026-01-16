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

## 🚀 Running This App (Local Development)

> **Important:** This sample app consumes the [RunAnywhere React Native SDK](../../../sdk/runanywhere-react-native/) as local workspace dependencies. Before opening this project, you must first build the SDK's native libraries.

### First-Time Setup

```bash
# 1. Navigate to the React Native SDK directory
cd runanywhere-sdks/sdk/runanywhere-react-native

# 2. Run the setup script (~15-20 minutes on first run)
#    This builds the native C++ frameworks/libraries and enables local mode
./scripts/build-react-native.sh --setup

# 3. Navigate to this sample app
cd ../../examples/react-native/RunAnywhereAI

# 4. Install dependencies
npm install

# 5. For iOS: Install pods
cd ios && pod install && cd ..

# 6a. Run on iOS
npx react-native run-ios

# 6b. Or run on Android
npx react-native run-android

# Or open in VS Code / Cursor and run from there
```

### How It Works

This sample app's `package.json` uses workspace dependencies to reference the local React Native SDK packages:

```
This Sample App → Local RN SDK packages (sdk/runanywhere-react-native/packages/)
                          ↓
              Local XCFrameworks/JNI libs (in each package's ios/ and android/ directories)
                          ↑
           Built by: ./scripts/build-react-native.sh --setup
```

The `build-react-native.sh --setup` script:
1. Downloads dependencies (ONNX Runtime, Sherpa-ONNX)
2. Builds the native C++ libraries from `runanywhere-commons`
3. Copies XCFrameworks to `packages/*/ios/Binaries/` and `packages/*/ios/Frameworks/`
4. Copies JNI `.so` files to `packages/*/android/src/main/jniLibs/`
5. Creates `.testlocal` marker files (enables local library consumption)

### After Modifying the SDK

- **TypeScript SDK code changes**: Metro bundler picks them up automatically (Fast Refresh)
- **C++ code changes** (in `runanywhere-commons`):
  ```bash
  cd sdk/runanywhere-react-native
  ./scripts/build-react-native.sh --local --rebuild-commons
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
| **Speech-to-Text** | Voice transcription with batch & live modes | `RunAnywhere.transcribeFile()` |
| **Text-to-Speech** | Neural voice synthesis with Piper TTS | `RunAnywhere.synthesize()` |
| **Voice Assistant** | Full STT → LLM → TTS pipeline | Voice pipeline orchestration |
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
│   │   ├── STTScreen.tsx             # Speech-to-text with batch/live modes
│   │   ├── TTSScreen.tsx             # Text-to-speech synthesis & playback
│   │   ├── VoiceAssistantScreen.tsx  # Full STT → LLM → TTS pipeline
│   │   └── SettingsScreen.tsx        # Model & storage management
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
│   │   └── TabNavigator.tsx          # Bottom tab navigation (5 tabs)
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

# Install iOS dependencies
cd ios && pod install && cd ..
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
import { RunAnywhere, SDKEnvironment, ModelCategory } from '@runanywhere/core';
import { LlamaCPP } from '@runanywhere/llamacpp';
import { ONNX, ModelArtifactType } from '@runanywhere/onnx';

// Phase 1: Initialize SDK
await RunAnywhere.initialize({
  apiKey: '',  // Empty in development mode
  baseURL: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.Development,
});

// Phase 2: Register backends and models
LlamaCPP.register();
await LlamaCPP.addModel({
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/...',
  memoryRequirement: 500_000_000,
});

ONNX.register();
await ONNX.addModel({
  id: 'sherpa-onnx-whisper-tiny.en',
  name: 'Sherpa Whisper Tiny (ONNX)',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/...',
  modality: ModelCategory.SpeechRecognition,
  artifactType: ModelArtifactType.TarGzArchive,
  memoryRequirement: 75_000_000,
});
```

### Download & Load a Model

```typescript
// Download with progress tracking
await RunAnywhere.downloadModel(modelId, (progress) => {
  console.log(`Download: ${(progress.progress * 100).toFixed(1)}%`);
});

// Load LLM model into memory
const success = await RunAnywhere.loadModel(modelPath);

// Check if model is loaded
const isLoaded = await RunAnywhere.isModelLoaded();
```

### Stream Text Generation

```typescript
// Generate with streaming
const streamResult = await RunAnywhere.generateStream(prompt, {
  maxTokens: 1000,
  temperature: 0.7,
});

let fullResponse = '';
for await (const token of streamResult.stream) {
  fullResponse += token;
  // Update UI in real-time
  updateMessage(fullResponse);
}

// Get final metrics
const result = await streamResult.result;
console.log(`Speed: ${result.tokensPerSecond} tok/s`);
console.log(`Latency: ${result.latencyMs}ms`);
```

### Non-Streaming Generation

```typescript
const result = await RunAnywhere.generate(prompt, {
  maxTokens: 256,
  temperature: 0.7,
});

console.log('Response:', result.text);
console.log('Tokens:', result.tokensUsed);
console.log('Model:', result.modelUsed);
```

### Speech-to-Text

```typescript
// Load STT model
await RunAnywhere.loadSTTModel(modelPath, 'whisper');

// Check if loaded
const isLoaded = await RunAnywhere.isSTTModelLoaded();

// Transcribe audio file
const result = await RunAnywhere.transcribeFile(audioPath, {
  language: 'en',
});

console.log('Transcription:', result.text);
console.log('Confidence:', result.confidence);
```

### Text-to-Speech

```typescript
// Load TTS voice model
await RunAnywhere.loadTTSModel(modelPath, 'piper');

// Synthesize speech
const result = await RunAnywhere.synthesize(text, {
  voice: 'default',
  rate: 1.0,
  pitch: 1.0,
  volume: 1.0,
});

// result.audio contains base64-encoded float32 PCM
// result.sampleRate, result.numSamples, result.duration
```

### Voice Pipeline (STT → LLM → TTS)

```typescript
// 1. Record audio using AudioService
const audioPath = await AudioService.startRecording();

// 2. Stop and get audio
const { uri } = await AudioService.stopRecording();

// 3. Transcribe
const sttResult = await RunAnywhere.transcribeFile(uri, { language: 'en' });

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
// Get available models
const models = await RunAnywhere.getAvailableModels();
const downloaded = await RunAnywhere.getDownloadedModels();

// Get storage info
const storage = await RunAnywhere.getStorageInfo();
console.log('Used:', storage.usedSpace);
console.log('Free:', storage.freeSpace);
console.log('Models:', storage.modelsSize);

// Delete a model
await RunAnywhere.deleteModel(modelId);

// Clear cache
await RunAnywhere.clearCache();
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
- `RunAnywhere.generateStream()` — Streaming generation
- `RunAnywhere.loadModel()` — Load LLM model
- `RunAnywhere.isModelLoaded()` — Check model status
- `RunAnywhere.getAvailableModels()` — List models

### 2. Speech-to-Text Screen (`STTScreen.tsx`)

**What it demonstrates:**
- **Batch mode**: Record full audio, then transcribe
- **Live mode**: Pseudo-streaming with interval-based transcription
- Audio level visualization during recording
- Transcription metrics (confidence percentage)
- Microphone permission handling

**Key SDK APIs:**
- `RunAnywhere.loadSTTModel()` — Load Whisper model
- `RunAnywhere.isSTTModelLoaded()` — Check STT model status
- `RunAnywhere.transcribeFile()` — Transcribe audio file
- Native audio recording via `AudioService`

### 3. Text-to-Speech Screen (`TTSScreen.tsx`)

**What it demonstrates:**
- Neural voice synthesis with Piper TTS models
- Speed, pitch, and volume controls
- Audio playback with progress tracking
- System TTS fallback support
- WAV file generation from float32 PCM

**Key SDK APIs:**
- `RunAnywhere.loadTTSModel()` — Load TTS model
- `RunAnywhere.isTTSModelLoaded()` — Check TTS model status
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
- Model catalog with download/delete functionality
- Download progress tracking
- Storage usage overview (total, models, cache, free)
- Generation settings (temperature, max tokens)
- SDK version and backend information

**Key SDK APIs:**
- `RunAnywhere.getAvailableModels()` — List all models
- `RunAnywhere.getDownloadedModels()` — List downloaded models
- `RunAnywhere.downloadModel()` — Download with progress
- `RunAnywhere.deleteModel()` — Remove model
- `RunAnywhere.getStorageInfo()` — Storage metrics
- `RunAnywhere.clearCache()` — Clear temporary files

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

# Install dependencies
npm install
cd ios && pod install && cd ..

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
