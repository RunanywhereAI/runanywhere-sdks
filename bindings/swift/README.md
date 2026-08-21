# RunAnywhere Swift SDK

Run large language models, speech recognition, text-to-speech, and voice agents directly on iPhone, iPad, and Mac — with low latency and on-device privacy. The Swift SDK provides a unified API over pluggable backends (llama.cpp, ONNX, Apple MLX) so you can ship AI features without sending user data to the cloud for inference.

[![Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://github.com/RunanywhereAI/runanywhere-sdks)
[![Version](https://img.shields.io/badge/version-0.20.25-blue.svg)](https://github.com/RunanywhereAI/runanywhere-sdks/releases)
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
https://github.com/RunanywhereAI/runanywhere-swift.git
```

Consume the Swift **distribution repo**, never this monorepo. This repo's tags do not compile as a Swift package: the generated protobuf Swift sources are codegen output and are no longer committed, so resolving the monorepo URL by version fails with hundreds of "cannot find type" errors. The distribution repo is generated with those sources and declares the same binary targets, with the same checksums, against the same release assets.

Select version **`0.20.25`** (or `from: "0.20.25"`), then add the products you need. Resolve against the newest tag on the [Releases](https://github.com/RunanywhereAI/runanywhere-sdks/releases) page if `0.20.25` binary assets are not published yet.

| Product | Required | Capabilities |
|---------|----------|--------------|
| `RunAnywhere` | Yes | Core SDK, model lifecycle, events |
| `RunAnywhereLlamaCPP` | For LLM/VLM | GGUF models via llama.cpp + Metal |
| `RunAnywhereONNX` | For STT/TTS/VAD | Whisper, Piper, Sherpa-ONNX |
| `RunAnywhereMLX` | For MLX models | Apple MLX LLM, VLM, STT, TTS |

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-swift.git", from: "0.20.25")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "RunAnywhere", package: "runanywhere-swift"),
            .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-swift"),
            .product(name: "RunAnywhereONNX", package: "runanywhere-swift"),
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
                baseUrl: "https://api.runanywhere.ai",
                environment: .production
            )

            // 3. Generate text. The model auto-loads (and downloads when
            //    absent); call `RunAnywhere.models.load(id:)` first if you
            //    want to control when that cost is paid.
            let result = try await RunAnywhere.llm.generate(
                prompt: "What is the capital of France?",
                options: LlmOptions(model: "llama-3.2-1b-instruct-q4", maxOutputTokens: 128)
            )
            print(result.text)
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

For development without an API key, call `try RunAnywhere.initialize(environment: .development)`.

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

Models are discovered through the RunAnywhere catalog, downloaded on-device, and managed via `RunAnywhere.models.load(id:)`, `RunAnywhere.models.download(id:)`, and the rest of the `models` namespace.

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

See the iOS/macOS example app in [RunanywhereAI/runanywhere-ios](https://github.com/RunanywhereAI/runanywhere-ios) (`ConnectHostManagementView`, model-selection Connect section).

---

## Documentation and Examples

| Resource | Link |
|----------|------|
| **Docs** | [docs.runanywhere.ai/swift/introduction](https://docs.runanywhere.ai/swift/introduction) |
| **Minimal example** | [`example/`](example/) — SwiftPM harness, builds the SDK from local source |
| **Full example app** | [RunanywhereAI/runanywhere-ios](https://github.com/RunanywhereAI/runanywhere-ios) |
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
