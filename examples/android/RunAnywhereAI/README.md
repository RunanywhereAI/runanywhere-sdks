# RunAnywhere AI - Android Speech-to-Text Demo

This Android sample app demonstrates on-device Speech-to-Text using the RunAnywhere SDK with Whisper
and WebRTC VAD.

## Features

### 🎤 Speech-to-Text Capabilities

- **Whisper STT**: On-device speech recognition using OpenAI's Whisper model
- **WebRTC VAD**: Voice Activity Detection for automatic speech segmentation
- **Real-time Processing**: Continuous recording with automatic transcription
- **Privacy-First**: All processing happens on-device, no data leaves the device

### 🔧 Technical Components

- **WhisperSTTComponent**: Handles speech-to-text transcription
- **WebRTCVADComponent**: Detects speech/silence boundaries
- **ModelService**: Manages model downloads and storage
- **Audio Recording**: Real-time audio capture from device microphone

## Prerequisites

- Android Studio Arctic Fox or later
- Android SDK API Level 24+ (Android 7.0+)
- Kotlin 1.9.0 or later
- Device with microphone access
- At least 500MB free storage for models

## Setup Instructions

### 1. Clone the Repository

```bash
git clone <repository-url>
cd RunAnywhere-Android
```

### 2. Open in Android Studio

1. Open Android Studio
2. Select "Open an Existing Project"
3. Navigate to `examples/android/RunAnywhereAI`
4. Wait for Gradle sync to complete

### 3. Download Whisper Model

The app requires a Whisper model for STT. You have two options:

#### Option A: Manual Download (Recommended for Development)

1. Download the model from Hugging Face:
    - [Whisper Base Model (74MB)](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin)

2. Place the model in your device's external storage:
   ```
   /Android/data/com.runanywhere.runanywhereai/files/models/ggml-base.bin
   ```

#### Option B: Automatic Download (Built into App)

The app will automatically download models when needed (requires internet connection).

### 4. Build and Run

1. Connect your Android device or start an emulator
2. Click "Run" in Android Studio or use:
   ```bash
   ./gradlew installDebug
   ```

### 5. Grant Permissions

When the app launches, it will request microphone permission. Grant this permission to enable STT
functionality.

## Usage

### Basic Speech Recognition

1. **Launch the app** - The STT engine will initialize automatically
2. **Press the microphone button** - Recording will start
3. **Speak clearly** - The VAD will detect when you're speaking
4. **Stop speaking** - After a brief pause, your speech will be transcribed
5. **View results** - The transcription appears in the result card

### VAD Indicators

- **"VAD: Speech detected (XX%)"** - Voice activity detected with confidence level
- **"VAD: Silence"** - No speech detected
- **"VAD: Inactive"** - Recording not started

### Model Status

The app shows the current STT engine status:

- **Whisper STT**: Ready/Not Ready
- **VAD**: Active/Inactive
- **Model**: Currently loaded model name

## Architecture

```
MainActivity.kt
├── STT Components
│   ├── WhisperSTTComponent    # Speech-to-text processing
│   └── WebRTCVADComponent     # Voice activity detection
├── Audio Pipeline
│   ├── AudioRecord            # Captures microphone input
│   ├── VAD Processing         # Detects speech segments
│   └── Whisper Transcription  # Converts speech to text
└── UI Components
    ├── Status Card            # Shows engine status
    ├── Result Card            # Displays transcription
    └── Record Button          # Controls recording
```

## Key Dependencies

```kotlin
// Speech-to-Text
implementation("io.github.givimad:whisper-jni:1.7.1")

// Voice Activity Detection
implementation("com.github.gkonovalov.android-vad:webrtc:2.0.10")

// Model Management
implementation("com.mindorks.android:prdownloader:0.6.0")
```

## Performance Tips

### For Best Results

1. **Use in quiet environment** - Background noise affects accuracy
2. **Speak clearly** - Articulate words properly
3. **Appropriate distance** - Hold device 6-12 inches from mouth
4. **Model selection** - Use larger models for better accuracy (at cost of speed)

### Device Requirements

| Model | RAM Required | Storage | Speed |
|-------|-------------|---------|-------|
| Tiny  | 39MB | 39MB | Fast |
| Base  | 74MB | 74MB | Good |
| Small | 244MB | 244MB | Moderate |
| Medium | 769MB | 769MB | Slow |

## Troubleshooting

### STT Not Ready

- Ensure model is downloaded
- Check storage permissions
- Verify sufficient free memory

### No Transcription

- Check microphone permission
- Ensure you're speaking loud enough
- Verify VAD is detecting speech

### Poor Accuracy

- Try a larger model
- Reduce background noise
- Speak more clearly
- Check audio recording quality

## Advanced Configuration

### Custom VAD Settings

```kotlin
VADConfig(
    sampleRate = 16000,           // Audio sample rate
    frameSize = 320,              // Samples per frame (20ms)
    speechDurationMs = 100,       // Min speech duration
    silenceDurationMs = 500       // Silence to stop recording
)
```

### Whisper Configuration

```kotlin
WhisperSTTConfig(
    modelType = WhisperModel.ModelType.BASE,
    language = "en",              // null for auto-detect
    translate = false,            // Translate to English
    nThreads = 4,                // Processing threads
    beamSize = 5                 // Beam search width
)
```

## Building for Release

1. Generate signed APK:
   ```bash
   ./gradlew assembleRelease
   ```

2. Enable ProGuard for optimization:
   ```kotlin
   buildTypes {
       release {
           isMinifyEnabled = true
           proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
       }
   }
   ```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

This sample is part of the RunAnywhere SDK. See LICENSE file for details.

## Support

For issues or questions:

- Open an issue on GitHub
- Check the documentation
- Contact the RunAnywhere team
