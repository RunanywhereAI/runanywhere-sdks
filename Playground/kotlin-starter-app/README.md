# RunAnywhere Kotlin SDK Starter

A comprehensive Android starter app demonstrating the **RunAnywhere SDK** capabilities - privacy-first, on-device AI for Android with Kotlin and Jetpack Compose.

## Features

This starter app showcases all major capabilities of the RunAnywhere SDK:

### 🧠 Chat (LLM Text Generation)
- On-device text generation using **SmolLM2 360M**
- Real-time chat interface with message history
- Powered by llama.cpp backend

### 🎤 Speech to Text (STT)
- Real-time speech recognition using **Whisper Tiny**
- Microphone permission handling
- Voice activity detection
- Powered by Sherpa-ONNX backend

### 🔊 Text to Speech (TTS)
- Natural voice synthesis using **Piper TTS**
- Sample texts and custom input
- High-quality US English voice (Lessac)
- Powered by Sherpa-ONNX backend

### 🎯 Voice Pipeline (Voice Agent)
- Complete voice conversation pipeline
- Combines STT → LLM → TTS
- Real-time conversation flow
- Status indicators for each stage

## Getting Started

### Prerequisites

- **Android Studio**: Hedgehog (2023.1.1) or later
- **Minimum SDK**: API 26 (Android 8.0)
- **Target SDK**: API 35 (Android 15)
- **Kotlin**: 2.2.0 or later
- **Java**: 17

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd Playground/kotlin-starter-app
   ```

2. **Open in Android Studio**
   - Open Android Studio
   - Select "Open an Existing Project"
   - Navigate to the `kotlin-starter-app` folder
   - Click "OK"

3. **Sync Gradle**
   - Android Studio will automatically sync Gradle
   - If not, click "Sync Now" in the notification bar

4. **Run the app**
   - Connect an Android device or start an emulator
   - Click the "Run" button (▶️) in Android Studio
   - Select your device/emulator
   - The app will build and install

### First Launch

On the first launch:

1. **Home Screen**: You'll see 4 feature cards
2. **Load Models**: Each feature requires downloading AI models:
   - **LLM**: ~400 MB (SmolLM2 360M)
   - **STT**: ~75 MB (Whisper Tiny)
   - **TTS**: ~20 MB (Piper TTS)
3. **Grant Permissions**: STT and Voice Pipeline require microphone permission
4. **Start Using**: Once models are loaded, all features are ready!

## Architecture

### Project Structure

```text
app/src/main/java/com/runanywhere/kotlin_starter_example/
├── MainActivity.kt                    # App entry point
├── services/
│   └── ModelService.kt               # Model management (download, load, unload)
└── ui/
    ├── theme/                        # App theme and colors
    │   ├── Theme.kt
    │   └── Type.kt
    ├── components/                   # Reusable UI components
    │   ├── FeatureCard.kt
    │   └── ModelLoaderWidget.kt
    └── screens/                      # Feature screens
        ├── HomeScreen.kt
        ├── ChatScreen.kt
        ├── SpeechToTextScreen.kt
        ├── TextToSpeechScreen.kt
        └── VoicePipelineScreen.kt
```

### Key Technologies

- **Jetpack Compose**: Modern declarative UI
- **Material 3**: Latest Material Design
- **Navigation Compose**: Screen navigation
- **Coroutines & Flow**: Asynchronous operations
- **ViewModel**: State management
- **RunAnywhere SDK**: On-device AI (`io.github.sanchitmonga22`)

## RunAnywhere SDK Integration

### Dependencies

The app uses three RunAnywhere packages:

```kotlin
// build.gradle.kts (app module)
val sdkVersion = "0.1.5-SNAPSHOT"
dependencies {
    // Core SDK
    implementation("io.github.sanchitmonga22:runanywhere-sdk-android:$sdkVersion")

    // Backends
    implementation("io.github.sanchitmonga22:runanywhere-llamacpp-android:$sdkVersion")  // LLM
    implementation("io.github.sanchitmonga22:runanywhere-onnx-android:$sdkVersion")      // STT/TTS
}
```

### Initialization

```kotlin
// MainActivity.kt
RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)
ModelService.registerDefaultModels()
```

### Model Registration

Models are registered in `ModelService.kt`:

```kotlin
// LLM Model
RunAnywhere.registerModel(
    id = "smollm2-360m-instruct-q8_0",
    name = "SmolLM2 360M Instruct Q8_0",
    url = "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf",
    framework = InferenceFramework.LLAMA_CPP,
    memoryRequirement = 400_000_000
)

// STT Model
RunAnywhere.registerModel(
    id = "sherpa-onnx-whisper-tiny.en",
    name = "Sherpa Whisper Tiny (ONNX)",
    url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
    framework = InferenceFramework.ONNX,
    category = ModelCategory.SPEECH_RECOGNITION
)

// TTS Model
RunAnywhere.registerModel(
    id = "vits-piper-en_US-lessac-medium",
    name = "Piper TTS (US English - Medium)",
    url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
    framework = InferenceFramework.ONNX,
    category = ModelCategory.SPEECH_SYNTHESIS
)
```

### Usage Examples

#### Chat (LLM)
```kotlin
val response = RunAnywhere.chat("Explain AI in simple terms")
```

#### Speech to Text (STT)
```kotlin
val audioData: ByteArray = recordAudio()
val transcription = RunAnywhere.transcribe(audioData)
```

#### Text to Speech (TTS)
```kotlin
RunAnywhere.speak("Hello, world!")
```

#### Voice Pipeline
```kotlin
val audioFlow: Flow<ByteArray> = captureAudio() // Your audio capture flow
val config = VoiceSessionConfig(silenceDuration = 1.5, continuousMode = true)

RunAnywhere.streamVoiceSession(audioFlow, config).collect { event ->
    when (event) {
        is VoiceSessionEvent.Listening -> updateUI("Listening...")
        is VoiceSessionEvent.Transcribed -> updateUI("You: ${event.text}")
        is VoiceSessionEvent.Processing -> updateUI("Processing...")
        is VoiceSessionEvent.Responded -> updateUI("AI: ${event.text}")
        is VoiceSessionEvent.Speaking -> updateUI("Speaking...")
    }
}
```

## Performance

### Model Sizes
- **LLM (SmolLM2 360M)**: ~400 MB
- **STT (Whisper Tiny)**: ~75 MB
- **TTS (Piper)**: ~20 MB
- **Total**: ~495 MB

### Inference Speed
- **LLM**: 5-15 tokens/sec (device dependent)
- **STT**: Real-time transcription
- **TTS**: Real-time synthesis

### Device Requirements
- **RAM**: Minimum 2GB recommended
- **Storage**: 1GB free space for models
- **CPU**: ARMv8 64-bit recommended (supports ARMv7)

## Customization

### Changing Models

To use different models, update `ModelService.kt`:

```kotlin
companion object {
    const val LLM_MODEL_ID = "your-model-id"
    const val STT_MODEL_ID = "your-stt-model-id"
    const val TTS_MODEL_ID = "your-tts-model-id"
    
    fun registerDefaultModels() {
        RunAnywhere.registerModel(
            id = LLM_MODEL_ID,
            name = "Your Model Name",
            url = "your-model-url",
            framework = InferenceFramework.LLAMA_CPP
        )
        // ... register other models
    }
}
```

### Customizing UI

All UI colors and themes are defined in:
- `ui/theme/Theme.kt` - Color palette
- `ui/theme/Type.kt` - Typography

## Troubleshooting

### Models Not Downloading
- Check internet connection
- Verify URLs in `ModelService.kt`
- Check device storage space

### App Crashes on Launch
- Ensure minimum SDK 26
- Check Gradle sync completed successfully
- Verify all dependencies are downloaded

### Microphone Permission Denied
- Go to Settings → Apps → RunAnywhere Kotlin → Permissions
- Enable "Microphone" permission

### Poor Performance
- Use a device with at least 2GB RAM
- Close other apps to free memory
- Consider using smaller models

## Privacy & Security

All AI processing happens **100% on-device**:
- ✅ No data sent to servers
- ✅ No internet required (after model download)
- ✅ Complete privacy
- ✅ Works offline

## Resources

- [RunAnywhere SDK Documentation](https://github.com/RunanywhereAI/runanywhere-sdks)
- [Kotlin SDK API Reference](../../sdk/runanywhere-kotlin/docs/Documentation.md)
- [Release Notes](https://github.com/RunanywhereAI/runanywhere-sdks/releases)

## License

See the [LICENSE](../../LICENSE) file for details.

## Support

For issues and questions:
- GitHub Issues: [runanywhere-sdks/issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- Documentation: [RunAnywhere Docs](https://github.com/RunanywhereAI/runanywhere-sdks)

---

**Built with RunAnywhere SDK**
