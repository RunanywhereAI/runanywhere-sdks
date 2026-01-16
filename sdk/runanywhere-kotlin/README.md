# RunAnywhere Kotlin SDK

**Privacy-first, on-device AI for Android & JVM**. Run LLMs, speech-to-text, text-to-speech, and voice agents locally with cloud fallback, OTA updates, and production observability.

[![Maven Central](https://img.shields.io/maven-central/v/com.runanywhere.sdk/runanywhere-kotlin?label=Maven%20Central)](https://search.maven.org/artifact/com.runanywhere.sdk/runanywhere-kotlin)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Platform: Android 7.0+](https://img.shields.io/badge/Platform-Android%207.0%2B-green)](https://developer.android.com)
[![Kotlin](https://img.shields.io/badge/Kotlin-2.0%2B-blue?logo=kotlin)](https://kotlinlang.org)
[![KMP](https://img.shields.io/badge/Kotlin%20Multiplatform-Supported-purple)](https://kotlinlang.org/docs/multiplatform.html)

---

## Key Features

- **Works Offline & Instantly** – Models run locally on-device; zero network latency for inference.
- **Hybrid by Design** – Automatic fallback to cloud based on device memory, thermal status, or your custom policies.
- **Privacy First** – User data stays on-device. HIPAA/GDPR friendly.
- **One API, All Platforms** – Single SDK API across iOS, Android, React Native, Flutter.
- **OTA Model Updates** – Deploy new models without app releases via the RunAnywhere console.
- **Production Observability** – Built-in analytics: latency, token throughput, device state, and more.
- **Complete Voice AI Stack** – LLM, STT, TTS, and VAD unified under one SDK.

---

## Quick Start

### 1. Add Dependencies

**build.gradle.kts (Module: app)**

```kotlin
dependencies {
    // Core SDK
    implementation("com.runanywhere.sdk:runanywhere-kotlin:0.1.4")

    // Optional: LLM support (llama.cpp backend) - ~34MB
    implementation("com.runanywhere.sdk:runanywhere-core-llamacpp:0.1.4")

    // Optional: STT/TTS/VAD support (ONNX backend) - ~25MB
    implementation("com.runanywhere.sdk:runanywhere-core-onnx:0.1.4")
}
```

### 2. Initialize SDK (Application.onCreate)

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.SDKEnvironment

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        // Initialize RunAnywhere (fast, ~1-5ms)
        RunAnywhere.initialize(
            apiKey = "your-api-key",    // Optional for development
            environment = SDKEnvironment.DEVELOPMENT
        )
    }
}
```

### 3. Register & Download a Model

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.*
import com.runanywhere.sdk.core.types.InferenceFramework

// Register a model from HuggingFace
val modelInfo = RunAnywhere.registerModel(
    name = "Qwen 0.5B",
    url = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q8_0.gguf",
    framework = InferenceFramework.LLAMA_CPP
)

// Download the model (observe progress)
RunAnywhere.downloadModel(modelInfo.id)
    .collect { progress ->
        println("Download: ${(progress.progress * 100).toInt()}%")
    }
```

### 4. Run Inference

```kotlin
// Load the model
RunAnywhere.loadLLMModel(modelInfo.id)

// Simple chat
val response = RunAnywhere.chat("What is machine learning?")
println(response)

// Or with full metrics
val result = RunAnywhere.generate(
    prompt = "Explain quantum computing",
    options = LLMGenerationOptions(
        maxTokens = 150,
        temperature = 0.7f
    )
)
println("Response: ${result.text}")
println("Tokens/sec: ${result.tokensPerSecond}")
println("Latency: ${result.latencyMs}ms")
```

### 5. Streaming Generation

```kotlin
// Stream tokens as they're generated
RunAnywhere.generateStream("Tell me a story about AI")
    .collect { token ->
        print(token) // Display in real-time
    }

// With metrics
val streamResult = RunAnywhere.generateStreamWithMetrics("Write a poem")
streamResult.stream.collect { token -> print(token) }
val metrics = streamResult.result.await()
println("\nSpeed: ${metrics.tokensPerSecond} tok/s")
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Your Android App                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │            RunAnywhere Kotlin SDK (Public API)             │  │
│  │                                                            │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │  │
│  │  │   LLM    │  │   STT    │  │   TTS    │  │   VAD    │  │  │
│  │  │ generate │  │transcribe│  │synthesize│  │  detect  │  │  │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │  │
│  │                                                            │  │
│  │  ┌──────────────────────────────────────────────────────┐ │  │
│  │  │              VoiceAgent (Orchestration)              │ │  │
│  │  │         VAD → STT → LLM → TTS Pipeline               │ │  │
│  │  └──────────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              ↓                                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │         runanywhere-commons (C++ Native Layer)            │  │
│  │    JNI bridge to shared AI inference infrastructure       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              ↓                                    │
│  ┌─────────────────────┐    ┌─────────────────────────────────┐ │
│  │  runanywhere-core-  │    │   runanywhere-core-onnx        │ │
│  │     llamacpp        │    │                                 │ │
│  │  ┌───────────────┐  │    │ ┌───────────┐  ┌─────────────┐ │ │
│  │  │  llama.cpp    │  │    │ │ONNX Runtime│  │Sherpa-ONNX  │ │ │
│  │  │ LLM Inference │  │    │ └───────────┘  │(STT/TTS/VAD)│ │ │
│  │  └───────────────┘  │    │                └─────────────┘ │ │
│  └─────────────────────┘    └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

**Key Components:**
- **Public API** - Kotlin extension functions for LLM, STT, TTS, VAD, VoiceAgent
- **runanywhere-commons** - Shared C++ infrastructure (JNI bridging)
- **runanywhere-core-llamacpp** - llama.cpp backend for LLM inference (~34MB)
- **runanywhere-core-onnx** - ONNX Runtime + Sherpa-ONNX for STT/TTS/VAD (~25MB)

---

## Features

### Text Generation (LLM)

```kotlin
// Simple chat
val answer = RunAnywhere.chat("What is 2+2?")

// Generation with options
val result = RunAnywhere.generate(
    prompt = "Write a haiku about code",
    options = LLMGenerationOptions(
        maxTokens = 50,
        temperature = 0.9f,
        systemPrompt = "You are a creative poet"
    )
)

// Streaming
RunAnywhere.generateStream("Tell me a joke")
    .collect { token -> print(token) }

// Cancel ongoing generation
RunAnywhere.cancelGeneration()
```

### Speech-to-Text (STT)

```kotlin
// Load an STT model
RunAnywhere.loadSTTModel("whisper-tiny")

// Transcribe audio
val text = RunAnywhere.transcribe(audioData)

// With options
val output = RunAnywhere.transcribeWithOptions(
    audioData = audioBytes,
    options = STTOptions(
        language = "en",
        enableTimestamps = true,
        enablePunctuation = true
    )
)
println("Text: ${output.text}")
println("Confidence: ${output.confidence}")

// Streaming transcription
RunAnywhere.transcribeStream(audioData) { partial ->
    println("Partial: ${partial.transcript}")
}
```

### Text-to-Speech (TTS)

```kotlin
// Load a TTS voice
RunAnywhere.loadTTSVoice("en-us-default")

// Simple speak (plays audio automatically)
RunAnywhere.speak("Hello, world!")

// Synthesize to bytes
val output = RunAnywhere.synthesize(
    text = "Welcome to RunAnywhere",
    options = TTSOptions(
        rate = 1.0f,
        pitch = 1.0f
    )
)

// Stream synthesis for long text
RunAnywhere.synthesizeStream(longText) { chunk ->
    audioPlayer.play(chunk)
}
```

### Voice Activity Detection (VAD)

```kotlin
// Detect speech in audio
val result = RunAnywhere.detectVoiceActivity(audioData)
println("Speech detected: ${result.hasSpeech}")
println("Confidence: ${result.confidence}")

// Configure VAD
RunAnywhere.configureVAD(VADConfiguration(
    threshold = 0.5f,
    minSpeechDurationMs = 250,
    minSilenceDurationMs = 300
))

// Stream VAD
RunAnywhere.streamVAD(audioSamplesFlow)
    .collect { result ->
        if (result.hasSpeech) println("Speaking...")
    }
```

### Voice Agent (Full Pipeline)

```kotlin
// Configure voice agent
RunAnywhere.configureVoiceAgent(VoiceAgentConfiguration(
    sttModelId = "whisper-tiny",
    llmModelId = "qwen-0.5b",
    ttsVoiceId = "en-us-default"
))

// Start voice session
RunAnywhere.startVoiceSession()
    .collect { event ->
        when (event) {
            is VoiceSessionEvent.Listening -> println("Listening...")
            is VoiceSessionEvent.Transcribed -> println("You: ${event.text}")
            is VoiceSessionEvent.Thinking -> println("Thinking...")
            is VoiceSessionEvent.Responded -> println("AI: ${event.text}")
            is VoiceSessionEvent.Speaking -> println("Speaking...")
            is VoiceSessionEvent.Error -> println("Error: ${event.message}")
        }
    }

// Stop session
RunAnywhere.stopVoiceSession()
```

### Model Management

```kotlin
// List available models
val models = RunAnywhere.availableModels()

// Filter by category
val llmModels = RunAnywhere.models(ModelCategory.LANGUAGE)
val sttModels = RunAnywhere.models(ModelCategory.SPEECH_RECOGNITION)
val ttsModels = RunAnywhere.models(ModelCategory.SPEECH_SYNTHESIS)

// Check download status
val isDownloaded = RunAnywhere.isModelDownloaded(modelId)

// Delete model
RunAnywhere.deleteModel(modelId)

// Refresh model registry
RunAnywhere.refreshModelRegistry()
```

### Event System

```kotlin
// Subscribe to LLM events
RunAnywhere.events.llmEvents.collect { event ->
    when (event) {
        is LLMEvent -> {
            println("LLM Event: ${event.type}")
            println("Latency: ${event.latencyMs}ms")
        }
    }
}

// Subscribe to model events
RunAnywhere.events.modelEvents.collect { event ->
    when (event) {
        is ModelEvent -> {
            println("Model ${event.modelId}: ${event.eventType}")
        }
    }
}
```

---

## Supported Model Formats

| Format | Extension | Backend | Use Case |
|--------|-----------|---------|----------|
| GGUF | `.gguf` | llama.cpp | LLM text generation |
| ONNX | `.onnx` | ONNX Runtime | STT, TTS, VAD |
| ORT | `.ort` | ONNX Runtime | Optimized STT/TTS |

---

## Requirements

- **Android**: API 24+ (Android 7.0+)
- **JVM**: Java 17+
- **Kotlin**: 2.0+

---

## Troubleshooting

### Q: Model loads but inference is slow. How do I debug?

**A:** Check the generation result metrics:
```kotlin
val result = RunAnywhere.generate(prompt = "...")
println("Latency: ${result.latencyMs}ms")
println("Tokens/sec: ${result.tokensPerSecond}")
println("Model: ${result.modelUsed}")
```

If latency is high:
- Try a smaller quantized model (q4_0 vs q8_0)
- Check device thermal state
- Ensure sufficient RAM (model size × 1.5)

### Q: App crashes when loading large models

**A:** Check available memory before loading:
```kotlin
// Register smaller quantized model variant
val smallModel = RunAnywhere.registerModel(
    name = "Qwen 0.5B Q4",
    url = "...qwen2.5-0.5b-instruct-q4_0.gguf",
    framework = InferenceFramework.LLAMA_CPP
)
```

### Q: Models don't download. What's wrong?

**A:** Ensure you have:
1. Internet permission in AndroidManifest.xml:
   ```xml
   <uses-permission android:name="android.permission.INTERNET" />
   ```
2. SDK initialized before download calls
3. Valid download URL (test in browser first)

### Q: How do I know which model is loaded?

**A:**
```kotlin
val llmModelId = RunAnywhere.currentLLMModelId
val sttModelId = RunAnywhere.currentSTTModelId
val ttsVoiceId = RunAnywhere.currentTTSVoiceId

println("LLM: ${llmModelId ?: "None"}")
println("STT: ${sttModelId ?: "None"}")
println("TTS: ${ttsVoiceId ?: "None"}")
```

---

## Sample Code

See the [examples/android/RunAnywhereAI](../../examples/android/RunAnywhereAI) directory for a complete sample app demonstrating:
- LLM chat with streaming
- Voice transcription
- Text-to-speech
- Full voice agent pipeline
- Model management UI

---

## Local Development & Contributing

This section explains how to set up your development environment to build the SDK from source and test your changes with the sample app.

### Prerequisites

- **Android Studio** (latest stable)
- **Android NDK** (v27+ recommended, installed via Android Studio SDK Manager)
- **CMake** (installed via Android Studio SDK Manager)
- **Bash** (macOS/Linux terminal)

### First-Time Setup (Build from Source)

The SDK depends on native C++ libraries from `runanywhere-commons`. The setup script builds these locally so you can develop and test the SDK end-to-end.

```bash
# 1. Clone the repository
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/sdk/runanywhere-kotlin

# 2. Run first-time setup (~10-15 minutes)
./scripts/build-kotlin.sh --setup
```

**What the setup script does:**
1. Downloads dependencies (Sherpa-ONNX, ~500MB)
2. Builds `runanywhere-commons` for Android (arm64-v8a by default)
3. Copies JNI libraries (`.so` files) to module `jniLibs/` directories
4. Sets `runanywhere.testLocal=true` in `gradle.properties`

### Understanding testLocal

The SDK has two modes controlled by `runanywhere.testLocal` in `gradle.properties`:

| Mode | Setting | Description |
|------|---------|-------------|
| **Local** | `runanywhere.testLocal=true` | Uses JNI libs from `src/androidMain/jniLibs/` (for development) |
| **Remote** | `runanywhere.testLocal=false` | Downloads JNI libs from GitHub releases (for end users) |

When you run `--setup`, the script automatically sets `testLocal=true`.

### Testing with the Android Sample App

The recommended way to test SDK changes is with the sample app:

```bash
# 1. Ensure SDK is set up (from previous step)

# 2. Open Android Studio
# 3. Select Open → Navigate to examples/android/RunAnywhereAI
# 4. Wait for Gradle sync to complete
# 5. Connect an Android device (ARM64 recommended) or emulator
# 6. Click Run
```

The sample app's `settings.gradle.kts` references the local SDK via `includeBuild()`, which in turn uses the local JNI libraries. This creates a complete local development loop:

```
Sample App → Local Kotlin SDK → Local JNI Libraries (jniLibs/)
                                       ↑
                          Built by build-kotlin.sh --setup
```

### Development Workflow

**After modifying Kotlin SDK code:**
- Rebuild in Android Studio or run `./gradlew assembleDebug`

**After modifying runanywhere-commons (C++ code):**

```bash
cd sdk/runanywhere-kotlin
./scripts/build-kotlin.sh --local --rebuild-commons
```

### Build Script Reference

| Command | Description |
|---------|-------------|
| `--setup` | First-time setup: downloads deps, builds all libs, sets `testLocal=true` |
| `--local` | Use locally built libs from `jniLibs/` |
| `--remote` | Use remote libs from GitHub releases |
| `--rebuild-commons` | Force rebuild of runanywhere-commons |
| `--clean` | Clean build directories before building |
| `--abis=ABIS` | ABIs to build (default: `arm64-v8a`, use `arm64-v8a,armeabi-v7a` for 97% device coverage) |
| `--skip-build` | Skip Gradle build (only setup native libs) |

### Project Structure

```
sdk/runanywhere-kotlin/
├── src/
│   ├── commonMain/          # Cross-platform Kotlin code
│   ├── jvmAndroidMain/      # Shared JVM/Android (JNI bridges)
│   ├── androidMain/         # Android-specific (jniLibs, platform code)
│   └── jvmMain/             # Desktop JVM support
├── modules/
│   ├── runanywhere-core-llamacpp/   # LLM backend module
│   └── runanywhere-core-onnx/       # STT/TTS/VAD backend module
├── scripts/
│   └── build-kotlin.sh      # Build automation script
└── gradle.properties        # testLocal flag controls local vs remote libs
```

### Code Quality

Run linting before submitting PRs:

```bash
# Run detekt (static analysis)
./gradlew detekt

# Run ktlint (code formatting)
./gradlew ktlintCheck

# Auto-fix formatting issues
./gradlew ktlintFormat
```

### Testing the SDK

1. **Unit Tests:** `./gradlew jvmTest`
2. **Android Tests:** Open sample app in Android Studio → Run instrumented tests
3. **Manual Testing:** Use the sample app to test all SDK features on a real device

### Submitting Changes

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run linting: `./gradlew detekt ktlintCheck`
5. Test with the sample app
6. Commit: `git commit -m 'Add my feature'`
7. Push: `git push origin feature/my-feature`
8. Open a Pull Request

---

## License

Apache 2.0. See [LICENSE](../../LICENSE).

---

## Links

- [Architecture Documentation](./ARCHITECTURE.md)
- [API Documentation](./Documentation.md)
- [Sample App](../../examples/android/RunAnywhereAI)
