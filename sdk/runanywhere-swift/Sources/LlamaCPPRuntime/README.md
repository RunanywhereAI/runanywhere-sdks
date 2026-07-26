# RunAnywhereLlamaCPP

**Llama.cpp LLM backend for the RunAnywhere Swift SDK** — GGUF text generation with Metal acceleration on Apple platforms.

---

## Installation

Add the Swift package and include the `RunAnywhereLlamaCPP` product (pin `0.20.10`):

```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", exact: "0.20.10"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "RunAnywhere", package: "runanywhere-sdks"),
            .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks"),
        ]
    )
]
```

See the [Swift SDK README](../../README.md) for Xcode setup and API keys.

---

## Usage

```swift
import RunAnywhere
import LlamaCPPRuntime

@MainActor
func bootstrap() throws {
    LlamaCPP.register()
    try RunAnywhere.initialize(
        apiKey: "<YOUR_API_KEY>",
        baseURL: "https://api.runanywhere.ai",
        environment: .production
    )
}

// Load models and generate via RunAnywhere core APIs
var req = RALLMGenerateRequest()
req.prompt = "What is on-device AI?"
let result = try await RunAnywhere.generate(req)
```

See the [Swift SDK README](../../README.md) for model registration, streaming, and VLM.

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
