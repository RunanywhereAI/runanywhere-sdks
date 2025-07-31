# Sample App Framework Implementation Plan

## Overview

This document outlines how the RunAnywhereAI iOS sample app will consume the RunAnywhere SDK and implement framework-specific adapters for various on-device language models. The sample app serves as both a demonstration of SDK capabilities and a reference implementation for developers.

## Architecture Overview

### Updated Sample App Responsibilities (With Enhanced SDK)

1. **Advanced Framework Demonstrations**
   - Showcase advanced framework features not in SDK modules
   - Demonstrate custom framework adapter creation
   - Show performance optimization techniques
   - Example: MLX with Metal Performance Shaders, TFLite with custom delegates

2. **UI & User Experience**
   - Provide comprehensive UI for model selection and testing
   - Display progress, errors, and performance metrics
   - Demonstrate best practices for SDK integration
   - Show modular SDK usage patterns

3. **Extension Examples**
   - Custom model provider implementations
   - Advanced authentication patterns
   - Custom routing policies
   - Performance monitoring extensions

### Phase 1 Architectural Changes

The implementation has been restructured to ensure clean separation between SDK and sample app:

1. **SDK Components (Removed from Sample App)**:
   - Hardware detection (iOSHardwareDetector) - belongs in SDK
   - Protocol definitions (FrameworkAdapter, LLMService, etc.) - come from SDK
   - Model lifecycle management - handled by SDK
   - Progress tracking infrastructure - provided by SDK
   - Memory management system - SDK responsibility

2. **Sample App Components (What Remains)**:
   - Framework-specific service wrappers (CoreMLService, etc.)
   - Authentication UI and keychain extensions
   - Custom framework adapter implementations
   - UI components and view models
   - Integration examples

3. **Clean API Consumption**:
   - UnifiedLLMServiceSDK only calls SDK APIs
   - No implementation of SDK functionality
   - Placeholder code where SDK will be integrated
   - Complete removal of legacy service dependencies

### SDK Integration Points

```swift
// Core SDK (always included)
import RunAnywhere

// Import optional modules for built-in functionality
import RunAnywhereHuggingFace  // For HuggingFace models
import RunAnywhereCorML        // For Core ML support
import RunAnywhereGGUF         // For GGUF models
import RunAnywhereONNX         // For ONNX support
import RunAnywhereProviders    // For model providers

// SDK provides core functionality with defaults
let sdk = RunAnywhereSDK.shared

// Initialize with API key
try await sdk.initialize(apiKey: "your-api-key")

// Option 1: Use built-in adapters from modules
// (Modules auto-register their adapters when imported)

// Option 2: Register custom adapters for advanced features
sdk.registerFrameworkAdapter(AdvancedMLXAdapter())     // Custom MLX with MPS
sdk.registerFrameworkAdapter(CustomTFLiteAdapter())    // TFLite with custom delegates

// Option 3: Override built-in providers with custom ones
sdk.modelRegistry.registerProvider(
    CustomHuggingFaceProvider(),  // Extends built-in with custom features
    replaceExisting: true
)

// Use SDK for model operations
try await sdk.loadModel("llama-3.2-1b", preferredFramework: .mlx)
let result = try await sdk.generate("Hello, world!")
```

## Implementation Structure

### Directory Organization

```
examples/ios/RunAnywhereAI/
├── Services/
│   ├── Frameworks/              # Framework-specific implementations
│   │   ├── CoreML/
│   │   │   ├── CoreMLService.swift
│   │   │   ├── CoreMLModelAdapter.swift
│   │   │   └── CoreMLTokenizerAdapter.swift
│   │   ├── TFLite/
│   │   │   ├── TFLiteService.swift
│   │   │   └── TFLiteDelegate.swift
│   │   ├── MLX/
│   │   │   ├── MLXService.swift
│   │   │   └── MLXModelWrapper.swift
│   │   ├── SwiftTransformers/
│   │   ├── ONNX/
│   │   ├── ExecuTorch/
│   │   ├── LlamaCpp/
│   │   ├── FoundationModels/
│   │   ├── PicoLLM/
│   │   └── MLC/
│   ├── Adapters/               # SDK protocol implementations
│   │   ├── FrameworkAdapterRegistry.swift
│   │   ├── CoreMLFrameworkAdapter.swift
│   │   ├── TFLiteFrameworkAdapter.swift
│   │   └── ... (other adapters)
│   ├── Tokenizers/             # Tokenizer implementations
│   │   ├── BPETokenizer.swift
│   │   ├── SentencePieceTokenizer.swift
│   │   └── TokenizerAdapters/
│   ├── Providers/              # Model provider integrations
│   │   ├── HuggingFaceProvider.swift
│   │   ├── AppleModelsProvider.swift
│   │   └── KaggleProvider.swift
│   └── UnifiedLLMService.swift # Orchestrator using SDK
├── Views/
│   ├── ModelSelectionView.swift
│   ├── GenerationView.swift
│   ├── ProgressView.swift
│   └── SettingsView.swift
└── ViewModels/
    ├── ModelViewModel.swift
    └── GenerationViewModel.swift
```

## SDK Extension Examples in Sample App

### Custom Hardware Detector (Advanced Example)

**Note:** The SDK includes `DefaultiOSHardwareDetector` and `DefaultAndroidHardwareDetector` as part of the core module. This example shows how to create a custom implementation with additional capabilities for the sample app.

```swift
// Services/Hardware/AdvancedHardwareDetector.swift
import RunAnywhere
import Metal
import CoreML

// Extends the SDK's default with custom features
class AdvancedHardwareDetector: DefaultiOSHardwareDetector {
    override func detectCapabilities() -> DeviceCapabilities {
        return DeviceCapabilities(
            totalMemory: ProcessInfo.processInfo.physicalMemory,
            availableMemory: getAvailableMemory(),
            hasNeuralEngine: detectNeuralEngine(),
            hasGPU: detectGPU(),
            processorCount: ProcessInfo.processInfo.processorCount
        )
    }

    func detectNeuralEngine() -> Bool {
        // Platform-specific Neural Engine detection
        if #available(iOS 14.0, *) {
            // Check for Neural Engine availability
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            // Test if Neural Engine is available
            return true // Simplified - actual implementation would test
        }
        return false
    }

    func detectGPU() -> Bool {
        return MTLCreateSystemDefaultDevice() != nil
    }

    func getAvailableMemory() -> Int64 {
        // Platform-specific memory detection
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}
```

### Custom Model Provider Example

**Note:** The SDK includes built-in providers via optional modules:
- `RunAnywhereHuggingFace` - HuggingFace integration
- `RunAnywhereProviders` - Kaggle, Microsoft, Apple providers
- `RunAnywhereSystemModels` - System model providers

This example shows how to create a custom provider or extend existing ones.

```swift
// Services/Providers/CustomHuggingFaceProvider.swift
import RunAnywhere
import RunAnywhereHuggingFace

// Extends the SDK's built-in provider with custom features
class CustomHuggingFaceProvider: HuggingFaceProvider {
    // Add custom filtering, caching, or API features

    func discoverModels() async throws -> [ModelInfo] {
        // Query HuggingFace API for compatible models
        guard let token = authService.token else {
            throw ProviderError.authenticationRequired
        }

        // API implementation
        let models = try await queryHuggingFaceAPI(token: token)
        return models.compactMap { convertToModelInfo($0) }
    }

    func downloadModel(_ model: ModelInfo) async throws -> URL {
        // Use SDK's download manager with HF authentication
        return try await downloadWithAuth(model)
    }

    func requiresAuthentication() -> Bool {
        return true
    }
}

// Services/Providers/KaggleProvider.swift
class KaggleProvider: ModelProvider {
    let name = "Kaggle"
    private let authService = KaggleAuthService.shared

    func discoverModels() async throws -> [ModelInfo] {
        // Kaggle-specific model discovery
        let credentials = try authService.getCredentials()
        return try await queryKaggleDatasets(credentials)
    }

    func downloadModel(_ model: ModelInfo) async throws -> URL {
        // Kaggle-specific download with authentication
        return try await downloadFromKaggle(model)
    }

    func requiresAuthentication() -> Bool {
        return true
    }
}
```

### Metadata Extractor Implementations

**Note:** These implement the SDK's `MetadataExtractorProtocol`. Each extractor handles format-specific metadata extraction logic.

```swift
// Services/Metadata/CoreMLMetadataExtractor.swift
import RunAnywhere
import CoreML

class CoreMLMetadataExtractor: MetadataExtractorProtocol {
    let supportedFormats: [ModelFormat] = [.mlmodel, .mlpackage]

    func extractMetadata(from url: URL) async throws -> ModelMetadata {
        var metadata = ModelMetadata()

        if url.pathExtension == "mlpackage" {
            // Read Metadata.json from mlpackage
            let metadataURL = url.appendingPathComponent("Metadata.json")
            if let data = try? Data(contentsOf: metadataURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                metadata.author = json["author"] as? String
                metadata.description = json["description"] as? String
                metadata.version = json["version"] as? String
            }
        } else {
            // For .mlmodel, compile and inspect
            if let model = try? MLModel(contentsOf: url) {
                let description = model.modelDescription
                metadata.inputShapes = description.inputDescriptionsByName.mapValues { desc in
                    desc.multiArrayConstraint?.shape.map { $0.intValue } ?? []
                }
                metadata.outputShapes = description.outputDescriptionsByName.mapValues { desc in
                    desc.multiArrayConstraint?.shape.map { $0.intValue } ?? []
                }
            }
        }

        return metadata
    }
}

// Services/Metadata/SafetensorsMetadataExtractor.swift
class SafetensorsMetadataExtractor: MetadataExtractorProtocol {
    let supportedFormats: [ModelFormat] = [.safetensors]

    func extractMetadata(from url: URL) async throws -> ModelMetadata {
        var metadata = ModelMetadata()

        // Read safetensors header
        if let file = try? FileHandle(forReadingFrom: url) {
            defer { try? file.close() }

            // First 8 bytes contain header size
            let headerSizeData = file.readData(ofLength: 8)
            guard headerSizeData.count == 8 else { return metadata }

            let headerSize = headerSizeData.withUnsafeBytes { $0.load(as: UInt64.self) }
            let headerData = file.readData(ofLength: Int(headerSize))

            if let json = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
                // Extract tensor information
                if let tensors = json["tensors"] as? [String: Any] {
                    metadata.tensorCount = tensors.count
                    metadata.parameterCount = calculateParameterCount(from: tensors)
                }

                // Extract model config if present
                if let config = json["__metadata__"] as? [String: Any] {
                    metadata.modelType = config["model_type"] as? String
                    metadata.architecture = config["architecture"] as? String
                }
            }
        }

        return metadata
    }
}
```

### Tokenizer Adapter Implementations

**Note:** These implement the SDK's `TokenizerAdapter` protocol. The SDK manages tokenizer lifecycle and caching, while these adapters provide format-specific implementations.

```swift
// Services/Tokenizers/Adapters/BPETokenizerAdapter.swift
import RunAnywhere

class BPETokenizerAdapter: TokenizerAdapter {
    let format: TokenizerFormat = .bpe

    func createTokenizer(modelPath: URL) throws -> UnifiedTokenizer {
        return try BPETokenizerWrapper(modelPath: modelPath)
    }
}

class BPETokenizerWrapper: UnifiedTokenizer {
    private let tokenizer: GenericBPETokenizer

    init(modelPath: URL) throws {
        self.tokenizer = try GenericBPETokenizer(modelPath: modelPath)
    }

    func encode(_ text: String) -> [Int] {
        return tokenizer.encode(text)
    }

    func decode(_ tokens: [Int]) -> String {
        return tokenizer.decode(tokens)
    }

    var vocabularySize: Int {
        return tokenizer.vocabulary.count
    }
}
```

## Framework-Specific Implementations

### 1. CoreML Framework

```swift
// Services/Frameworks/CoreML/CoreMLService.swift
import CoreML
import RunAnywhere

class CoreMLService: LLMService {
    private var model: MLModel?
    private var modelAdapter: CoreMLModelAdapter?
    private var tokenizerAdapter: TokenizerAdapter?

    // Preserve all existing CoreML logic
    func initialize(modelPath: String) async throws {
        // Existing compilation logic for .mlmodel → .mlmodelc
        // Directory vs file detection
        // Neural Engine configuration
    }

    func generate(prompt: String, options: GenerationOptions) async throws -> String {
        // Existing generation logic with sliding window
        // Context management
        // Token generation loop
    }
}

// Services/Adapters/CoreMLFrameworkAdapter.swift
import RunAnywhere

class CoreMLFrameworkAdapter: FrameworkAdapter {
    let framework: LLMFramework = .coreML
    let supportedFormats: [ModelFormat] = [.mlmodel, .mlpackage]

    func createService() -> LLMService {
        return CoreMLService()
    }

    func canHandle(model: ModelInfo) -> Bool {
        // Check model compatibility
        // Verify hardware requirements
        return supportedFormats.contains(model.format)
    }
}
```

### 2. TensorFlow Lite Framework

```swift
// Services/Frameworks/TFLite/TFLiteService.swift
import TensorFlowLite
import RunAnywhere

class TFLiteService: LLMService {
    private var interpreter: Interpreter?

    // Preserve delegate configuration logic
    private func configureDelegate() -> Delegate? {
        // Complex CoreML/Metal delegate selection
        // Hardware-specific optimization
    }

    func initialize(modelPath: String) async throws {
        // Kaggle authentication check
        // Interpreter initialization
        // Delegate configuration
    }
}
```

### 3. MLX Framework

```swift
// Services/Frameworks/MLX/MLXService.swift
import MLX
import RunAnywhere

class MLXService: LLMService {
    // Preserve A17 Pro/M3+ device checking
    static func isMLXSupported() -> Bool {
        ProcessInfo.processInfo.processorHasARM64E
    }

    func initialize(modelPath: String) async throws {
        guard Self.isMLXSupported() else {
            throw MLXError.deviceNotSupported
        }

        // Handle tar.gz extraction (delegated to SDK)
        // Load multi-file models (config.json, weights.safetensors)
    }
}
```

### 4. Additional Frameworks

Each framework maintains its specific requirements:

- **SwiftTransformers**: Strict input validation (must have 'input_ids')
- **ONNX**: ORTEnv and ORTSession lifecycle management
- **ExecuTorch**: Module pattern for .pte files
- **LlamaCpp**: GGUF/GGML support with quantization
- **FoundationModels**: iOS 18+ system models (no download)
- **PicoLLM**: API key validation, ultra-compressed models
- **MLC**: JIT compilation with caching

## Tokenizer Implementations

### Tokenizer Adapter Pattern

```swift
// Services/Tokenizers/TokenizerAdapters/BPETokenizerAdapter.swift
import RunAnywhere

class BPETokenizerAdapter: UnifiedTokenizer {
    private let tokenizer: GenericBPETokenizer

    init(modelPath: URL) throws {
        self.tokenizer = try GenericBPETokenizer(modelPath: modelPath)
    }

    func encode(_ text: String) -> [Int] {
        return tokenizer.encode(text)
    }

    func decode(_ tokens: [Int]) -> String {
        return tokenizer.decode(tokens)
    }

    var vocabularySize: Int {
        return tokenizer.vocabulary.count
    }
}
```

## Model Provider Integrations

### HuggingFace Provider

```swift
// Services/Providers/HuggingFaceProvider.swift
import RunAnywhere

class HuggingFaceProvider: ModelProvider {
    private let authService = HuggingFaceAuthService.shared

    func discoverModels() async throws -> [ModelInfo] {
        // Query HuggingFace API
        // Filter for compatible models
        // Extract metadata
    }

    func downloadModel(_ model: ModelInfo) async throws -> URL {
        // Use SDK's download manager
        // Handle authentication if needed
    }
}
```

## UI Integration

### Model Selection View

```swift
import SwiftUI
import RunAnywhere

struct ModelSelectionView: View {
    @StateObject private var sdk = RunAnywhereSDK.shared
    @State private var selectedFramework: LLMFramework?
    @State private var availableModels: [ModelInfo] = []

    var body: some View {
        List {
            // Framework selection
            Section("Framework") {
                ForEach(registeredFrameworks, id: \.self) { framework in
                    Button(action: { selectedFramework = framework }) {
                        HStack {
                            Text(framework.displayName)
                            if selectedFramework == framework {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            // Model list from SDK
            Section("Available Models") {
                ForEach(availableModels) { model in
                    ModelRow(model: model, onSelect: {
                        Task {
                            try await sdk.loadModel(
                                model.identifier,
                                preferredFramework: selectedFramework
                            )
                        }
                    })
                }
            }
        }
        .task {
            availableModels = try await sdk.discoverModels()
        }
    }
}
```

## Service Orchestration

### UnifiedLLMServiceSDK (Phase 1 & 2 Implementation)

```swift
// Services/UnifiedLLMServiceSDK.swift
import RunAnywhere
import Combine

@MainActor
class UnifiedLLMServiceSDK: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentModel: ModelInfo?
    @Published var progress: ProgressInfo?
    @Published var availableModels: [ModelInfo] = []
    @Published var currentFramework: LLMFramework?

    // SDK instance will be used when available
    // private let sdk = RunAnywhereSDK.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        Task {
            await initializeSDK()
        }
    }

    private func initializeSDK() async {
        do {
            // Get API key from keychain
            let apiKey = KeychainService.shared.getRunAnywhereAPIKey() ?? "demo-api-key"

            // When SDK is available:
            // try await sdk.initialize(apiKey: apiKey)

            // The SDK will auto-register its built-in components
            // We only need to register our custom framework adapters
            registerFrameworkAdapters()

            // Discover available models
            // availableModels = try await sdk.discoverModels()

        } catch {
            self.error = error
            print("Failed to initialize SDK: \(error)")
        }
    }

    private func registerFrameworkAdapters() {
        // Get all adapters from the registry
        let adapters = FrameworkAdapterRegistry.shared.getAllAdapters()

        // When SDK is available, register each adapter:
        // for adapter in adapters {
        //     sdk.registerFrameworkAdapter(adapter)
        // }

        print("Registered \(adapters.count) framework adapters")
    }

    // Public API methods that purely consume SDK functionality
    func loadModel(_ identifier: String, framework: LLMFramework? = nil) async {
        // try await sdk.loadModel(identifier, preferredFramework: framework)
    }

    func generate(_ prompt: String, options: GenerationOptions = .default) async throws -> String {
        // return try await sdk.generate(prompt, options: options)
        throw NSError(domain: "SDKNotAvailable", code: -1)
    }

    func streamGenerate(_ prompt: String, options: GenerationOptions = .default, onToken: @escaping (String) -> Void) async throws {
        // try await sdk.streamGenerate(prompt, options: options, onToken: onToken)
        throw NSError(domain: "SDKNotAvailable", code: -1)
    }
}
```

## Authentication Services

### Keychain Integration

```swift
// Services/Auth/KeychainService.swift
import RunAnywhere

extension KeychainService {
    // HuggingFace token
    func getHuggingFaceToken() -> String? {
        return try? retrieveAPIKey(for: "huggingface")
    }

    // Kaggle credentials
    func getKaggleCredentials() -> (username: String, key: String)? {
        guard let username = try? retrieve(key: "kaggle_username"),
              let key = try? retrieveAPIKey(for: "kaggle") else {
            return nil
        }
        return (username, key)
    }

    // Picovoice API key
    func getPicovoiceAPIKey() -> String? {
        return try? retrieveAPIKey(for: "picovoice")
    }
}
```

## Build Configuration

### Package Dependencies

```swift
// Package.swift updates for sample app
dependencies: [
    // SDK
    .package(path: "../../../sdk/runanywhere-swift"),

    // Framework-specific
    .package(url: "https://github.com/apple/swift-transformers", from: "0.1.22"),
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.25.0"),
    // ... other framework dependencies
]
```

### CocoaPods (for TensorFlow Lite)

```ruby
# Podfile
platform :ios, '15.0'

target 'RunAnywhereAI' do
  use_frameworks!

  # TensorFlow Lite
  pod 'TensorFlowLiteSwift', '~> 2.14.0'
  pod 'TensorFlowLiteSwift/CoreML', '~> 2.14.0'
  pod 'TensorFlowLiteSwift/Metal', '~> 2.14.0'

  # Other dependencies
  pod 'ZIPFoundation', '~> 0.9'
end
```

## Testing Strategy

### Framework Adapter Tests

```swift
import XCTest
import RunAnywhere
@testable import RunAnywhereAI

class FrameworkAdapterTests: XCTestCase {
    func testCoreMLAdapter() async throws {
        let adapter = CoreMLFrameworkAdapter()
        let model = ModelInfo(
            id: "test",
            format: .mlmodel,
            // ... other properties
        )

        XCTAssertTrue(adapter.canHandle(model: model))

        let service = adapter.createService()
        XCTAssertNotNil(service)
    }

    func testAllFrameworksRegistered() {
        let service = UnifiedLLMService()

        // Verify all frameworks can be loaded
        for framework in LLMFramework.allCases {
            XCTAssertNotNil(
                RunAnywhereSDK.shared.getAdapter(for: framework),
                "\(framework) adapter not registered"
            )
        }
    }
}
```

## Migration Steps

### Phase 1: Setup ✅ COMPLETED
**Summary**: Created the foundation for SDK integration in the sample app.

**Completed Items**:
1. ✅ Created directory structure for adapters, providers, tokenizers, and metadata extractors
2. ✅ Extended KeychainService with SDK-specific API key management methods
3. ✅ Created BaseFrameworkAdapter and FrameworkAdapterRegistry skeletons
4. ✅ Implemented UnifiedLLMServiceSDK that purely consumes SDK APIs
5. ✅ Removed all SDK-specific implementation code from the sample app

**Key Architectural Decisions**:
- Sample app only consumes SDK APIs, never implements SDK functionality
- No legacy service dependencies in UnifiedLLMServiceSDK
- Clean separation between SDK consumption and implementation

### Phase 2: Framework Migration ✅ COMPLETED

**Summary**: Created framework adapters for all 10 ML frameworks while preserving existing services.

**Completed Items**:
1. ✅ Created adapters for all 10 ML frameworks
2. ✅ Implemented FrameworkAdapterRegistry to manage all adapters
3. ✅ Preserved all framework-specific logic and requirements
4. ✅ Integrated authentication checks (Kaggle, Picovoice)
5. ✅ Updated UnifiedLLMServiceSDK to use the registry

**Framework Adapters Created**:
| Framework | Adapter | Key Features Preserved |
|-----------|---------|------------------------|
| Core ML | `CoreMLFrameworkAdapter` | Model compilation, Neural Engine optimization |
| TensorFlow Lite | `TFLiteFrameworkAdapter` | Delegate configuration, Kaggle auth |
| MLX | `MLXFrameworkAdapter` | A17 Pro/M3+ device checking, archive extraction |
| Swift Transformers | `SwiftTransformersAdapter` | Strict input_ids validation |
| ONNX | `ONNXFrameworkAdapter` | Execution provider selection |
| LlamaCpp | `LlamaCppFrameworkAdapter` | GGUF/GGML support, quantization detection |
| ExecuTorch | `ExecuTorchAdapter` | PyTorch Edge format, edge optimization |
| Foundation Models | `FoundationModelsAdapter` | iOS 18+ system models, privacy features |
| PicoLLM | `PicoLLMAdapter` | Ultra-compression, API key validation |
| MLC | `MLCAdapter` | JIT compilation, target-specific optimization |

---

## Migration Notes

### Moving from Direct Framework Usage to SDK

For developers currently using frameworks directly:

1. **Wrap existing services** - Don't rewrite, just adapt
2. **Preserve framework logic** - Keep all optimizations and quirks
3. **Add SDK benefits** - Lifecycle management, progress tracking, etc.
4. **Test thoroughly** - Ensure no regression in functionality

---

## Edge Cases and Framework-Specific Considerations

### Framework-Specific Edge Cases

#### 1. CoreML Compilation Failures
- **Issue**: .mlmodel compilation to .mlmodelc can fail on older devices
- **Solution**: Fallback to pre-compiled models or alternative framework
```swift
class CoreMLFrameworkAdapter {
    func handleCompilationFailure(_ error: Error, model: ModelInfo) -> FrameworkAdapter? {
        // Try SwiftTransformers as fallback for transformer models
        if model.architecture?.contains("transformer") == true {
            return SwiftTransformersAdapter()
        }
        return nil
    }
}
```

#### 2. TensorFlow Lite Delegate Conflicts
- **Issue**: CoreML delegate not available on all devices
- **Solution**: Dynamic delegate selection based on hardware
```swift
class TFLiteFrameworkAdapter {
    func selectOptimalDelegate() -> Delegate? {
        if HardwareCapabilityManager.shared.hasNeuralEngine {
            return try? CoreMLDelegate()
        } else if HardwareCapabilityManager.shared.hasGPU {
            return try? MetalDelegate()
        }
        return nil // CPU fallback
    }
}
```

#### 3. MLX Memory Constraints
- **Issue**: MLX requires unified memory architecture
- **Solution**: Pre-flight memory checks and model size validation

#### 4. ONNX Session Creation Failures
- **Issue**: Some ONNX models require specific execution providers
- **Solution**: Fallback chain of execution providers

#### 5. LlamaCpp Quantization Mismatches
- **Issue**: Model quantization format not matching runtime capabilities
- **Solution**: Runtime quantization format detection and adaptation

### Authentication Edge Cases

#### 1. Expired Tokens
- **Issue**: HuggingFace/Kaggle tokens expire during download
- **Solution**: Token refresh mid-download with resume capability

#### 2. Keychain Access Failures
- **Issue**: Keychain locked or unavailable
- **Solution**: Fallback to environment variables or prompt user

### Model Loading Edge Cases

#### 1. Incomplete Model Files
- **Issue**: Multi-file models with missing components
- **Solution**: Validate all required files before loading

#### 2. Framework Switching Mid-Generation
- **Issue**: User wants to switch framework while generating
- **Solution**: Graceful cancellation and state preservation

#### 3. Background Termination
- **Issue**: App terminated while loading large model
- **Solution**: State restoration on app relaunch

## Sample App Best Practices

### 1. Framework Adapter Implementation

```swift
// Always implement all protocol methods
class CustomFrameworkAdapter: FrameworkAdapter {
    // Required: Identify your framework
    let framework: LLMFramework = .custom("MyFramework")

    // Required: Specify supported formats
    let supportedFormats: [ModelFormat] = [.onnx, .custom("myformat")]

    // Required: Check model compatibility
    func canHandle(model: ModelInfo) -> Bool {
        // Check format
        guard supportedFormats.contains(model.format) else { return false }

        // Check hardware requirements
        let hardware = HardwareCapabilityManager.shared.capabilities
        return model.estimatedMemory <= hardware.availableMemory
    }

    // Required: Create service instance
    func createService() -> LLMService {
        return MyCustomLLMService()
    }

    // Optional: Configure for hardware
    func configure(with hardware: HardwareConfiguration) async {
        // Apply hardware-specific optimizations
    }
}
```

### 2. Error Handling

```swift
// Use SDK's error types and recovery
do {
    try await sdk.loadModel("model-id")
} catch SDKError.resourceUnavailable(let reason) {
    // Show user-friendly message
    showError("Cannot load model: \(reason)")
} catch SDKError.authRequired(let service) {
    // Prompt for authentication
    promptForAuth(service: service)
} catch {
    // Generic error handling
    showError(error.localizedDescription)
}
```

### 3. Progress Tracking

```swift
// Subscribe to SDK progress updates
sdk.progressPublisher
    .sink { progress in
        updateUI(
            stage: progress.currentStage,
            percentage: progress.percentage,
            message: progress.message,
            timeRemaining: progress.estimatedTimeRemaining
        )
    }
    .store(in: &cancellables)
```

### 4. Memory Management

```swift
// Let SDK handle memory pressure
sdk.memoryPressureHandler = { level in
    switch level {
    case .low:
        // Maybe clear caches
        clearImageCache()
    case .critical:
        // SDK will unload models automatically
        showMemoryWarning()
    }
}
```




## Phase 3: Framework-Specific Adapter Details

This phase focuses on implementing the detailed framework adapters in the sample app that wrap existing framework services and prepare them for SDK integration.

### 3.1 Base Framework Adapter

**Location**: `examples/ios/RunAnywhereAI/Services/UnifiedArchitecture/Adapters/`

```swift
// Sample App: Services/UnifiedArchitecture/Adapters/BaseFrameworkAdapter.swift
import RunAnywhere // Import SDK

class BaseFrameworkAdapter: FrameworkAdapter {
    let framework: LLMFramework
    let supportedFormats: [ModelFormat]

    private let hardwareManager = HardwareCapabilityManager.shared
    private let progressTracker = UnifiedProgressTracker()
    private let memoryManager = UnifiedMemoryManager.shared

    init(framework: LLMFramework, formats: [ModelFormat]) {
        self.framework = framework
        self.supportedFormats = formats
    }

    func canHandle(model: ModelInfo) -> Bool {
        // Check format compatibility
        guard supportedFormats.contains(model.format) else {
            return false
        }

        // Check hardware requirements
        let hardware = hardwareManager.capabilities
        return model.hardwareRequirements.allSatisfy { req in
            hardware.supports(req)
        }
    }

    func configure(with hardware: HardwareConfiguration) async {
        // Base configuration applicable to all frameworks
    }
}
```

### 3.2 Framework-Specific Adapter Implementations

**Core ML Adapter**:

```swift
// Sample App: Services/UnifiedArchitecture/Adapters/CoreMLFrameworkAdapter.swift
import RunAnywhere
import CoreML

class CoreMLFrameworkAdapter: BaseFrameworkAdapter {
    init() {
        super.init(
            framework: .coreML,
            formats: [.mlmodel, .mlpackage]
        )
    }

    func createService() -> LLMService {
        // Wrap existing CoreMLService with unified interface
        return UnifiedCoreMLService()
    }
}

// IMPORTANT: This is a WRAPPER, not inheritance
// We preserve ALL existing CoreMLService logic
class UnifiedCoreMLAdapter: LLMService {
    private let coreMLService = CoreMLService() // Existing service
    private let lifecycleManager = ModelLifecycleStateMachine()
    private let tokenizerManager = UnifiedTokenizerManager.shared
    private let progressTracker = UnifiedProgressTracker()

    // Preserve existing model adapter factory
    private let adapterFactory = CoreMLAdapterFactory.self

    func initialize(modelPath: String) async throws {
        try await lifecycleManager.transitionTo(.initializing)
        progressTracker.startStage(.initialization)

        do {
            // Use EXISTING CoreMLService initialization
            try await coreMLService.initialize(modelPath: modelPath)

            // Wrap existing tokenizer adapter with unified interface
            if let existingAdapter = coreMLService.tokenizerAdapter {
                let unifiedAdapter = CoreMLTokenizerWrapper(existing: existingAdapter)
                tokenizerManager.registerTokenizer(unifiedAdapter, for: modelPath)
            }

            progressTracker.completeStage(.initialization)
            try await lifecycleManager.transitionTo(.initialized)
        } catch {
            progressTracker.failStage(.initialization, error: error)
            try await lifecycleManager.transitionTo(.error(error))
            throw UnifiedModelError.framework(
                FrameworkError(framework: .coreML, underlying: error)
            )
        }
    }

    // Delegate all operations to existing service
    func generate(prompt: String, options: GenerationOptions) async throws -> String {
        try await coreMLService.generate(prompt: prompt, options: options)
    }

    // PRESERVE: Model compilation logic
    private func preserveCompilationLogic() {
        // The existing compilation logic in CoreMLService.initialize()
        // lines 110-145 is preserved and called through delegation
    }

    // PRESERVE: Model adapter pattern
    private func preserveAdapterPattern() {
        // CoreMLAdapterFactory.createAdapter() logic preserved
        // GPT2CoreMLAdapter and other adapters remain unchanged
    }
}
```

**TensorFlow Lite Adapter (Preserving Delegate Logic)**:

```swift
// Services/UnifiedArchitecture/Adapters/TFLiteFrameworkAdapter.swift
class UnifiedTFLiteAdapter: LLMService {
    private let tfliteService = TFLiteService()
    private let lifecycleManager = ModelLifecycleStateMachine()

    // PRESERVE: Complex delegate configuration
    private func preserveDelegateConfiguration() {
        // Lines 99-121 in TFLiteService - delegate selection logic
        // This MUST be preserved as-is for proper acceleration
    }

    // PRESERVE: Tensor shape management
    private func preserveTensorHandling() {
        // Lines 283-300 - createTensorInput logic
        // Critical for proper model input formatting
    }

    // INTEGRATE: Kaggle authentication
    func initialize(modelPath: String) async throws {
        // Check if model requires Kaggle auth
        if requiresKaggleAuth(modelPath) {
            let kaggleService = KaggleAuthService.shared
            guard kaggleService.hasValidCredentials() else {
                throw UnifiedModelError.authRequired("Kaggle")
            }
        }

        try await tfliteService.initialize(modelPath: modelPath)
    }
}
```

**MLX Adapter (Handling Archives & Device Requirements)**:

```swift
class UnifiedMLXAdapter: LLMService {
    private let mlxService = MLXService()
    private let downloadManager = EnhancedDownloadManager()

    // PRESERVE: Device compatibility checking
    private func checkDeviceRequirements() throws {
        // A17 Pro/M3+ requirement from MLXService.isMLXSupported()
        guard ProcessInfo.processInfo.processorHasARM64E else {
            throw UnifiedModelError.deviceNotSupported("MLX requires A17 Pro/M3+")
        }
    }

    // HANDLE: Archive extraction
    func initialize(modelPath: String) async throws {
        try checkDeviceRequirements()

        // Check if model needs extraction
        if modelPath.hasSuffix(".tar.gz") {
            let extracted = try await downloadManager.extractTarGz(URL(fileURLWithPath: modelPath))
            try await mlxService.initialize(modelPath: extracted.path)
        } else {
            try await mlxService.initialize(modelPath: modelPath)
        }
    }

    // PRESERVE: MLXModelWrapper directory structure handling
    private func preserveDirectoryHandling() {
        // Lines 33-59 in MLXService - directory vs file detection
    }
}
```

**Swift Transformers Adapter (Strict Validation)**:

```swift
class UnifiedSwiftTransformersAdapter: LLMService {
    private let swiftTransformersService = SwiftTransformersService()

    // PRESERVE: Strict model validation
    private func validateModelCompatibility(_ modelPath: String) throws {
        // Lines 188-209 - input_ids validation
        // This is CRITICAL - Swift Transformers will crash without proper inputs
    }

    // REMOVE: Bundled model support
    func initialize(modelPath: String) async throws {
        // Remove lines 122-131 - bundled model checking
        // All models must be downloaded, not bundled

        try validateModelCompatibility(modelPath)
        try await swiftTransformersService.initialize(modelPath: modelPath)
    }
}
```

**LlamaCpp Adapter (GGUF/GGML Support)**:

```swift
class UnifiedLlamaCppAdapter: LLMService {
    private let llamaCppService = LlamaCppService()
    private let lifecycleManager = ModelLifecycleStateMachine()

    // PRESERVE: Quantization format handling
    private func detectQuantizationFormat(_ modelPath: String) -> QuantizationFormat? {
        // Detect Q2, Q3, Q4, Q5, Q6, Q8 formats from filename or metadata
    }

    // PRESERVE: Memory mapping
    func initialize(modelPath: String) async throws {
        try await lifecycleManager.transitionTo(.initializing)

        // Check format
        guard modelPath.hasSuffix(".gguf") || modelPath.hasSuffix(".ggml") else {
            throw UnifiedModelError.unsupportedFormat("LlamaCpp requires GGUF/GGML")
        }

        // Configure hardware acceleration
        let hardware = HardwareCapabilityManager.shared.capabilities
        if hardware.hasGPU {
            llamaCppService.enableMetalAcceleration()
        }

        try await llamaCppService.initialize(modelPath: modelPath)
        try await lifecycleManager.transitionTo(.initialized)
    }

    // PRESERVE: Streaming capabilities
    func streamGenerate(prompt: String, options: GenerationOptions, onToken: @escaping (String) -> Void) async throws {
        try await llamaCppService.streamGenerate(prompt: prompt, options: options, onToken: onToken)
    }
}
```

**Foundation Models Adapter (iOS 18+ System Models)**:

```swift
@available(iOS 18.0, *)
class UnifiedFoundationModelsAdapter: LLMService {
    private let foundationService = FoundationModelsService()

    // SPECIAL: No model download needed
    func initialize(modelPath: String) async throws {
        // Foundation Models are system-provided
        // modelPath is ignored or used as identifier only

        guard #available(iOS 26.0, *) else {
            throw UnifiedModelError.platformNotSupported("Foundation Models require iOS 26+")
        }

        try await foundationService.initialize(modelPath: "system")
    }

    // PRESERVE: Privacy features
    func configurePrivacy(options: PrivacyOptions) {
        foundationService.setDifferentialPrivacy(enabled: options.differentialPrivacy)
        foundationService.setOnDeviceOnly(options.onDeviceOnly)
    }
}
```

**PicoLLM Adapter (Ultra-Compressed Models)**:

```swift
class UnifiedPicoLLMAdapter: LLMService {
    private let picoService = PicoLLMService()
    private let keychain = KeychainService.shared

    // REQUIRE: API key validation
    func initialize(modelPath: String) async throws {
        // Check for Picovoice API key
        guard let apiKey = try? keychain.retrieveAPIKey(for: "picovoice") else {
            throw UnifiedModelError.authRequired("Picovoice API key required")
        }

        picoService.setAPIKey(apiKey)

        // PicoLLM models are pre-optimized
        try await picoService.initialize(modelPath: modelPath)
    }

    // PRESERVE: Edge optimization
    func configureForEdge() {
        picoService.setLowLatencyMode(true)
        picoService.setMemoryOptimization(.aggressive)
    }
}
```

**MLC Adapter (Universal Compilation)**:

```swift
class UnifiedMLCAdapter: LLMService {
    private let mlcService = MLCService()
    private let compilationCache = CompilationCache.shared

    // PRESERVE: JIT compilation
    func initialize(modelPath: String) async throws {
        // Check if model is already compiled for this device
        let deviceId = HardwareCapabilityManager.shared.deviceIdentifier
        let cacheKey = "\(modelPath)-\(deviceId)"

        if let compiledPath = compilationCache.getCompiledModel(key: cacheKey) {
            try await mlcService.initialize(modelPath: compiledPath)
        } else {
            // Compile for current hardware
            let compiled = try await compileForDevice(modelPath)
            compilationCache.store(key: cacheKey, path: compiled)
            try await mlcService.initialize(modelPath: compiled)
        }
    }

    private func compileForDevice(_ modelPath: String) async throws -> String {
        let hardware = HardwareCapabilityManager.shared.capabilities

        var target = "auto"
        if hardware.hasNeuralEngine {
            target = "apple-neural-engine"
        } else if hardware.hasGPU {
            target = "metal"
        }

        return try await mlcService.compile(modelPath: modelPath, target: target)
    }
}
```

### 3.3 Adapter Registry & Factory

```swift
// Sample App: Services/UnifiedArchitecture/Adapters/FrameworkAdapterRegistry.swift
import RunAnywhere

class FrameworkAdapterRegistry {
    static let shared = FrameworkAdapterRegistry()

    private var adapters: [LLMFramework: FrameworkAdapter] = [:]

    init() {
        registerDefaultAdapters()
    }

    private func registerDefaultAdapters() {
        register(CoreMLFrameworkAdapter())
        register(TFLiteFrameworkAdapter())
        register(MLXFrameworkAdapter())
        register(SwiftTransformersAdapter())
        register(ONNXFrameworkAdapter())
        register(ExecuTorchAdapter())
        register(LlamaCppFrameworkAdapter())
        register(FoundationModelsAdapter())
        register(PicoLLMFrameworkAdapter())
        register(MLCFrameworkAdapter())
    }

    func register(_ adapter: FrameworkAdapter) {
        adapters[adapter.framework] = adapter
    }

    func getAdapter(for framework: LLMFramework) -> FrameworkAdapter? {
        return adapters[framework]
    }

    func findBestAdapter(for model: ModelInfo) -> FrameworkAdapter? {
        // Get hardware capabilities
        let hardware = HardwareCapabilityManager.shared.capabilities

        // Score each adapter
        let scores = adapters.values.compactMap { adapter -> (FrameworkAdapter, Double)? in
            guard adapter.canHandle(model: model) else { return nil }

            let score = calculateScore(
                adapter: adapter,
                model: model,
                hardware: hardware
            )

            return (adapter, score)
        }

        // Return highest scoring adapter
        return scores.max(by: { $0.1 < $1.1 })?.0
    }

    private func calculateScore(
        adapter: FrameworkAdapter,
        model: ModelInfo,
        hardware: DeviceCapabilities
    ) -> Double {
        var score = 0.0

        // Hardware optimization score
        if adapter.framework == .coreML && hardware.hasNeuralEngine {
            score += 10.0
        }

        // Memory efficiency score
        let memoryScore = adapter.estimatedMemoryEfficiency(for: model)
        score += memoryScore * 5.0

        // Performance score
        let perfScore = adapter.estimatedPerformance(for: model, on: hardware)
        score += perfScore * 8.0

        return score
    }
}
```

## Phase 4: Sample App Integration and Cleanup

This phase focuses on updating the sample app to use the SDK and cleaning up legacy code.

### 4.1 Update Sample App to Use SDK

**Location**: `examples/ios/RunAnywhereAI/Services/UnifiedLLMService.swift`

**Implementation**:

```swift
// Sample App: Services/UnifiedLLMService.swift
import RunAnywhere
import SwiftUI

@MainActor
class UnifiedLLMService: ObservableObject {
    static let shared = UnifiedLLMService()

    // SAME public interface - no breaking changes
    @Published var currentService: LLMService?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentFramework: LLMFramework?
    @Published var currentModel: ModelInfo?

    // New unified components (private)
    private let modelRegistry = DynamicModelRegistry()
    private let lifecycleManager = ModelLifecycleStateMachine()
    private let downloadManager = EnhancedDownloadManager()
    private let memoryManager = UnifiedMemoryManager.shared
    private let progressTracker = UnifiedProgressTracker()
    private let adapterRegistry = FrameworkAdapterRegistry.shared
    private let tokenizerManager = UnifiedTokenizerManager.shared

    // PUBLIC API - Keep exactly the same
    func loadModel(_ model: ModelInfo, framework: LLMFramework? = nil) async throws {
        NSLog("🔍 UnifiedService.loadModel called with model: %@, framework: %@",
              model.name, framework?.displayName ?? "auto")

        // Direct implementation - no feature flags
        try await loadModelImpl(model, framework: framework)
    }

    private func loadModelImpl(_ model: ModelInfo, framework: LLMFramework?) async throws {
        let errorRecovery = UnifiedErrorRecovery()
        let validator = UnifiedModelValidator()
        let metadataExtractor = MetadataExtractor()

        // Check resource availability first
        let resources = HardwareCapabilityManager.shared.checkResourceAvailability()
        let (canLoad, reason) = resources.canLoad(model: model)
        if !canLoad {
            throw UnifiedModelError.resourceUnavailable(reason ?? "Insufficient resources")
        }

        // Start lifecycle
        try await lifecycleManager.transitionTo(.discovered(model))

        // Download if needed
        if model.localPath == nil {
            try await lifecycleManager.transitionTo(.downloading(progress: 0))

            do {
                let downloadTask = try await downloadManager.downloadModel(model)
                let localPath = try await downloadTask.result.value
                model.localPath = localPath
                try await lifecycleManager.transitionTo(.downloaded(location: localPath))
            } catch {
                let context = RecoveryContext(
                    model: model,
                    stage: .download,
                    attemptCount: 1,
                    previousErrors: [error],
                    availableResources: resources
                )
                try await errorRecovery.attemptRecovery(from: error, in: context)
                // Retry after recovery
                return try await loadModelImpl(model, framework: framework)
            }
        }

        // Extract if needed
        if downloadManager.needsExtraction(model.localPath!) {
            try await lifecycleManager.transitionTo(.extracting)
            let extracted = try await downloadManager.extractArchive(model.localPath!)
            model.localPath = extracted
            try await lifecycleManager.transitionTo(.extracted(location: extracted))
        }

        // Validate model
        try await lifecycleManager.transitionTo(.validating)
        let validationResult = try await validator.validateModel(model, at: model.localPath!)

        if !validationResult.isValid {
            let context = RecoveryContext(
                model: model,
                stage: .validation,
                attemptCount: 1,
                previousErrors: validationResult.errors,
                availableResources: resources
            )
            try await errorRecovery.attemptRecovery(from: validationResult.errors.first!, in: context)
            // Retry after recovery
            return try await loadModelImpl(model, framework: framework)
        }

        try await lifecycleManager.transitionTo(.validated)

        // Extract metadata
        let metadata = await metadataExtractor.extractMetadata(
            from: model.localPath!,
            format: model.format
        )
        model.metadata = metadata

        // Find best adapter
        let adapter = framework.flatMap { adapterRegistry.getAdapter(for: $0) }
            ?? adapterRegistry.findBestAdapter(for: model)

        guard let adapter = adapter else {
            throw UnifiedModelError.noCompatibleFramework(model: model)
        }

        // Configure hardware
        let hardwareConfig = HardwareCapabilityManager.shared.optimalConfiguration(for: model)
        await adapter.configure(with: hardwareConfig)

        // Create service
        let service = adapter.createService()

        // Initialize with error recovery
        try await lifecycleManager.transitionTo(.initializing)

        do {
            try await service.initializeModel(model)
            try await lifecycleManager.transitionTo(.initialized)
        } catch {
            let context = RecoveryContext(
                model: model,
                stage: .initialization,
                attemptCount: 1,
                previousErrors: [error],
                availableResources: resources
            )
            try await errorRecovery.attemptRecovery(from: error, in: context)

            // Check if we should retry with different framework
            if case UnifiedModelError.retryWithFramework(let newFramework) = error {
                return try await loadModelImpl(model, framework: newFramework)
            }
        }

        // Load
        try await lifecycleManager.transitionTo(.loading)
        try await service.loadModel(model)
        try await lifecycleManager.transitionTo(.loaded)

        // Ready
        try await lifecycleManager.transitionTo(.ready)

        // Update state
        self.currentService = service
        self.currentFramework = adapter.framework
        self.currentModel = model

        // Register with memory manager
        let modelSize = try await service.getModelMemoryUsage()
        memoryManager.registerLoadedModel(
            LoadedModel(
                id: model.id,
                framework: adapter.framework,
                service: service,
                tokenizer: try await tokenizerManager.getTokenizer(for: model),
                metadata: metadata
            ),
            size: modelSize,
            service: service
        )
    }
}
```

### 4.2 Sample App Cleanup & Code Removal

**Files to DELETE Completely**:
```
Services/
├── UnifiedLLMService.swift (DELETE - replaced by new implementation)
├── BundledModelsService.swift (DELETE - no more bundled models)
├── ModelURLRegistry.swift (DELETE - replaced by DynamicModelRegistry)
├── Tokenization/
│   ├── BaseTokenizer.swift (DELETE - replaced by unified system)
│   ├── TokenizerFactory.swift (DELETE - replaced by UnifiedTokenizerManager)
│   └── TokenizerAdapterFactory.swift (DELETE - integrated into unified)
└── ModelManagement/
    └── ModelCompatibilityChecker.swift (DELETE - integrated into registry)
```

**Code to REMOVE from existing files**:

**1. Remove from all LLMService implementations:**
```swift
// DELETE these properties from each service:
override var supportedModels: [ModelInfo] {
    get { ModelURLRegistry.shared.getAllModels(for: .xxx) }
    set { }
}

// DELETE hardcoded model lists
// DELETE duplicate hardware detection code
// DELETE basic error handling
```

**2. Remove from CoreMLService:**
```swift
// DELETE lines 319-341: isNeuralEngineAvailable()
// Replaced by HardwareCapabilityManager

// DELETE manual tokenizer adapter creation (lines 166-174)
// Replaced by UnifiedTokenizerManager
```

**3. Remove from TFLiteService:**
```swift
// DELETE duplicate delegate configuration logic
// Keep only the core configuration, remove UI decisions
```

**4. Remove from SwiftTransformersService:**
```swift
// DELETE lines 122-131: Bundled model support
// DELETE all references to app bundle models
```

### 4.3 UI Updates

**Update UnifiedModelsView**:

```swift
// Views/UnifiedModelsView.swift (UPDATE EXISTING)
struct UnifiedModelsView: View {
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var unifiedService = UnifiedLLMService.shared // Same name!
    @StateObject private var progressTracker = UnifiedProgressTracker.shared

    var body: some View {
        List {
            // Models from dynamic registry
            Section("Available Models") {
                ForEach(unifiedService.discoveredModels) { model in
                    UnifiedModelRow(model: model)
                }
            }

            // Downloaded models with memory info
            Section("Downloaded Models") {
                ForEach(modelManager.downloadedModels) { model in
                    DownloadedModelRow(model: model)
                        .overlay(alignment: .topTrailing) {
                            if let memory = memoryManager.getModelMemoryUsage(model.id) {
                                Text(ByteCountFormatter.string(fromByteCount: memory, countStyle: .memory))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                }
            }
        }
    }
}

struct UnifiedModelRow: View {
    let model: ModelInfo
    @StateObject private var progressTracker = UnifiedProgressTracker.shared

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(model.name)
                Spacer()
                Text(model.format.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Show compatible frameworks
            HStack {
                ForEach(model.compatibleFrameworks, id: \.self) { framework in
                    FrameworkBadge(framework: framework)
                }
            }

            // Progress if loading
            if let progress = progressTracker.getProgress(for: model.id) {
                ProgressView(value: progress.percentage)
                Text(progress.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
```

### 4.4 Sample App Directory Structure

```
examples/ios/RunAnywhereAI/
├── RunAnywhereAI.xcodeproj
├── Package.swift
├── Podfile                              # For TensorFlow Lite
├── Info.plist
├── RunAnywhereAIApp.swift
├── Services/
│   ├── UnifiedArchitecture/             # New unified implementation
│   │   ├── UnifiedLLMService.swift      # Main orchestrator
│   │   ├── Adapters/
│   │   │   ├── BaseFrameworkAdapter.swift
│   │   │   ├── FrameworkAdapterRegistry.swift
│   │   │   ├── CoreMLFrameworkAdapter.swift
│   │   │   ├── TFLiteFrameworkAdapter.swift
│   │   │   ├── MLXFrameworkAdapter.swift
│   │   │   ├── SwiftTransformersAdapter.swift
│   │   │   ├── ONNXFrameworkAdapter.swift
│   │   │   ├── ExecuTorchAdapter.swift
│   │   │   ├── LlamaCppFrameworkAdapter.swift
│   │   │   ├── FoundationModelsAdapter.swift
│   │   │   ├── PicoLLMFrameworkAdapter.swift
│   │   │   └── MLCFrameworkAdapter.swift
│   │   ├── Hardware/
│   │   │   └── AdvancedHardwareDetector.swift
│   │   └── Extensions/
│   │       ├── CustomErrorRecovery.swift
│   │       └── PerformanceOptimizations.swift
│   ├── Frameworks/                      # Framework-specific services
│   │   ├── CoreML/
│   │   │   ├── CoreMLService.swift      # Existing implementation
│   │   │   ├── CoreMLModelAdapter.swift
│   │   │   └── CoreMLTokenizerAdapter.swift
│   │   ├── TFLite/
│   │   │   ├── TFLiteService.swift
│   │   │   ├── TFLiteDelegate.swift
│   │   │   └── TFLiteTokenizer.swift
│   │   ├── MLX/
│   │   │   ├── MLXService.swift
│   │   │   ├── MLXModelWrapper.swift
│   │   │   └── MLXTokenizer.swift
│   │   ├── SwiftTransformers/
│   │   │   └── SwiftTransformersService.swift
│   │   ├── ONNX/
│   │   │   ├── ONNXService.swift
│   │   │   └── ONNXTokenizer.swift
│   │   ├── ExecuTorch/
│   │   │   └── ExecuTorchService.swift
│   │   ├── LlamaCpp/
│   │   │   └── LlamaCppService.swift
│   │   ├── FoundationModels/
│   │   │   └── FoundationModelsService.swift
│   │   ├── PicoLLM/
│   │   │   └── PicoLLMService.swift
│   │   └── MLC/
│   │       └── MLCService.swift
│   ├── Providers/                       # Custom model providers
│   │   ├── CustomHuggingFaceProvider.swift
│   │   ├── KaggleProvider.swift
│   │   └── AppleModelsProvider.swift
│   ├── Tokenizers/                      # Custom tokenizer implementations
│   │   ├── BPETokenizer.swift
│   │   ├── SentencePieceTokenizer.swift
│   │   └── TokenizerAdapters/
│   │       └── CustomTokenizerAdapters.swift
│   ├── Auth/
│   │   ├── KeychainService.swift
│   │   ├── HuggingFaceAuthService.swift
│   │   └── KaggleAuthService.swift
│   └── Storage/
│       ├── ModelLocalStorage.swift
│       └── CompilationCache.swift
├── Views/
│   ├── ContentView.swift
│   ├── ModelSelectionView.swift
│   ├── GenerationView.swift
│   ├── ProgressView.swift
│   ├── SettingsView.swift
│   └── Components/
│       ├── ModelRow.swift
│       ├── FrameworkBadge.swift
│       └── ProgressIndicator.swift
├── ViewModels/
│   ├── ModelViewModel.swift
│   ├── GenerationViewModel.swift
│   └── SettingsViewModel.swift
├── Resources/
│   ├── Assets.xcassets
│   └── Localizable.strings
└── Tests/
    ├── FrameworkAdapterTests/
    ├── TokenizerTests/
    └── IntegrationTests/
```

## Phase 5: Testing & Validation

This phase focuses on comprehensive testing of the SDK integration and framework adapters.

### 5.1 Framework Adapter Tests

Test each framework adapter to ensure proper SDK integration:

1. **Unit Tests**: Test adapter registration and framework detection
2. **Integration Tests**: Test end-to-end model loading through SDK
3. **Performance Tests**: Measure performance impact of unified architecture
4. **Memory Tests**: Validate memory management under pressure

### 5.2 Validation Checklist

- [ ] All 10 framework adapters successfully register with SDK
- [ ] Model loading works through SDK for each framework
- [ ] Framework-specific optimizations are preserved
- [ ] Authentication flows work correctly
- [ ] Error recovery mechanisms function properly
- [ ] Progress tracking updates UI correctly
- [ ] Memory management handles pressure gracefully

## Summary

The sample app framework implementation plan has been updated to reflect:

1. **Phases 1-2 Completed**: Foundation and framework migration done
2. **Phase 3 Active**: Detailed framework adapter implementations
3. **Phase 4 Ready**: Sample app integration and cleanup
4. **Phase 5 Planning**: Testing and validation strategy

The implementation maintains clean separation between SDK and sample app responsibilities while preserving all framework-specific optimizations.
