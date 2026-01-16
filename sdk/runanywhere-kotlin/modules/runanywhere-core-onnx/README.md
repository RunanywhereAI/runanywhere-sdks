# RunAnywhere Core ONNX Module

**Speech & Audio inference backend for the RunAnywhere Kotlin SDK** — powered by [ONNX Runtime](https://onnxruntime.ai) and [Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx) for on-device STT, TTS, and VAD.

[![Maven Central](https://img.shields.io/maven-central/v/com.runanywhere.sdk/runanywhere-core-onnx?label=Maven%20Central)](https://search.maven.org/artifact/com.runanywhere.sdk/runanywhere-core-onnx)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Platform: Android](https://img.shields.io/badge/Platform-Android%207.0%2B-green)](https://developer.android.com)

---

## Features

This module provides the **Speech-to-Text (STT)**, **Text-to-Speech (TTS)**, and **Voice Activity Detection (VAD)** backends, enabling complete voice AI capabilities on-device using ONNX Runtime and Sherpa-ONNX.

**This module is optional.** Only include it if your app needs STT, TTS, or VAD capabilities.

- **Speech-to-Text (STT)** — Whisper-based transcription on-device
- **Text-to-Speech (TTS)** — Neural TTS voice synthesis
- **Voice Activity Detection (VAD)** — Silero VAD for speech detection
- **Streaming Support** — Real-time transcription and synthesis
- **Multiple Languages** — Multi-language STT and TTS support
- **ARM64 Optimized** — Native ONNX Runtime for Android

---

## Installation

Add to your module's `build.gradle.kts`:

```kotlin
dependencies {
    // Core SDK (required)
    implementation("com.runanywhere.sdk:runanywhere-kotlin:0.1.4")

    // ONNX backend (this module)
    implementation("com.runanywhere.sdk:runanywhere-core-onnx:0.1.4")
}
```

---

## Usage

Once included, the module automatically registers the `ONNX` framework with the SDK.

### Speech-to-Text (STT)

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.*

// Register and download STT model
val sttModel = RunAnywhere.registerModel(
    name = "Whisper Tiny",
    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2",
    framework = InferenceFramework.ONNX,
    modality = ModelCategory.SPEECH_RECOGNITION
)

RunAnywhere.downloadModel(sttModel.id).collect { progress ->
    println("Download: ${(progress.progress * 100).toInt()}%")
}

// Load and transcribe
RunAnywhere.loadSTTModel(sttModel.id)
val text = RunAnywhere.transcribe(audioData)
println("Transcription: $text")
```

### Advanced STT Options

```kotlin
val output = RunAnywhere.transcribeWithOptions(
    audioData = audioBytes,
    options = STTOptions(
        language = "en",
        enablePunctuation = true,
        enableTimestamps = true
    )
)

println("Text: ${output.text}")
println("Confidence: ${output.confidence}")
output.wordTimestamps?.forEach { word ->
    println("${word.word}: ${word.startTime}s - ${word.endTime}s")
}
```

### Streaming STT

```kotlin
RunAnywhere.transcribeStream(audioData) { partial ->
    // Update UI with partial results
    println("Partial: ${partial.transcript}")
}
```

---

### Text-to-Speech (TTS)

```kotlin
// Register and download TTS voice
val ttsVoice = RunAnywhere.registerModel(
    name = "English US Voice",
    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-libritts-high.tar.bz2",
    framework = InferenceFramework.ONNX,
    modality = ModelCategory.SPEECH_SYNTHESIS
)

RunAnywhere.downloadModel(ttsVoice.id).collect { /* progress */ }

// Load and synthesize
RunAnywhere.loadTTSVoice(ttsVoice.id)

// Simple speak (handles playback)
RunAnywhere.speak("Hello, world!")

// Or get audio bytes
val output = RunAnywhere.synthesize("Welcome to RunAnywhere")
val audioBytes = output.audioData
val duration = output.duration
```

### TTS Options

```kotlin
val output = RunAnywhere.synthesize(
    text = "Hello!",
    options = TTSOptions(
        rate = 1.2f,     // Faster speech
        pitch = 1.0f,
        volume = 0.8f
    )
)
```

### Streaming TTS

```kotlin
RunAnywhere.synthesizeStream(longText) { chunk ->
    audioPlayer.play(chunk)  // Play as chunks arrive
}
```

---

### Voice Activity Detection (VAD)

```kotlin
// Detect speech in audio
val result = RunAnywhere.detectVoiceActivity(audioData)

if (result.hasSpeech) {
    println("Speech detected! Confidence: ${result.confidence}")
}
```

### Configure VAD

```kotlin
RunAnywhere.configureVAD(VADConfiguration(
    threshold = 0.5f,
    minSpeechDurationMs = 250,
    minSilenceDurationMs = 300
))
```

### Streaming VAD

```kotlin
RunAnywhere.streamVAD(audioSamplesFlow)
    .collect { result ->
        when {
            result.hasSpeech -> println("Speaking...")
            else -> println("Silence")
        }
    }
```

---

## Supported Models

### Speech-to-Text (Whisper)

| Model | Size | Languages | Quality |
|-------|------|-----------|---------|
| whisper-tiny | ~75MB | 99 languages | Good for mobile |
| whisper-base | ~150MB | 99 languages | Better accuracy |
| whisper-small | ~500MB | 99 languages | High accuracy |

### Text-to-Speech (VITS/Piper)

| Voice | Size | Language | Quality |
|-------|------|----------|---------|
| vits-piper-en_US-libritts-high | ~100MB | English (US) | High quality |
| vits-piper-en_GB-* | ~100MB | English (UK) | High quality |
| vits-piper-de_DE-* | ~100MB | German | High quality |
| vits-piper-es_ES-* | ~100MB | Spanish | High quality |

### VAD (Built-in)

VAD uses Silero VAD which is bundled with Sherpa-ONNX (~5MB).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  RunAnywhere SDK (Kotlin)                    │
│                                                              │
│  RunAnywhere.transcribe() / synthesize() / detectVAD()       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    runanywhere-core-onnx                     │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                 JNI Bridge (Kotlin ↔ C++)               │ │
│  │             librac_backend_onnx_jni.so                  │ │
│  └────────────────────────────────────────────────────────┘ │
│                              │                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                  librunanywhere_onnx.so                 │ │
│  │               RunAnywhere ONNX wrapper                  │ │
│  └────────────────────────────────────────────────────────┘ │
│                              │                               │
│  ┌──────────────────┐  ┌─────────────────────────────────┐ │
│  │ libonnxruntime.so│  │       Sherpa-ONNX libs          │ │
│  │   ONNX Runtime   │  │  STT / TTS / VAD inference      │ │
│  │     (~15MB)      │  │  libsherpa-onnx-*.so            │ │
│  └──────────────────┘  └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## Native Libraries

This module bundles the following native libraries (~25MB total for ARM64):

| Library | Size | Description |
|---------|------|-------------|
| `librac_backend_onnx_jni.so` | ~1MB | JNI bridge |
| `librunanywhere_onnx.so` | ~2MB | RunAnywhere ONNX wrapper |
| `libonnxruntime.so` | ~15MB | ONNX Runtime |
| `libsherpa-onnx-c-api.so` | ~2MB | Sherpa-ONNX C API |
| `libsherpa-onnx-cxx-api.so` | ~3MB | Sherpa-ONNX C++ API |
| `libsherpa-onnx-jni.so` | ~2MB | Sherpa-ONNX JNI bridge |

### Supported ABIs

- `arm64-v8a` — Primary target (modern Android devices)

---

## Build Configuration

### Remote Mode (Default)

Native libraries are automatically downloaded from GitHub releases:

```kotlin
// gradle.properties
runanywhere.testLocal=false  // Downloads from releases
runanywhere.coreVersion=0.1.4
```

### Local Development

For developing with local C++ builds:

```kotlin
// gradle.properties
runanywhere.testLocal=true   // Uses local jniLibs/
```

Then build the native libraries:

```bash
cd ../../  # SDK root
./scripts/build-kotlin.sh --setup
```

---

## Performance

### Speech-to-Text (Pixel 7, 8GB RAM)

| Model | Audio Length | Processing Time | RTF |
|-------|--------------|-----------------|-----|
| whisper-tiny | 5s | ~200ms | 0.04 |
| whisper-tiny | 30s | ~1.2s | 0.04 |
| whisper-base | 5s | ~400ms | 0.08 |

**RTF** = Real-Time Factor (lower is better)

### Text-to-Speech

| Voice | Text Length | Synthesis Time | Duration |
|-------|-------------|----------------|----------|
| libritts-high | 100 chars | ~100ms | ~2s |
| libritts-high | 500 chars | ~300ms | ~10s |

### VAD

- Frame processing: < 5ms per 30ms frame
- Latency: < 100ms speech detection

---

## Audio Format Requirements

### STT Input

- **Format**: PCM (16-bit signed, little-endian)
- **Sample Rate**: 16000 Hz (recommended)
- **Channels**: Mono

```kotlin
val options = STTOptions(
    audioFormat = AudioFormat.PCM,
    sampleRate = 16000
)
```

### TTS Output

- **Format**: PCM (16-bit signed)
- **Sample Rate**: 22050 Hz (default) or 44100 Hz
- **Channels**: Mono

---

## Requirements

- **Android**: API 24+ (Android 7.0+)
- **Architecture**: ARM64 (arm64-v8a)
- **Memory**: 512MB+ free RAM recommended
- **RunAnywhere SDK**: 0.1.4+

---

## Troubleshooting

### STT model fails to load

```
SDKError: MODEL_LOAD_FAILED - Invalid model format
```

**Solution:** Ensure the model is in Sherpa-ONNX format (usually `.tar.bz2` archives from the official releases).

### TTS voice sounds robotic

Try using a higher-quality voice model:
```kotlin
// Use "high" quality variants
val ttsVoice = RunAnywhere.registerModel(
    url = "...libritts-high.tar.bz2"  // Not "low" or "medium"
)
```

### VAD too sensitive / not sensitive enough

Adjust the threshold:
```kotlin
RunAnywhere.configureVAD(VADConfiguration(
    threshold = 0.3f,  // Lower = more sensitive (0.0 - 1.0)
    minSpeechDurationMs = 100  // Shorter = faster detection
))
```

### Audio playback issues

Ensure proper audio format matching:
```kotlin
val output = RunAnywhere.synthesize(text, TTSOptions(
    audioFormat = AudioFormat.PCM,
    sampleRate = 22050
))
// Configure AudioTrack with matching sample rate
```

---

## License

Apache 2.0. See [LICENSE](../../../../LICENSE).

This module includes:
- **ONNX Runtime** — MIT License
- **Sherpa-ONNX** — Apache 2.0 License
- **Silero VAD** — MIT License

---

## See Also

- [RunAnywhere Kotlin SDK](../../README.md) — Main SDK documentation
- [Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx) — Upstream STT/TTS/VAD
- [ONNX Runtime](https://onnxruntime.ai) — ONNX inference engine
- [Sherpa-ONNX Models](https://github.com/k2-fsa/sherpa-onnx/releases) — Model downloads
