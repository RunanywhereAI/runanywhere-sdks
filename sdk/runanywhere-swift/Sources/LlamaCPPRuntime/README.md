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
| iOS      | 17.0+           |
| macOS    | 14.0+           |

The module requires the `RABackendLlamaCPP.xcframework` binary, which is automatically included when you add the SDK as a dependency.

## Installation

The LlamaCPPRuntime module is included in the RunAnywhere SDK. Add it to your target:

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
// Load a GGUF model by ID
try await RunAnywhere.loadModel("llama-3.2-1b-instruct-q4")

// Check if model is loaded
let isLoaded = await RunAnywhere.isModelLoaded
```

### Text Generation

```swift
// Simple chat
let response = try await RunAnywhere.chat("What is the capital of France?")
print(response)

// Generation with options and metrics
let result = try await RunAnywhere.generate(
    "Explain quantum computing in simple terms",
    options: LLMGenerationOptions(
        maxTokens: 200,
        temperature: 0.7,
        systemPrompt: "You are a helpful assistant."
    )
)

print("Response: \(result.text)")
print("Tokens used: \(result.tokensUsed)")
print("Speed: \(result.tokensPerSecond) tok/s")
```

### Streaming Generation

```swift
let result = try await RunAnywhere.generateStream(
    "Write a short poem about technology",
    options: LLMGenerationOptions(maxTokens: 150)
)

// Display tokens in real-time
for try await token in result.stream {
    print(token, terminator: "")
}

// Get complete metrics after streaming finishes
let metrics = try await result.result.value
print("\nSpeed: \(metrics.tokensPerSecond) tok/s")
print("Total tokens: \(metrics.tokensUsed)")
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
try await RunAnywhere.unloadModel()
```

## API Reference

### LlamaCPP Module

```swift
public enum LlamaCPP: RunAnywhereModule {
    /// Module identifier
    public static let moduleId = "llamacpp"

    /// Human-readable module name
    public static let moduleName = "LlamaCPP"

    /// Capabilities provided by this module
    public static let capabilities: Set<SDKComponent> = [.llm]

    /// Default registration priority
    public static let defaultPriority: Int = 100

    /// Inference framework used
    public static let inferenceFramework: InferenceFramework = .llamaCpp

    /// Module version
    public static let version = "2.0.0"

    /// Underlying llama.cpp library version
    public static let llamaCppVersion = "b7199"

    /// Register the module with the service registry
    @MainActor
    public static func register(priority: Int = 100)

    /// Unregister the module
    public static func unregister()

    /// Check if the module can handle a given model
    public static func canHandle(modelId: String?) -> Bool
}
```

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

1. Ensure the model is downloaded: check `ModelInfo.isDownloaded`
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
