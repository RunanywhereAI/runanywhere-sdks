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

### UnifiedLLMService

```swift
// Services/UnifiedLLMService.swift
import RunAnywhere
import Combine

@MainActor
class UnifiedLLMService: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentModel: ModelInfo?
    @Published var progress: ProgressInfo?
    
    private let sdk = RunAnywhereSDK.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Initialize SDK with configuration
        Task {
            try await initializeSDK()
        }
        
        // Subscribe to SDK progress updates
        sdk.progressPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$progress)
    }
    
    private func initializeSDK() async throws {
        // Register hardware detector
        sdk.hardwareManager.registerHardwareDetector(iOSHardwareDetector())
        
        // Register model providers
        sdk.modelRegistry.registerProvider(HuggingFaceProvider())
        sdk.modelRegistry.registerProvider(KaggleProvider())
        sdk.modelRegistry.registerProvider(AppleModelsProvider())
        sdk.modelRegistry.registerProvider(MicrosoftModelsProvider())
        sdk.modelRegistry.registerProvider(PicovoiceProvider())
        sdk.modelRegistry.registerProvider(MLCProvider())
        
        // Register metadata extractors
        sdk.metadataExtractor.registerExtractor(CoreMLMetadataExtractor())
        sdk.metadataExtractor.registerExtractor(SafetensorsMetadataExtractor())
        sdk.metadataExtractor.registerExtractor(GGUFMetadataExtractor())
        sdk.metadataExtractor.registerExtractor(TFLiteMetadataExtractor())
        sdk.metadataExtractor.registerExtractor(ONNXMetadataExtractor())
        
        // Register tokenizer adapters
        sdk.tokenizerManager.registerTokenizerAdapter(BPETokenizerAdapter.self)
        sdk.tokenizerManager.registerTokenizerAdapter(SentencePieceAdapter.self)
        sdk.tokenizerManager.registerTokenizerAdapter(WordPieceAdapter.self)
        sdk.tokenizerManager.registerTokenizerAdapter(TFLiteTokenizerAdapter.self)
        sdk.tokenizerManager.registerTokenizerAdapter(CoreMLTokenizerAdapter.self)
        
        // Register framework adapters
        registerFrameworkAdapters()
    }
    
    private func registerFrameworkAdapters() {
        sdk.registerFrameworkAdapter(CoreMLFrameworkAdapter())
        sdk.registerFrameworkAdapter(TFLiteFrameworkAdapter())
        sdk.registerFrameworkAdapter(MLXFrameworkAdapter())
        sdk.registerFrameworkAdapter(SwiftTransformersAdapter())
        sdk.registerFrameworkAdapter(ONNXFrameworkAdapter())
        sdk.registerFrameworkAdapter(ExecuTorchAdapter())
        sdk.registerFrameworkAdapter(LlamaCppAdapter())
        
        if #available(iOS 18.0, *) {
            sdk.registerFrameworkAdapter(FoundationModelsAdapter())
        }
        
        sdk.registerFrameworkAdapter(PicoLLMAdapter())
        sdk.registerFrameworkAdapter(MLCAdapter())
    }
    
    func loadModel(_ identifier: String, framework: LLMFramework? = nil) async {
        isLoading = true
        error = nil
        
        do {
            try await sdk.loadModel(identifier, preferredFramework: framework)
            currentModel = sdk.currentModel
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    func generate(_ prompt: String) async throws -> GenerationResult {
        return try await sdk.generate(prompt)
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

### Phase 1: Setup (Week 1)
1. Update Package.swift to include SDK dependency
2. Create directory structure for frameworks
3. Set up authentication services

### Phase 2: Framework Migration (Week 2-3)
1. Move each framework service to new structure
2. Create framework adapters implementing SDK protocols
3. Preserve all framework-specific logic
4. Update imports and dependencies

### Phase 3: Tokenizer Migration (Week 4)
1. Create tokenizer adapters for SDK protocol
2. Move tokenizer implementations
3. Register with SDK's tokenizer manager

### Phase 4: UI Updates (Week 5)
1. Update views to use SDK
2. Implement progress tracking UI
3. Add framework selection UI
4. Update error handling displays

### Phase 5: Testing & Validation (Week 6)
1. Test each framework adapter
2. Validate model loading through SDK
3. Performance testing
4. Memory usage validation

## Migration Notes

### Moving from Direct Framework Usage to SDK

For developers currently using frameworks directly:

1. **Wrap existing services** - Don't rewrite, just adapt
2. **Preserve framework logic** - Keep all optimizations and quirks
3. **Add SDK benefits** - Lifecycle management, progress tracking, etc.
4. **Test thoroughly** - Ensure no regression in functionality

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

## Conclusion

This sample app implementation plan demonstrates:

1. **Clean Separation**: SDK provides infrastructure, app provides frameworks
2. **Flexibility**: Developers can implement custom frameworks
3. **Best Practices**: Reference implementation for SDK integration
4. **Comprehensive Coverage**: All 10 frameworks with specific requirements preserved
5. **Edge Case Handling**: Robust error handling and recovery strategies

The sample app serves as both a testing ground for the SDK and a reference for developers building their own applications with the RunAnywhere SDK.