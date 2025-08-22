# LLMSwift Module

Swift Package module providing LLM.swift integration for RunAnywhere SDK.

## Features

- GGUF/GGML model support
- Multiple template formats (ChatML, Alpaca, Llama, Mistral, Gemma)
- Hardware optimization
- Streaming and non-streaming generation
- Quantization support
- Automatic template detection based on model name

## Requirements

- iOS 16.0+ / macOS 13.0+ / tvOS 16.0+ / watchOS 9.0+
- LLM.swift framework
- RunAnywhereSDK

## Installation

### Swift Package Manager

Add the package to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(path: "path/to/sdk/runanywhere-swift/Modules/LLMSwift")
]
```

Then add to your target:

```swift
.target(
    name: "YourApp",
    dependencies: ["LLMSwift"]
)
```

## Usage

### Basic Setup

```swift
import LLMSwift
import RunAnywhereSDK

// Register the adapter
RunAnywhereSDK.shared.registerFrameworkAdapter(LLMSwiftAdapter())
```

### Supported Models

The module supports models in GGUF and GGML formats with various quantization levels:

- Q2_K, Q3_K_S, Q3_K_M, Q3_K_L
- Q4_0, Q4_1, Q4_K_S, Q4_K_M
- Q5_0, Q5_1, Q5_K_S, Q5_K_M
- Q6_K, Q8_0
- IQ2_XXS, IQ2_XS, IQ3_S, IQ3_XXS
- IQ4_NL, IQ4_XS

### Template Detection

The module automatically detects the appropriate template based on the model filename:

- **Qwen models**: ChatML template
- **Alpaca models**: Alpaca template
- **Llama models**: Llama template
- **Mistral models**: Mistral template (no system prompt support)
- **Gemma models**: Gemma template (no system prompt support)
- **Default**: ChatML template

### Hardware Configuration

The adapter automatically optimizes hardware configuration based on:

- Model size
- Available GPU/CPU resources
- Memory constraints

Example optimal configuration:

```swift
let config = adapter.optimalConfiguration(for: modelInfo)
// Returns configuration with:
// - GPU acceleration for models < 4GB (if available)
// - CPU fallback
// - Balanced memory mode
// - 4 threads
// - Quantization enabled
```

## API Reference

### LLMSwiftAdapter

Main adapter implementing `UnifiedFrameworkAdapter`:

```swift
public class LLMSwiftAdapter: UnifiedFrameworkAdapter {
    public let framework: LLMFramework = .llamaCpp
    public let supportedModalities: Set<FrameworkModality> = [.textToText]
    public let supportedFormats: [ModelFormat] = [.gguf, .ggml]

    public init()
    public func canHandle(model: ModelInfo) -> Bool
    public func createService(for modality: FrameworkModality) -> Any?
    public func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any
    public func configure(with hardware: HardwareConfiguration) async
    public func estimateMemoryUsage(for model: ModelInfo) -> Int64
    public func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration
}
```

### LLMSwiftService

Service implementation for text generation:

```swift
public class LLMSwiftService: LLMService {
    public var isReady: Bool
    public var modelInfo: LoadedModelInfo?

    public func initialize(modelPath: String) async throws
    public func generate(prompt: String, options: RunAnywhereGenerationOptions) async throws -> String
    public func streamGenerate(prompt: String, options: RunAnywhereGenerationOptions, onToken: @escaping (String) -> Void) async throws
    public func cleanup() async
    public func getModelMemoryUsage() async throws -> Int64
}
```

### LLMSwiftTemplateResolver

Utility for template resolution:

```swift
public struct LLMSwiftTemplateResolver {
    public static func determineTemplate(from modelPath: String, systemPrompt: String?) -> Template
}
```

### LLMSwiftError

Error types for LLM operations:

```swift
public enum LLMSwiftError: LocalizedError {
    case modelLoadFailed
    case initializationFailed
    case generationFailed(String)
    case templateResolutionFailed(String)
}
```

## Logging

The module uses the Apple unified logging system with subsystem `com.runanywhere.llmswift`.

Categories:
- `LLMSwiftService` - Service operations
- `TemplateResolver` - Template detection

## Performance Considerations

- Models are loaded with a default context length of 2048 tokens
- Conversation history is limited to 6 turns to prevent context overflow
- Generation includes a 60-second timeout protection
- Memory usage is estimated as file size + 20% overhead for processing

## License

See the main SDK license file for details.
