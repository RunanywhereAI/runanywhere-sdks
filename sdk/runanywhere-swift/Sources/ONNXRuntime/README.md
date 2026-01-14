# ONNXRuntime Module

> Speech-to-Text (STT), Text-to-Speech (TTS), and Voice Activity Detection (VAD) using ONNX Runtime.

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+" />
  <img src="https://img.shields.io/badge/ONNX-Runtime%201.17-blue?style=flat-square" alt="ONNX Runtime" />
  <img src="https://img.shields.io/badge/CoreML-Supported-green?style=flat-square" alt="CoreML" />
</p>

---

## Overview

The **ONNXRuntime** module provides speech AI capabilities to the RunAnywhere SDK using [ONNX Runtime](https://onnxruntime.ai/) as the inference engine. It enables on-device speech recognition (Whisper), voice synthesis (Piper TTS), and voice activity detection (Silero VAD).

### Key Features

- **Speech-to-Text** — Real-time and batch transcription with Whisper models
- **Text-to-Speech** — Neural voice synthesis with Piper TTS
- **Voice Activity Detection** — Speech detection with Silero VAD
- **Multi-language support** — Whisper supports 100+ languages
- **Streaming capabilities** — Real-time audio processing
- **CoreML acceleration** — Native Apple hardware optimization

---

## Installation

The ONNXRuntime module is included with the RunAnywhere Swift SDK:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.16.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "RunAnywhere", package: "runanywhere-sdks"),
            .product(name: "RunAnywhereONNX", package: "runanywhere-sdks"),
        ]
    )
]
```

---

## Quick Start

### 1. Register the Module

```swift
import RunAnywhere
import ONNXRuntime

@MainActor
func setupSDK() async {
    // Initialize SDK
    try RunAnywhere.initialize()

    // Register ONNX backend (provides STT, TTS, VAD)
    ONNX.register()
}
```

### 2. Speech-to-Text

```swift
// Download and load STT model
for try await progress in RunAnywhere.downloadModel("sherpa-onnx-whisper-tiny.en") {
    print("Progress: \(Int(progress.overallProgress * 100))%")
}
try await RunAnywhere.loadSTTModel("sherpa-onnx-whisper-tiny.en")

// Transcribe audio
let transcription = try await RunAnywhere.transcribe(audioData)
print("Transcribed: \(transcription)")
```

### 3. Text-to-Speech

```swift
// Download and load TTS voice
for try await progress in RunAnywhere.downloadModel("piper-en-us-amy-medium") {
    print("Progress: \(Int(progress.overallProgress * 100))%")
}
try await RunAnywhere.loadTTSVoice("piper-en-us-amy-medium")

// Synthesize speech
let result = try await RunAnywhere.synthesize(
    "Hello, welcome to RunAnywhere!",
    options: TTSOptions(speakingRate: 1.0, pitch: 1.0)
)
// result.audioData contains WAV audio bytes
```

### 4. Voice Activity Detection

```swift
// Initialize VAD
try await RunAnywhere.initializeVAD(
    options: VADOptions(sensitivity: 0.5)
)

// Detect speech in audio samples
let result = try await RunAnywhere.detectSpeech(audioSamples)
print("Is speech: \(result.isSpeech)")
print("Probability: \(result.probability)")
```

---

## Supported Models

### Speech-to-Text (Whisper)

| Model | Size | Languages | Speed | Quality |
|-------|------|-----------|-------|---------|
| whisper-tiny.en | ~75MB | English | Fastest | Good |
| whisper-base.en | ~150MB | English | Fast | Better |
| whisper-small | ~500MB | Multilingual | Medium | Good |
| whisper-medium | ~1.5GB | Multilingual | Slower | High |

### Text-to-Speech (Piper)

| Voice | Size | Language | Description |
|-------|------|----------|-------------|
| piper-en-us-amy-medium | ~65MB | English (US) | Natural female voice |
| piper-en-us-lessac-medium | ~65MB | English (US) | Clear male voice |
| piper-en-gb-alan-medium | ~65MB | English (UK) | British male voice |
| piper-de-thorsten-medium | ~65MB | German | German male voice |
| piper-es-carlfm-medium | ~65MB | Spanish | Spanish male voice |

### Voice Activity Detection

| Model | Size | Description |
|-------|------|-------------|
| silero-vad | ~2MB | Silero VAD v4 (built-in) |

---

## Configuration

### STT Options

```swift
let options = STTOptions(
    language: "en-US",           // Language code
    enableTimestamps: true       // Word-level timestamps
)

let result = try await RunAnywhere.transcribeWithTimestamps(
    audioData,
    options: options
)

// Access word timestamps
for word in result.words ?? [] {
    print("\(word.word): \(word.start)s - \(word.end)s")
}
```

### TTS Options

```swift
let options = TTSOptions(
    speakingRate: 1.0,   // Speed (0.5–2.0)
    pitch: 1.0,          // Pitch (0.5–2.0)
    volume: 0.8          // Volume (0.0–1.0)
)

let result = try await RunAnywhere.synthesize(text, options: options)
```

### VAD Options

```swift
let options = VADOptions(
    sensitivity: 0.5,            // Detection sensitivity (0.0–1.0)
    frameDurationMs: 30,         // Frame size in milliseconds
    minSpeechDurationMs: 250,    // Minimum speech duration
    minSilenceDurationMs: 500    // Minimum silence to end speech
)

try await RunAnywhere.initializeVAD(options: options)
```

---

## Architecture

The ONNXRuntime module wraps the C++ ONNX backend:

```
┌─────────────────────────────────────────────────┐
│              Your Application                    │
├─────────────────────────────────────────────────┤
│         RunAnywhere Public API                   │
│  (RunAnywhere.transcribe(), .synthesize(), etc.)│
├─────────────────────────────────────────────────┤
│           ONNXRuntime Module                     │
│    ┌─────────────────────────────────────────┐  │
│    │  ONNX.swift (registration)              │  │
│    └─────────────────────────────────────────┘  │
├─────────────────────────────────────────────────┤
│            C Bridge (ONNXBackend)                │
│    rac_backend_onnx_register()                  │
│    rac_stt_*() / rac_tts_*() / rac_vad_*()     │
├─────────────────────────────────────────────────┤
│          RABackendONNX.xcframework              │
│    (Sherpa-ONNX + ONNX Runtime)                 │
├─────────────────────────────────────────────────┤
│         ONNXRuntime.xcframework                  │
│    (Official ONNX Runtime with CoreML)          │
└─────────────────────────────────────────────────┘
```

### Binary Dependencies

| Framework | Size | Description |
|-----------|------|-------------|
| `RABackendONNX.xcframework` | ~50-70MB | Sherpa-ONNX models |
| `ONNXRuntimeBinary` | ~20MB | Official ONNX Runtime |
| `RACommons.xcframework` | ~2MB | Shared infrastructure |

---

## Audio Format Requirements

### Input Audio (STT)

| Parameter | Requirement |
|-----------|-------------|
| Sample Rate | 16,000 Hz |
| Channels | Mono (1) |
| Format | Float32 or PCM Int16 |
| Encoding | Raw samples |

### Output Audio (TTS)

| Parameter | Value |
|-----------|-------|
| Sample Rate | 22,050 Hz (typical) |
| Channels | Mono (1) |
| Format | Float32 |
| Container | WAV |

### Converting Audio

```swift
import AVFoundation

// Convert recorded audio to required format
func convertToSTTFormat(fileURL: URL) async throws -> Data {
    let file = try AVAudioFile(forReading: fileURL)
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    // ... conversion logic
    return audioData
}
```

---

## Performance

### Benchmarks

| Operation | Device | Model | Latency |
|-----------|--------|-------|---------|
| STT (10s audio) | iPhone 15 Pro | whisper-tiny.en | ~2.5s |
| STT (10s audio) | M1 Mac | whisper-tiny.en | ~1.5s |
| TTS (50 words) | iPhone 15 Pro | piper-amy | ~1.0s |
| TTS (50 words) | M1 Mac | piper-amy | ~0.5s |
| VAD (100ms) | Any | silero-vad | ~5ms |

### Optimization Tips

1. **Use smaller models** for real-time applications
2. **Enable CoreML** for Apple Silicon optimization
3. **Process audio in chunks** for streaming
4. **Preload models** during app startup

---

## Error Handling

```swift
do {
    let transcription = try await RunAnywhere.transcribe(audioData)
} catch let error as SDKError {
    switch error.code {
    case .modelNotFound:
        print("STT model not downloaded.")
    case .modelLoadFailed:
        print("Failed to load STT model.")
    case .transcriptionFailed:
        print("Transcription failed: \(error.message)")
    case .invalidInput:
        print("Invalid audio format.")
    default:
        print("Error: \(error.localizedDescription)")
    }
}

do {
    let result = try await RunAnywhere.synthesize(text)
} catch let error as SDKError {
    switch error.code {
    case .modelNotFound:
        print("TTS voice not loaded.")
    case .synthesisFailed:
        print("Synthesis failed: \(error.message)")
    default:
        print("Error: \(error.localizedDescription)")
    }
}
```

---

## API Reference

### `ONNX` Module

```swift
public enum ONNX: RunAnywhereModule {
    /// Module identifier
    static let moduleId: String = "onnx"

    /// Human-readable name
    static let moduleName: String = "ONNX Runtime"

    /// Supported capabilities
    static let capabilities: Set<SDKComponent> = [.stt, .tts, .vad]

    /// Inference framework identifier
    static let inferenceFramework: InferenceFramework = .onnx

    /// Current module version
    static let version: String = "2.0.0"

    /// Underlying ONNX Runtime version
    static let onnxRuntimeVersion: String = "1.23.2"

    /// Register the module with the SDK
    @MainActor
    static func register(priority: Int = 100)

    /// Unregister the module
    static func unregister()

    /// Check if this module can handle a model for STT
    static func canHandleSTT(modelId: String?) -> Bool

    /// Check if this module can handle a model for TTS
    static func canHandleTTS(modelId: String?) -> Bool

    /// Check if this module can handle VAD
    static func canHandleVAD(modelId: String?) -> Bool
}
```

### Auto-Registration

```swift
// Trigger registration automatically when module is imported
_ = ONNX.autoRegister
```

---

## Troubleshooting

### Transcription Returns Empty

**Symptoms:** Empty string returned from `transcribe()`

**Solutions:**
1. Verify audio is not silent (check levels)
2. Ensure correct sample rate (16kHz)
3. Check audio is mono channel
4. Verify model is fully loaded

### TTS Audio Sounds Robotic

**Symptoms:** Low-quality synthesized speech

**Solutions:**
1. Ensure using neural TTS model (Piper)
2. Check `speakingRate` isn't too high
3. Verify model downloaded completely
4. Try a different voice model

### VAD Not Detecting Speech

**Symptoms:** `isSpeech` always false

**Solutions:**
1. Increase `sensitivity` option
2. Reduce `minSpeechDurationMs`
3. Check audio levels (not too quiet)
4. Verify correct audio format

### Memory Issues

**Symptoms:** App crashes or memory warnings

**Solutions:**
1. Unload unused models
2. Don't load STT and TTS simultaneously if memory-constrained
3. Use smaller model variants
4. Process shorter audio segments

---

## Version History

| Version | ONNX Runtime | Changes |
|---------|--------------|---------|
| 2.0.0 | 1.23.2 | Modular architecture, C++ backend |
| 1.0.0 | 1.17.1 | Initial release |

---

## See Also

- [RunAnywhere SDK](../../README.md) — Main SDK documentation
- [API Reference](../../Docs/Documentation.md) — Complete API documentation
- [LlamaCPP Module](../LlamaCPPRuntime/README.md) — LLM backend
- [ONNX Runtime](https://onnxruntime.ai/) — Upstream project
- [Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx) — Speech models

---

## License

Copyright © 2025 RunAnywhere AI. All rights reserved.
