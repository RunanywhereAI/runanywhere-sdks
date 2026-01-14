# RunAnywhere AI - Android Example

<p align="center">
  <img src="../../../examples/logo.svg" alt="RunAnywhere Logo" width="120"/>
</p>

<p align="center">
  <a href="https://play.google.com/store/apps/details?id=com.runanywhere.runanywhereai">
    <img src="https://img.shields.io/badge/Google%20Play-Download-414141?style=for-the-badge&logo=google-play&logoColor=white" alt="Get it on Google Play" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android%207.0%2B-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android 7.0+" />
  <img src="https://img.shields.io/badge/Kotlin-2.1.21-7F52FF?style=flat-square&logo=kotlin&logoColor=white" alt="Kotlin 2.1.21" />
  <img src="https://img.shields.io/badge/Jetpack%20Compose-Modern%20UI-4285F4?style=flat-square&logo=jetpack-compose&logoColor=white" alt="Jetpack Compose" />
  <img src="https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square" alt="License" />
</p>

**A production-ready reference app demonstrating the [RunAnywhere Kotlin SDK](../../../sdk/runanywhere-kotlin/) capabilities for on-device AI.** This app showcases how to build privacy-first, offline-capable AI features with LLM chat, speech-to-text, text-to-speech, and a complete voice assistant pipeline—all running locally on your device.

---

## Try It Now

<p align="center">
  <a href="https://play.google.com/store/apps/details?id=com.runanywhere.runanywhereai">
    <img src="https://upload.wikimedia.org/wikipedia/commons/7/78/Google_Play_Store_badge_EN.svg" alt="Get it on Google Play" height="60"/>
  </a>
</p>

Download the app from Google Play Store to try it out.

---

## Screenshots

<p align="center">
  <img src="../../../docs/screenshots/main-screenshot.jpg" alt="RunAnywhere AI Chat Interface" width="220"/>
</p>

---

## Features

This sample app demonstrates the full power of the RunAnywhere SDK:

| Feature | Description | SDK Integration |
|---------|-------------|-----------------|
| **AI Chat** | Interactive LLM conversations with streaming responses | `RunAnywhere.generateStream()` |
| **Thinking Mode** | Support for models with `<think>...</think>` reasoning | Thinking tag parsing |
| **Real-time Analytics** | Token speed, generation time, inference metrics | `MessageAnalytics` |
| **Speech-to-Text** | Voice transcription with batch & live modes | `RunAnywhere.transcribe()` |
| **Text-to-Speech** | Neural voice synthesis with Piper TTS | `RunAnywhere.synthesize()` |
| **Voice Assistant** | Full STT -> LLM -> TTS pipeline with auto-detection | `RunAnywhere.processVoice()` |
| **Model Management** | Download, load, and manage multiple AI models | `RunAnywhere.downloadModel()` |
| **Storage Management** | View storage usage and delete models | `RunAnywhere.storageInfo()` |
| **Offline Support** | All features work without internet | On-device inference |

---

## Architecture

The app follows modern Android architecture patterns:

```
┌─────────────────────────────────────────────────────────────────┐
│                      Jetpack Compose UI                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │  Chat    │ │   STT    │ │   TTS    │ │  Voice   │ │Settings│ │
│  │  Screen  │ │  Screen  │ │  Screen  │ │  Screen  │ │ Screen │ │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └───┬────┘ │
├───────┼────────────┼────────────┼────────────┼───────────┼──────┤
│       ▼            ▼            ▼            ▼           ▼      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │  Chat    │ │   STT    │ │   TTS    │ │  Voice   │ │Settings│ │
│  │ViewModel │ │ViewModel │ │ViewModel │ │ViewModel │ │ViewModel│
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └───┬────┘ │
├───────┴────────────┴────────────┴────────────┴───────────┴──────┤
│                                                                  │
│                    RunAnywhere Kotlin SDK                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Extension Functions (generate, transcribe, synthesize)   │   │
│  │  EventBus (LLMEvent, STTEvent, TTSEvent, ModelEvent)     │   │
│  │  Model Management (download, load, unload, delete)        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│           ┌──────────────────┴──────────────────┐               │
│           ▼                                      ▼               │
│  ┌─────────────────┐                  ┌─────────────────┐       │
│  │   LlamaCpp      │                  │   ONNX Runtime  │       │
│  │   (LLM/GGUF)    │                  │   (STT/TTS)     │       │
│  └─────────────────┘                  └─────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

### Key Architecture Decisions

- **MVVM Pattern** — ViewModels manage UI state with `StateFlow`, Compose observes changes
- **Single Activity** — Jetpack Navigation Compose handles all screen transitions
- **Coroutines & Flow** — All async operations use Kotlin coroutines with structured concurrency
- **EventBus Pattern** — SDK events (model loading, generation, etc.) propagate via `EventBus.events`
- **Repository Abstraction** — `ConversationStore` persists chat history

---

## Project Structure

```
RunAnywhereAI/
├── app/
│   ├── src/main/
│   │   ├── java/com/runanywhere/runanywhereai/
│   │   │   ├── RunAnywhereApplication.kt      # SDK initialization, model registration
│   │   │   ├── MainActivity.kt                # Entry point, initialization state handling
│   │   │   │
│   │   │   ├── data/
│   │   │   │   └── ConversationStore.kt       # Chat history persistence
│   │   │   │
│   │   │   ├── domain/
│   │   │   │   ├── models/
│   │   │   │   │   ├── ChatMessage.kt         # Message data model with analytics
│   │   │   │   │   └── SessionState.kt        # Voice session states
│   │   │   │   └── services/
│   │   │   │       └── AudioCaptureService.kt # Microphone audio capture
│   │   │   │
│   │   │   ├── presentation/
│   │   │   │   ├── chat/
│   │   │   │   │   ├── ChatScreen.kt          # LLM chat UI with streaming
│   │   │   │   │   ├── ChatViewModel.kt       # Chat logic, thinking mode
│   │   │   │   │   └── components/
│   │   │   │   │       └── MessageInput.kt    # Chat input component
│   │   │   │   │
│   │   │   │   ├── stt/
│   │   │   │   │   ├── SpeechToTextScreen.kt  # STT UI with waveform
│   │   │   │   │   └── SpeechToTextViewModel.kt # Batch & live transcription
│   │   │   │   │
│   │   │   │   ├── tts/
│   │   │   │   │   ├── TextToSpeechScreen.kt  # TTS UI with playback
│   │   │   │   │   └── TextToSpeechViewModel.kt # Synthesis & audio playback
│   │   │   │   │
│   │   │   │   ├── voice/
│   │   │   │   │   ├── VoiceAssistantScreen.kt # Full voice pipeline UI
│   │   │   │   │   └── VoiceAssistantViewModel.kt # STT→LLM→TTS orchestration
│   │   │   │   │
│   │   │   │   ├── settings/
│   │   │   │   │   ├── SettingsScreen.kt      # Storage & model management
│   │   │   │   │   └── SettingsViewModel.kt   # Storage info, cache clearing
│   │   │   │   │
│   │   │   │   ├── models/
│   │   │   │   │   ├── ModelSelectionBottomSheet.kt # Model picker UI
│   │   │   │   │   └── ModelSelectionViewModel.kt   # Download & load logic
│   │   │   │   │
│   │   │   │   ├── navigation/
│   │   │   │   │   └── AppNavigation.kt       # Bottom nav, routing
│   │   │   │   │
│   │   │   │   └── common/
│   │   │   │       └── InitializationViews.kt # Loading/error states
│   │   │   │
│   │   │   └── ui/theme/
│   │   │       ├── Theme.kt                   # Material 3 theming
│   │   │       ├── AppColors.kt               # Color palette
│   │   │       ├── Type.kt                    # Typography
│   │   │       └── Dimensions.kt              # Spacing constants
│   │   │
│   │   ├── res/                               # Resources (icons, strings)
│   │   └── AndroidManifest.xml                # Permissions, app config
│   │
│   ├── src/test/                              # Unit tests
│   └── src/androidTest/                       # Instrumentation tests
│
├── build.gradle.kts                           # Project build config
├── settings.gradle.kts                        # Module settings
└── README.md                                  # This file
```

---

## Quick Start

### Prerequisites

- **Android Studio** Hedgehog (2023.1.1) or later
- **Android SDK** 24+ (Android 7.0 Nougat)
- **JDK** 17+
- **Device/Emulator** with arm64-v8a architecture (recommended: physical device)
- **~2GB** free storage for AI models

### Clone & Build

```bash
# Clone the repository
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/examples/android/RunAnywhereAI

# Build debug APK
./gradlew assembleDebug

# Install on connected device
./gradlew installDebug
```

### Run via Android Studio

1. Open the project in Android Studio
2. Wait for Gradle sync to complete
3. Select a physical device (arm64 recommended) or emulator
4. Click **Run** or press `Shift + F10`

### Run via Command Line

```bash
# Install and launch
./gradlew installDebug
adb shell am start -n com.runanywhere.runanywhereai.debug/.MainActivity
```

---

## SDK Integration Examples

### Initialize the SDK

The SDK is initialized in `RunAnywhereApplication.kt`:

```kotlin
// Initialize SDK with development environment
RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)

// Complete services initialization (device registration)
RunAnywhere.completeServicesInitialization()

// Register AI backends
LlamaCPP.register(priority = 100)  // LLM backend (GGUF models)
ONNX.register(priority = 100)      // STT/TTS backend

// Register models
RunAnywhere.registerModel(
    id = "smollm2-360m-q8_0",
    name = "SmolLM2 360M Q8_0",
    url = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/...",
    framework = InferenceFramework.LLAMA_CPP,
    memoryRequirement = 500_000_000,
)
```

### Download & Load a Model

```kotlin
// Download with progress tracking
RunAnywhere.downloadModel("smollm2-360m-q8_0").collect { progress ->
    println("Download: ${(progress.progress * 100).toInt()}%")
}

// Load into memory
RunAnywhere.loadLLMModel("smollm2-360m-q8_0")
```

### Stream Text Generation

```kotlin
// Generate with streaming
RunAnywhere.generateStream(prompt).collect { token ->
    // Display token in real-time
    displayToken(token)
}

// Or non-streaming
val result = RunAnywhere.generate(prompt)
println("Response: ${result.text}")
```

### Speech-to-Text

```kotlin
// Load STT model
RunAnywhere.loadSTTModel("sherpa-onnx-whisper-tiny.en")

// Transcribe audio bytes
val transcription = RunAnywhere.transcribe(audioBytes)
println("Transcription: $transcription")
```

### Text-to-Speech

```kotlin
// Load TTS voice
RunAnywhere.loadTTSVoice("vits-piper-en_US-lessac-medium")

// Synthesize speech
val result = RunAnywhere.synthesize(text, TTSOptions(
    rate = 1.0f,
    pitch = 1.0f,
))
// result.audioData contains WAV audio bytes
```

### Voice Pipeline (STT → LLM → TTS)

```kotlin
// Process voice through full pipeline
val result = RunAnywhere.processVoice(audioData)

if (result.speechDetected) {
    println("User said: ${result.transcription}")
    println("AI response: ${result.response}")
    // result.synthesizedAudio contains TTS audio
}
```

---

## Key Screens Explained

### 1. Chat Screen (`ChatScreen.kt`)

**What it demonstrates:**
- Streaming text generation with real-time token display
- Thinking mode support (`<think>...</think>` tags)
- Message analytics (tokens/sec, time to first token)
- Conversation history management
- Model selection bottom sheet integration

**Key SDK APIs:**
- `RunAnywhere.generateStream()` — Streaming generation
- `RunAnywhere.generate()` — Non-streaming generation
- `RunAnywhere.cancelGeneration()` — Stop generation
- `EventBus.events.filterIsInstance<LLMEvent>()` — Listen for LLM events

### 2. Speech-to-Text Screen (`SpeechToTextScreen.kt`)

**What it demonstrates:**
- Batch mode: Record full audio, then transcribe
- Live mode: Real-time streaming transcription
- Audio level visualization
- Transcription metrics (confidence, RTF, word count)

**Key SDK APIs:**
- `RunAnywhere.loadSTTModel()` — Load Whisper model
- `RunAnywhere.transcribe()` — Batch transcription
- `RunAnywhere.transcribeStream()` — Streaming transcription

### 3. Text-to-Speech Screen (`TextToSpeechScreen.kt`)

**What it demonstrates:**
- Neural voice synthesis with Piper TTS
- Speed and pitch controls
- Audio playback with progress
- Fun sample texts for testing

**Key SDK APIs:**
- `RunAnywhere.loadTTSVoice()` — Load TTS model
- `RunAnywhere.synthesize()` — Generate speech audio
- `RunAnywhere.stopSynthesis()` — Cancel synthesis

### 4. Voice Assistant Screen (`VoiceAssistantScreen.kt`)

**What it demonstrates:**
- Complete voice AI pipeline
- Automatic speech detection with silence timeout
- Continuous conversation mode
- Model status tracking for all 3 components (STT, LLM, TTS)

**Key SDK APIs:**
- `RunAnywhere.startVoiceSession()` — Start voice session
- `RunAnywhere.processVoice()` — Process audio through pipeline
- `RunAnywhere.voiceAgentComponentStates()` — Check component status

### 5. Settings Screen (`SettingsScreen.kt`)

**What it demonstrates:**
- Storage usage overview
- Downloaded model management
- Model deletion with confirmation
- Cache clearing

**Key SDK APIs:**
- `RunAnywhere.storageInfo()` — Get storage details
- `RunAnywhere.deleteModel()` — Remove downloaded model
- `RunAnywhere.clearCache()` — Clear temporary files

---

## Testing

### Run Unit Tests

```bash
./gradlew test
```

### Run Instrumentation Tests

```bash
./gradlew connectedAndroidTest
```

### Run Lint & Static Analysis

```bash
# Detekt static analysis
./gradlew detekt

# ktlint formatting check
./gradlew ktlintCheck

# Android lint
./gradlew lint
```

---

## Debugging

### Enable Verbose Logging

Filter logcat for RunAnywhere SDK logs:

```bash
adb logcat -s "RunAnywhere:D" "RunAnywhereApp:D" "ChatViewModel:D"
```

### Common Log Tags

| Tag | Description |
|-----|-------------|
| `RunAnywhereApp` | SDK initialization, model registration |
| `ChatViewModel` | LLM generation, streaming |
| `STTViewModel` | Speech transcription |
| `TTSViewModel` | Speech synthesis |
| `VoiceAssistantVM` | Voice pipeline |
| `ModelSelectionVM` | Model downloads, loading |

### Memory Profiling

1. Open Android Studio Profiler
2. Select your app process
3. Record memory allocations during model loading
4. Expected: ~300MB-2GB depending on model size

---

## Configuration

### Build Variants

| Variant | Description |
|---------|-------------|
| `debug` | Development build with debugging enabled |
| `release` | Optimized build with R8/ProGuard |
| `benchmark` | Release-like build for performance testing |

### Environment Variables (for release builds)

```bash
export KEYSTORE_PATH=/path/to/keystore.jks
export KEYSTORE_PASSWORD=your_password
export KEY_ALIAS=your_alias
export KEY_PASSWORD=your_key_password
```

---

## Supported Models

### LLM Models (LlamaCpp/GGUF)

| Model | Size | Memory | Description |
|-------|------|--------|-------------|
| SmolLM2 360M Q8_0 | ~400MB | 500MB | Fast, lightweight chat |
| Qwen 2.5 0.5B Q6_K | ~500MB | 600MB | Multilingual, efficient |
| LFM2 350M Q4_K_M | ~200MB | 250MB | LiquidAI, ultra-compact |
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

- **ARM64 Only** — Native libraries built for `arm64-v8a` only (x86 emulators not supported)
- **Memory Usage** — Large models (7B+) require devices with 6GB+ RAM
- **First Load** — Initial model loading takes 1-3 seconds (cached afterward)
- **Thermal Throttling** — Extended inference may trigger device throttling on some devices

---

## Contributing

See [CONTRIBUTING.md](../../../CONTRIBUTING.md) for guidelines.

### Development Setup

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/runanywhere-sdks.git
cd runanywhere-sdks/examples/android/RunAnywhereAI

# Create feature branch
git checkout -b feature/your-feature

# Make changes and test
./gradlew assembleDebug
./gradlew test
./gradlew detekt ktlintCheck

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

- [RunAnywhere Kotlin SDK](../../../sdk/runanywhere-kotlin/README.md) — Full SDK documentation
- [iOS Example App](../../ios/RunAnywhereAI/README.md) — iOS counterpart
- [React Native Example](../../react-native/RunAnywhereAI/README.md) — Cross-platform option
- [Main README](../../../README.md) — Project overview
