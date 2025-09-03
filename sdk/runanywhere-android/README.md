# RunAnywhere Kotlin STT SDK (MVP)

A Kotlin SDK for Speech-to-Text (STT) with Voice Activity Detection (VAD), targeting Android Studio
IDE plugins initially with architecture prepared for Android apps.

## 🎯 MVP Features

- **WebRTC VAD**: Efficient voice activity detection
- **Whisper.cpp STT**: On-device speech-to-text via JNI
- **Model Management**: Automatic download and lifecycle management
- **Event System**: Real-time events for VAD and STT status
- **Analytics**: Built-in usage tracking and performance metrics
- **Stream Processing**: Real-time audio streaming with partial results

## 📁 Project Structure

```
runanywhere-android/
├── core/                    # Core SDK module (JVM)
│   ├── components/         # VAD and STT components
│   ├── models/            # Model management
│   ├── events/            # Event system
│   ├── analytics/         # Analytics tracking
│   └── public/            # Public API (RunAnywhereSTT)
├── jni/                    # JNI bindings
│   ├── kotlin/            # JNI interfaces
│   └── cpp/               # Native C++ implementations
└── plugin/                # IntelliJ Plugin module (future)
```

## 🚀 Quick Start

### Installation

Add to your `build.gradle.kts`:

```kotlin
dependencies {
    implementation("com.runanywhere:sdk-stt:1.0.0")
}
```

### Basic Usage

```kotlin
import com.runanywhere.sdk.public.RunAnywhereSTT
import com.runanywhere.sdk.public.STTSDKConfig

// Initialize the SDK
suspend fun initializeSDK() {
    RunAnywhereSTT.initialize(
        STTSDKConfig(
            modelId = "whisper-base",
            enableVAD = true,
            language = "en"
        )
    )
}

// Simple transcription
suspend fun transcribeAudio(audioData: ByteArray): String {
    return RunAnywhereSTT.transcribe(audioData)
}

// Stream transcription with VAD
fun transcribeStream(audioFlow: Flow<ByteArray>) {
    RunAnywhereSTT.transcribeStream(audioFlow)
        .collect { event ->
            when (event) {
                is TranscriptionEvent.SpeechStart -> println("Speech started")
                is TranscriptionEvent.PartialTranscription -> println("Partial: ${event.text}")
                is TranscriptionEvent.FinalTranscription -> println("Final: ${event.text}")
                is TranscriptionEvent.SpeechEnd -> println("Speech ended")
                is TranscriptionEvent.Error -> println("Error: ${event.error}")
            }
        }
}
```

## 🔧 Components

### VAD Component

- WebRTC-based voice activity detection
- Configurable aggressiveness (0-3)
- Real-time speech/silence detection

### STT Component

- Whisper.cpp integration via JNI
- Multiple model sizes (tiny, base, small, medium)
- Streaming transcription support

### Model Management

- Automatic model downloading
- Progress tracking
- Local storage management
- Model lifecycle control

## 📊 Available Models

| Model | Size | Description |
|-------|------|-------------|
| whisper-tiny | 39MB | Fastest, lower accuracy |
| whisper-base | 74MB | Good balance |
| whisper-small | 244MB | Better accuracy |
| whisper-medium | 769MB | High accuracy |

## 🎪 Event System

The SDK provides comprehensive events for monitoring:

```kotlin
EventBus.events.collect { event ->
    when (event) {
        is STTEvent.Initialized -> // SDK ready
        is ModelEvent.DownloadProgress -> // Model downloading
        is TranscriptionEvent.FinalTranscription -> // Transcription complete
    }
}
```

## 🔨 Building from Source

### Prerequisites

- JDK 17+
- Android SDK (for Android targets)
- CMake 3.22+ (for native libraries)

### Build Commands

```bash
# Build the entire project
./gradlew build

# Run tests
./gradlew test

# Build core module only
./gradlew :core:build

# Build JNI module
./gradlew :jni:build
```

## 🧪 Testing

```kotlin
class RunAnywhereSTTTest {
    @Test
    fun `test transcription`() = runTest {
        RunAnywhereSTT.initialize()
        val audio = loadTestAudio("test.wav")
        val result = RunAnywhereSTT.transcribe(audio)
        assertEquals("expected text", result)
    }
}
```

## 📈 Performance Requirements

- **VAD Decision**: < 10ms per frame
- **STT First Token**: < 500ms
- **Full Transcription**: < 2s for 10s audio
- **Memory Usage**: < 500MB for base model
- **CPU Usage**: < 30% during active transcription

## 🚦 Implementation Status

### ✅ Completed

- [x] Core component abstractions
- [x] VAD component implementation
- [x] STT component implementation
- [x] Model management system
- [x] Event system
- [x] Analytics tracking
- [x] File management
- [x] Public API (RunAnywhereSTT)
- [x] JNI interfaces
- [x] Build configuration

### 🚧 In Progress

- [ ] Native C++ implementations (stub implementations provided)
- [ ] IntelliJ Plugin module
- [ ] Comprehensive testing
- [ ] Documentation

### 📅 Future Enhancements

- [ ] LLM integration
- [ ] TTS component
- [ ] Speaker diarization
- [ ] Wake word detection
- [ ] Android app support
- [ ] iOS support via KMP

## 📄 License

Apache License 2.0

## 🤝 Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

## 📞 Support

For issues and questions:

- GitHub Issues: [github.com/runanywhere/sdk-kotlin](https://github.com/runanywhere/sdk-kotlin)
- Email: support@runanywhere.com

---

Built with ❤️ by RunAnywhere Team
