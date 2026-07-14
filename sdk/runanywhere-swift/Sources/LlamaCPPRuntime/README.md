# LlamaCPPRuntime Module

The LlamaCPPRuntime module provides large language model (LLM) text generation capabilities for the RunAnywhere Swift SDK using llama.cpp with GGUF models and Metal acceleration.

## Overview

This module enables on-device text generation with support for:

- GGUF model format (Llama, Mistral, Phi, Qwen, and other llama.cpp-compatible models)
- Streaming and non-streaming generation
- Metal GPU acceleration on Apple Silicon
- Configurable generation parameters (temperature, top-p, max tokens)
- System prompts and structured output

## Requirements

| Platform | Minimum Version |
|----------|-----------------|
| iOS      | 17.5+           |
| macOS    | 14.5+           |

The module requires the `RABackendLlamaCPP.xcframework` binary, which is automatically included when you add the SDK as a dependency.

## Installation

The LlamaCPPRuntime module is included in the RunAnywhere SDK. Add it to your target:

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.20.10")
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

### Xcode

1. Go to **File > Add Package Dependencies...**
2. Enter: `https://github.com/RunanywhereAI/runanywhere-sdks`
3. Select version and add `RunAnywhereLlamaCPP` to your target

## Usage

### Registration

Register the module at app startup before using LLM capabilities:

```swift
import RunAnywhere
import LlamaCPPRuntime

@main
struct MyApp: App {
    init() {
        Task { @MainActor in
            LlamaCPP.register()

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

### Loading a Model

```swift
// Load a GGUF model via the canonical proto request
var req = RAModelLoadRequest()
req.modelID = "llama-3.2-1b-instruct-q4"
req.category = .language
req.framework = .llamaCpp
let loaded = await RunAnywhere.loadModel(req)
print("Loaded: \(loaded.resolvedPath)")
```

### Text Generation

```swift
// Simple generation
var req = RALLMGenerateRequest()
req.prompt = "What is the capital of France?"
let result = try await RunAnywhere.generate(req)
print(result.text)

// Generation with options and metrics
var detailed = RALLMGenerateRequest()
detailed.prompt = "Explain quantum computing in simple terms"
detailed.options.maxTokens = 200
detailed.options.temperature = 0.7
detailed.options.systemPrompt = "You are a helpful assistant."

let output = try await RunAnywhere.generate(detailed)
print("Response: \(output.text)")
print("Tokens used: \(output.outputTokens)")
print("Speed: \(output.tokensPerSecond) tok/s")
```

### Streaming Generation

```swift
var req = RALLMGenerateRequest()
req.prompt = "Write a short poem about technology"
req.options.maxTokens = 150

for try await event in try await RunAnywhere.generateStream(req) {
    if event.eventKind == .token {
        print(event.token, terminator: "")
    }
}
```

### Structured Output

```swift
struct QuizQuestion: Generatable {
    let question: String
    let options: [String]
    let correctAnswer: Int

    static var jsonSchema: String {
        """
        {
          "type": "object",
          "properties": {
            "question": { "type": "string" },
            "options": { "type": "array", "items": { "type": "string" } },
            "correctAnswer": { "type": "integer" }
          },
          "required": ["question", "options", "correctAnswer"]
        }
        """
    }
}

let quiz: QuizQuestion = try await RunAnywhere.generateStructured(
    QuizQuestion.self,
    prompt: "Create a quiz question about Swift programming"
)
```

### Unloading

```swift
var unload = RAModelUnloadRequest()
unload.modelID = "llama-3.2-1b-instruct-q4"
unload.category = .language
_ = await RunAnywhere.unloadModel(unload)
```

## API Reference

### LlamaCPP Module

```swift
public enum LlamaCPP {
    /// Module version
    public static let version = "2.0.0"

    /// Underlying llama.cpp library version
    public static let llamaCppVersion = "b7199"

    /// Register the module with the C++ service registry.
    /// The unified llama.cpp plugin publishes a single vtable that fills
    /// both LLM and VLM slots, so this single call covers both modalities.
    @MainActor
    public static func register(priority: Int = 100)

    /// Unregister the module
    public static func unregister()

    /// Trigger registration via property access (auto-registration helper)
    public static let autoRegister: Void
}
```

`LlamaCPP` is a thin `public enum` namespace. Routing between models and the LlamaCPP backend is done by the C++ plugin router (`rac_router_*`) using the proto-typed `RAInferenceFramework` / `RAModelCategory` tables — there is no Swift-side `canHandle(modelId:)` or `capabilities` set.

### Model Compatibility

The LlamaCPP module handles models with the `.gguf` file extension. Compatible model families include:

- Llama (1B, 3B, 7B, etc.)
- Mistral
- Phi
- Qwen
- DeepSeek
- Other llama.cpp-compatible architectures

### Generation Options

Key options for LLM generation:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `maxTokens` | Int | 100 | Maximum tokens to generate |
| `temperature` | Float | 0.8 | Sampling temperature (0.0 - 2.0) |
| `topP` | Float | 1.0 | Top-p sampling parameter |
| `stopSequences` | [String] | [] | Stop generation at these sequences |
| `systemPrompt` | String? | nil | System prompt for generation |

## Architecture

The module follows a thin wrapper pattern:

```
LlamaCPP.swift (Swift wrapper)
       |
LlamaCPPBackend (C headers)
       |
RABackendLlamaCPP.xcframework (C++ implementation)
       |
llama.cpp (Core inference engine)
```

The Swift code registers the backend with the C++ service registry, which handles all model loading and inference operations internally.

## Performance

Typical performance on Apple Silicon:

| Device | Model | Tokens/sec |
|--------|-------|------------|
| iPhone 15 Pro | Llama 3.2 1B Q4 | 25-35 |
| iPhone 15 Pro | Llama 3.2 3B Q4 | 15-20 |
| M1 MacBook | Llama 3.2 1B Q4 | 40-50 |
| M1 MacBook | Llama 3.2 7B Q4 | 20-30 |

Performance varies based on model size, quantization, context length, and device thermal state.

## Troubleshooting

### Model Load Fails

1. Ensure the model is downloaded: check `RAModelInfo.isDownloaded`
2. Verify the model format is GGUF
3. Check available memory (large models require significant RAM)

### Slow Generation

1. Use smaller quantization (Q4 vs Q8)
2. Reduce context length
3. Ensure device is not thermally throttled

### Registration Not Working

1. Ensure `register()` is called on the main actor
2. Call `register()` before `RunAnywhere.initialize()`
3. Check for registration errors in logs

## License

Copyright 2025 RunAnywhere AI. All rights reserved.
