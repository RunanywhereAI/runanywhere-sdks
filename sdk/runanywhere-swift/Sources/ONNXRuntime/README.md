# ONNXRuntime Module

The ONNXRuntime module provides speech-to-text (STT), text-to-speech (TTS), and voice activity detection (VAD) capabilities for the RunAnywhere Swift SDK using ONNX Runtime with models like Whisper, Piper, and Silero.

## Overview

This module enables on-device voice processing with support for:

- Speech-to-text transcription (Whisper, Zipformer, Paraformer models)
- Text-to-speech synthesis (Piper, VITS voices)
- Voice activity detection (Silero VAD)
- Streaming and batch processing
- CoreML acceleration on Apple devices

## Requirements

| Platform | Minimum Version |
|----------|-----------------|
| iOS      | 17.0+           |
| macOS    | 14.0+           |

The module requires:
- `RABackendONNX.xcframework` (included in SDK)
- ONNX Runtime (automatically linked)

## Installation

The ONNXRuntime module is included in the RunAnywhere SDK. Add it to your target:

### Swift Package Manager

```swift
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

### Xcode

1. Go to **File > Add Package Dependencies...**
2. Enter: `https://github.com/RunanywhereAI/runanywhere-sdks`
3. Select version and add `RunAnywhereONNX` to your target

## Usage

### Registration

Register the module at app startup before using STT, TTS, or VAD capabilities:

```swift
import RunAnywhere
import ONNXRuntime

@main
struct MyApp: App {
    init() {
        Task { @MainActor in
            ONNX.register()

            try RunAnywhere.initialize(
                apiKey: "<YOUR_API_KEY>",
                baseURL: "https://api.runanywhere.ai",
                environment: .production
            )
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### Speech-to-Text (STT)

#### Loading a Model

```swift
try await RunAnywhere.loadSTTModel("whisper-base-onnx")

let isLoaded = await RunAnywhere.isSTTModelLoaded
```

#### Simple Transcription

```swift
let audioData: Data = // your audio data (16kHz, mono, Float32)
let text = try await RunAnywhere.transcribe(audioData)
print("Transcribed: \(text)")
```

#### Transcription with Options

```swift
let options = STTOptions(
    language: "en-US",
    sampleRate: 16000,
    enableWordTimestamps: true
)

let result = try await RunAnywhere.transcribeWithOptions(audioData, options: options)
print("Text: \(result.text)")
print("Confidence: \(result.confidence ?? 0)")
if let language = result.detectedLanguage {
    print("Detected language: \(language)")
}
```

#### Streaming Transcription

```swift
let output = try await RunAnywhere.transcribeStream(
    audioData: audioData,
    options: STTOptions(language: "en")
) { partialResult in
    print("Partial: \(partialResult.transcript)")
}

print("Final: \(output.text)")
```

#### Unloading

```swift
try await RunAnywhere.unloadSTTModel()
```

### Text-to-Speech (TTS)

#### Loading a Voice

```swift
try await RunAnywhere.loadTTSVoice("piper-en-us-amy")

let isLoaded = await RunAnywhere.isTTSVoiceLoaded
```

#### Simple Synthesis

```swift
let output = try await RunAnywhere.synthesize(
    "Hello! Welcome to RunAnywhere.",
    options: TTSOptions(rate: 1.0, pitch: 1.0, volume: 0.8)
)

// output.audioData contains the synthesized audio
// output.duration contains the audio length in seconds
```

#### Speak with Automatic Playback

```swift
// Synthesize and play through device speakers
try await RunAnywhere.speak("Hello world")

// With options
let result = try await RunAnywhere.speak(
    "Hello",
    options: TTSOptions(rate: 1.2, pitch: 1.0)
)
print("Duration: \(result.duration)s")
```

#### Streaming Synthesis

```swift
let output = try await RunAnywhere.synthesizeStream(
    "Long text to synthesize...",
    options: TTSOptions()
) { chunk in
    // Process audio chunk as it's generated
    playAudioChunk(chunk)
}
```

#### Available Voices

```swift
let voices = await RunAnywhere.availableTTSVoices
for voice in voices {
    print("Voice: \(voice)")
}
```

#### Stopping Synthesis

```swift
await RunAnywhere.stopSynthesis()
await RunAnywhere.stopSpeaking()
```

### Voice Activity Detection (VAD)

#### Initialization

```swift
// Default configuration
try await RunAnywhere.initializeVAD()

// Custom configuration
try await RunAnywhere.initializeVAD(VADConfiguration(
    sampleRate: 16000,
    frameLength: 0.032,
    energyThreshold: 0.5
))
```

#### Detection

```swift
// From audio samples
let samples: [Float] = // your audio samples
let speechDetected = try await RunAnywhere.detectSpeech(in: samples)

// From AVAudioPCMBuffer
let buffer: AVAudioPCMBuffer = // your audio buffer
let speechDetected = try await RunAnywhere.detectSpeech(in: buffer)
```

#### Callbacks

```swift
// Speech activity callback
await RunAnywhere.setVADSpeechActivityCallback { event in
    switch event {
    case .started:
        print("Speech started")
    case .ended:
        print("Speech ended")
    }
}

// Audio buffer callback
await RunAnywhere.setVADAudioBufferCallback { samples in
    // Process audio samples
}
```

#### Control

```swift
try await RunAnywhere.startVAD()
try await RunAnywhere.stopVAD()
await RunAnywhere.cleanupVAD()
```

## API Reference

### ONNX Module

```swift
public enum ONNX: RunAnywhereModule {
    /// Module identifier
    public static let moduleId = "onnx"

    /// Human-readable module name
    public static let moduleName = "ONNX Runtime"

    /// Capabilities provided by this module
    public static let capabilities: Set<SDKComponent> = [.stt, .tts, .vad]

    /// Default registration priority
    public static let defaultPriority: Int = 100

    /// Inference framework used
    public static let inferenceFramework: InferenceFramework = .onnx

    /// Module version
    public static let version = "2.0.0"

    /// Underlying ONNX Runtime version
    public static let onnxRuntimeVersion = "1.23.2"

    /// Register the module with the service registry
    @MainActor
    public static func register(priority: Int = 100)

    /// Unregister the module
    public static func unregister()

    /// Check if the module can handle a given STT model
    public static func canHandleSTT(modelId: String?) -> Bool

    /// Check if the module can handle a given TTS model
    public static func canHandleTTS(modelId: String?) -> Bool

    /// Check if the module can handle VAD
    public static func canHandleVAD(modelId: String?) -> Bool
}
```

### Model Compatibility

#### STT Models

The ONNX module handles STT models containing:
- `whisper` (Whisper variants)
- `zipformer` (Zipformer ASR)
- `paraformer` (Paraformer ASR)

#### TTS Models

The ONNX module handles TTS models containing:
- `piper` (Piper TTS voices)
- `vits` (VITS TTS models)

#### VAD

The module uses Silero VAD by default for voice activity detection.

### STT Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `language` | String | "en" | Language code for transcription |
| `sampleRate` | Int | 16000 | Audio sample rate in Hz |
| `enableWordTimestamps` | Bool | false | Include word-level timestamps |
| `enableVAD` | Bool | true | Enable voice activity detection |

### TTS Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rate` | Float | 1.0 | Speaking rate multiplier |
| `pitch` | Float | 1.0 | Voice pitch multiplier |
| `volume` | Float | 1.0 | Output volume (0.0 - 1.0) |
| `language` | String | "en-US" | Voice language |
| `sampleRate` | Int | 22050 | Output sample rate |
| `audioFormat` | AudioFormat | .wav | Output audio format |

### VAD Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `sampleRate` | Int | 16000 | Audio sample rate in Hz |
| `frameLength` | Double | 0.032 | Frame length in seconds |
| `energyThreshold` | Double | 0.5 | Energy threshold for detection |

## Architecture

The module follows a thin wrapper pattern:

```
ONNX.swift (Swift wrapper)
       |
ONNXBackend (C headers)
       |
RABackendONNX.xcframework (C++ implementation)
       |
+---------------+----------------+
|               |                |
ONNX Runtime   Sherpa-ONNX     Silero VAD
```

The Swift code registers the backend with the C++ service registry, which handles all model loading and inference operations internally.

## Performance

### STT Performance

| Device | Model | Real-time Factor |
|--------|-------|------------------|
| iPhone 15 Pro | Whisper Base | 0.3x (3x faster than real-time) |
| iPhone 15 Pro | Whisper Small | 0.5x |
| M1 MacBook | Whisper Base | 0.2x |
| M1 MacBook | Whisper Small | 0.3x |

### TTS Performance

| Device | Voice | Characters/sec |
|--------|-------|----------------|
| iPhone 15 Pro | Piper Amy | 200-300 |
| M1 MacBook | Piper Amy | 400-500 |

Performance varies based on model size and device thermal state.

## Audio Format Requirements

### STT Input

- Sample rate: 16000 Hz (default, configurable)
- Channels: Mono
- Format: Float32 PCM

### TTS Output

- Sample rate: 22050 Hz (default, configurable)
- Channels: Mono
- Format: Float32 PCM or WAV

## Troubleshooting

### Model Load Fails

1. Ensure the model is downloaded: check `ModelInfo.isDownloaded`
2. Verify the model format matches the capability (Whisper for STT, Piper for TTS)
3. Check available memory

### Poor Transcription Quality

1. Ensure audio is 16kHz mono
2. Check audio levels (too quiet or clipped)
3. Try a larger Whisper model

### TTS Audio Issues

1. Verify the voice model is fully downloaded
2. Check audio output route
3. Ensure sample rate matches expectations

### Registration Not Working

1. Ensure `register()` is called on the main actor
2. Call `register()` before `RunAnywhere.initialize()`
3. Check for registration errors in logs

## License

Copyright 2025 RunAnywhere AI. All rights reserved.
