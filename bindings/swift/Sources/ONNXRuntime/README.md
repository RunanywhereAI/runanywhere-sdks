# RunAnywhereONNX

**ONNX/Sherpa backend for the RunAnywhere Swift SDK** — on-device STT, TTS, and VAD on Apple platforms.

---

## Installation

Add the Swift package and include the `RunAnywhereONNX` product (pin `0.20.17`):

```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", exact: "0.20.17"),
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

See the [Swift SDK README](../../README.md) for Xcode setup and API keys.

---

## Usage

```swift
import RunAnywhere
import ONNXRuntime

@MainActor
func bootstrap() throws {
    ONNX.register()
    try RunAnywhere.initialize(
        apiKey: "<YOUR_API_KEY>",
        baseUrl: "https://api.runanywhere.ai",
        environment: .production
    )
}

// Load models and transcribe via RunAnywhere core APIs
let output = try await RunAnywhere.stt.transcribe(.wav(audioData))
print(output.text)
```

See the [Swift SDK README](../../README.md) for TTS, VAD, and voice-agent flows.

---

## Requirements

- iOS 17.5+ / macOS 14.5+

---

## Support

- [Swift SDK documentation](../../README.md)
- [Discord](https://discord.gg/N359FBbDVd)
- [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

---

## License

RunAnywhere License. See [LICENSE](../../../../LICENSE).
