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
| iOS      | 17.5+           |
| macOS    | 14.5+           |

The module requires:
- `RABackendONNX.xcframework` (included in SDK)
- ONNX Runtime (automatically linked)

## Installation

The ONNXRuntime module is included in the RunAnywhere SDK. Add it to your target:

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.20.11")
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
var req = RAModelLoadRequest()
req.modelID = "whisper-base-onnx"
req.category = .speechRecognition
req.framework = .onnx
let result = await RunAnywhere.loadModel(req)
print("Loaded: \(result.resolvedPath)")
```

#### Simple Transcription

```swift
let audioData: Data = // your audio data (16kHz, mono, Float32)
let output = try await RunAnywhere.transcribe(audio: audioData)
print("Transcribed: \(output.text)")
```

#### Transcription with Options

```swift
var options = RASTTOptions.defaults()
options.language = .en
options.sampleRate = 16000
options.enableWordTimestamps = true

let output = try await RunAnywhere.transcribe(audio: audioData, options: options)
print("Text: \(output.text)")
print("Confidence: \(output.confidence)")
if output.hasLanguageCode {
    print("Detected language: \(output.languageCode)")
}
```

#### Streaming Transcription

```swift
var options = RASTTOptions.defaults()
options.language = .en

for await partial in RunAnywhere.transcribeStream(audio: audioStream, options: options) {
    if partial.isFinal {
        print("Final: \(partial.text)")
    } else {
        print("Partial: \(partial.text)")
    }
}
```

#### Unloading

```swift
var unload = RAModelUnloadRequest()
unload.modelID = "whisper-base-onnx"
unload.category = .speechRecognition
_ = await RunAnywhere.unloadModel(unload)
```

### Text-to-Speech (TTS)

#### Loading a Voice

```swift
var req = RAModelLoadRequest()
req.modelID = "piper-en-us-amy"
req.category = .speechSynthesis
req.framework = .onnx
_ = await RunAnywhere.loadModel(req)
```

#### Simple Synthesis

```swift
var options = RATTSOptions.defaults()
options.rate = 1.0
options.pitch = 1.0
options.volume = 0.8

let output = try await RunAnywhere.synthesize(
    "Hello! Welcome to RunAnywhere.",
    options: options
)

// output.audioData contains the synthesized audio
// output.durationMs contains the audio length in ms
```

#### Speak with Automatic Playback

```swift
// Synthesize and play through device speakers
let result = try await RunAnywhere.speak("Hello world")

// With options
var options = RATTSOptions.defaults()
options.rate = 1.2
options.pitch = 1.0
let result = try await RunAnywhere.speak("Hello", options: options)
print("Duration: \(result.output.durationMs) ms")
```

#### Streaming Synthesis

```swift
for await chunk in RunAnywhere.synthesizeStream("Long text to synthesize...") {
    // Process audio chunk as it is generated
    playAudioChunk(chunk.audioData)
}
```

#### Stopping Synthesis

```swift
await RunAnywhere.stopSynthesis()
await RunAnywhere.stopSpeaking()
```

### Voice Activity Detection (VAD)

#### Detection

```swift
// Single buffer
var opts = RAVADOptions()
opts.sampleRate = 16000
opts.energyThreshold = 0.5

let samples: Data = // Float32 PCM at 16 kHz mono
let result = try await RunAnywhere.detectVoiceActivity(samples, options: opts)
if result.isSpeech {
    print("Speech detected (confidence: \(result.confidence))")
}
```

#### Streaming Detection

```swift
// Stream VAD over a chunked AsyncStream<Data>
for await vadResult in RunAnywhere.streamVAD(audio: audioStream) {
    if vadResult.isSpeech { handleSpeechFrame(vadResult) }
}
```

#### Reset

```swift
try await RunAnywhere.resetVAD()
```

## API Reference

### ONNX Module

```swift
public enum ONNX {
    /// Module version
    public static let version = "2.0.0"

    /// Underlying ONNX Runtime version
    public static let onnxRuntimeVersion = RAVersions.onnxRuntimeIOS // 1.24.3

    /// Register the ONNX backend with the C++ service registry.
    /// Registers the generic ONNX module (embeddings + Silero VAD) and the
    /// Sherpa-ONNX engine plugin (STT: Whisper / Zipformer / Paraformer,
    /// TTS: Piper / VITS) so `framework == .sherpa` resolves through the
    /// unified C++ plugin router.
    @MainActor
    public static func register(priority: Int = 100)

    /// Unregister the ONNX backend (also unregisters the Sherpa-ONNX plugin)
    @MainActor
    public static func unregister()

    /// Trigger registration via property access (auto-registration helper)
    public static let autoRegister: Void
}
```

`ONNX` is a thin `public enum` namespace. Model-to-backend routing (STT / TTS / VAD) is performed by the C++ plugin registry (`rac_plugin_find` / `rac_plugin_find_for_engine`) using the proto-typed `RAInferenceFramework` / `RAModelCategory` tables — there are no Swift-side `canHandleSTT` / `canHandleTTS` / `canHandleVAD` methods or `capabilities` set.

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

1. Ensure the model is downloaded: check `RAModelInfo.isDownloaded`
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
