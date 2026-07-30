# RunAnywhere Swift SDK

Run large language models, speech recognition, text-to-speech, and voice agents directly on iPhone, iPad, and Mac — with low latency and on-device privacy. The Swift SDK provides a unified API over pluggable backends (llama.cpp, ONNX, Apple MLX) so you can ship AI features without sending user data to the cloud for inference.

[![Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://github.com/RunanywhereAI/runanywhere-sdks)
[![Version](https://img.shields.io/badge/version-0.20.11-blue.svg)](https://github.com/RunanywhereAI/runanywhere-sdks/releases)
[![Platform](https://img.shields.io/badge/Platform-iOS%2017.5%2B%20%7C%20macOS%2014.5%2B-lightgrey)](https://developer.apple.com)
[![License: RunAnywhere](https://img.shields.io/badge/License-RunAnywhere-blue.svg)](../../LICENSE)

---

## Requirements

| Requirement | Minimum |
|-------------|---------|
| iOS | 17.5+ |
| macOS | 14.5+ |
| Swift | 6.2 |
| Xcode | 26+ |

---

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies…** and enter:

```
https://github.com/RunanywhereAI/runanywhere-sdks
```

Select version **`0.20.11`** (or `from: "0.20.11"`), then add the products you need. Resolve against the newest tag on the [Releases](https://github.com/RunanywhereAI/runanywhere-sdks/releases) page if `0.20.11` binary assets are not published yet.

| Product | Required | Capabilities |
|---------|----------|--------------|
| `RunAnywhere` | Yes | Core SDK, model lifecycle, events |
| `RunAnywhereLlamaCPP` | For LLM/VLM | GGUF models via llama.cpp + Metal |
| `RunAnywhereONNX` | For STT/TTS/VAD | Whisper, Piper, Sherpa-ONNX |
| `RunAnywhereMLX` | For MLX models | Apple MLX LLM, VLM, STT, TTS |

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.20.11")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "RunAnywhere", package: "runanywhere-sdks"),
            .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks"),
            .product(name: "RunAnywhereONNX", package: "runanywhere-sdks"),
        ]
    )
]
```

---

## Quick Start

```swift
import RunAnywhere
import LlamaCPPRuntime

@main
struct MyApp: App {
    init() {
        Task { @MainActor in
            // 1. Register the LLM backend
            LlamaCPP.register()

            // 2. Initialize the SDK
            try RunAnywhere.initialize(
                apiKey: "<YOUR_API_KEY>",
                baseURL: "https://api.runanywhere.ai",
                environment: .production
            )

            // 3. Load a model
            var loadRequest = RAModelLoadRequest()
            loadRequest.modelID = "llama-3.2-1b-instruct-q4"
            loadRequest.category = .language
            let loadResult = await RunAnywhere.loadModel(loadRequest)
            guard loadResult.success else { return }

            // 4. Generate text
            var request = RALLMGenerateRequest()
            request.prompt = "What is the capital of France?"
            var options = RALLMGenerationOptions.defaults()
            options.maxTokens = 128
            request.options = options

            let result = try await RunAnywhere.generate(request)
            print(result.text)
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

For development without an API key, call `try RunAnywhere.initialize()` with the default `.development` environment.

---

## Capabilities

| Capability | Backends | Model formats | Notes |
|------------|----------|---------------|-------|
| **LLM** | `RunAnywhereLlamaCPP`, `RunAnywhereMLX` | GGUF (`.gguf`) | Streaming, structured output, tool calling |
| **STT** | `RunAnywhereONNX`, `RunAnywhereMLX` | ONNX (`.onnx`, `.ort`) | Whisper, Sherpa streaming |
| **TTS** | `RunAnywhereONNX`, `RunAnywhereMLX` | ONNX, Piper voices | System TTS also available |
| **VLM** | `RunAnywhereLlamaCPP`, `RunAnywhereMLX` | GGUF multimodal | Image + text inference |
| **Voice** | Core + STT + LLM + TTS backends | — | VAD → STT → LLM → TTS pipeline |
| **NPU** | — | — | Not available on Apple platforms via this SDK |

Register each backend module before using its capabilities:

```swift
LlamaCPP.register()  // LLM + VLM
ONNX.register()      // STT + TTS + VAD (requires RunAnywhereONNX)
MLX.register()       // MLX modalities (requires RunAnywhereMLX)
```

### Supported model formats

| Format | Extension | Backend | Use case |
|--------|-----------|---------|----------|
| GGUF | `.gguf` | llama.cpp | LLM, VLM text generation |
| ONNX | `.onnx` | ONNX Runtime | STT, TTS, VAD |
| ORT | `.ort` | ONNX Runtime | Optimized STT/TTS |

Models are discovered through the RunAnywhere catalog, downloaded on-device, and managed via `RunAnywhere.loadModel(_:)`, `RunAnywhere.downloadModel(_:onProgress:)`, and related lifecycle APIs.

### Connect (trusted LAN)

`ConnectSession` publishes or joins a language-model session on the local network. Commons owns role policy and protocol validation; this SDK owns Bonjour and the framed TCP adapter.

| Role | Platforms |
|------|-----------|
| **Host** | macOS only |
| **Client** | iOS and iPadOS (Android clients use the Kotlin SDK) |

- Service type: `_runanywhere-connect._tcp`
- Hosting is app-scoped: the macOS app must keep the model loaded and the process alive
- Clients adopt the **one model the host has selected** — no client-side model download for hosted chat
- Trust model: **trusted LAN only** (no TLS/pairing in this release). Runtime admission follows commons `platformPolicy()`; compile-time `#if os` guards only gate Apple APIs that do not exist on the other Apple platforms
- React Native, Flutter, Web, and Electron are **not** Connect participants in this release

See the iOS/macOS example under [`examples/ios/RunAnywhereAI/`](../../examples/ios/RunAnywhereAI/) (`ConnectHostManagementView`, model-selection Connect section).

---

## Documentation and Examples

| Resource | Link |
|----------|------|
| **Docs** | [docs.runanywhere.ai/swift/introduction](https://docs.runanywhere.ai/swift/introduction) |
| **Example app** | [`examples/ios/RunAnywhereAI/`](../../examples/ios/RunAnywhereAI/) |
| **Contributing / local build** | [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) |

---

## Privacy

Inference runs on-device after models are downloaded. Network access is used for SDK authentication, model downloads, and optional analytics — prompts, responses, and audio are not sent to the cloud for inference by default.

Compliance with regulations such as HIPAA or GDPR depends on your deployment, data handling practices, and backend configuration. Review your architecture and consult legal counsel for regulated use cases.

---

## Support

- **Documentation:** [docs.runanywhere.ai](https://docs.runanywhere.ai)
- **Discord:** [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd)
- **Email:** founders@runanywhere.ai
- **Issues:** [github.com/RunanywhereAI/runanywhere-sdks/issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)

---

## License

Copyright © 2026 RunAnywhere AI. All rights reserved.

This SDK is distributed under the [RunAnywhere License](../../LICENSE). For commercial licensing inquiries, contact founders@runanywhere.ai.
