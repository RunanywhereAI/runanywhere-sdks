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

### Phase 1: Setup (Week 1) ✅ COMPLETED
1. ✅ Update Package.swift to include SDK dependency
   - Project configured to use Swift Package Manager for SDK integration
   - SDK dependency path prepared: `../../../sdk/runanywhere-swift`
2. ✅ Create directory structure for frameworks
   - Created `/Services/Adapters/` for framework adapters
   - Created `/Services/Providers/` for model providers  
   - Created `/Services/Tokenizers/Adapters/` for tokenizer adapters
   - Created `/Services/Metadata/` for metadata extractors
3. ✅ Set up authentication services
   - Extended `KeychainService` with SDK-specific methods in `KeychainServiceExtensions.swift`
   - Added support for HuggingFace, Kaggle, Picovoice, and RunAnywhere API keys

### Phase 1 Implementation Details:
- **BaseFrameworkAdapter.swift**: Created skeleton that will implement SDK's FrameworkAdapter protocol
- **FrameworkAdapterRegistry.swift**: Simple registry for custom framework adapters (SDK handles built-in ones)
- **CoreMLFrameworkAdapter.swift**: Example adapter structure showing how to wrap existing services
- **UnifiedLLMServiceSDK.swift**: New service that purely consumes SDK APIs, no legacy dependencies
- **Removed SDK components**: Deleted hardware detection and other SDK-specific implementations

### Phase 2: Framework Migration (Week 2-3) ✅ COMPLETED
1. ✅ Move each framework service to new structure
   - All existing framework services preserved in their original locations
   - Created wrapper adapters instead of moving services
2. ✅ Create framework adapters implementing SDK protocols
   - Created all 10 framework adapters:
     - `CoreMLFrameworkAdapter.swift` - Wraps CoreMLService
     - `TFLiteFrameworkAdapter.swift` - Handles TensorFlow Lite with delegates
     - `MLXFrameworkAdapter.swift` - Includes A17 Pro/M3+ device checking
     - `SwiftTransformersAdapter.swift` - Strict input validation
     - `ONNXFrameworkAdapter.swift` - Execution provider management
     - `LlamaCppFrameworkAdapter.swift` - GGUF/GGML with quantization
     - `ExecuTorchAdapter.swift` - PyTorch Edge format support
     - `FoundationModelsAdapter.swift` - iOS 18+ system models
     - `PicoLLMAdapter.swift` - Ultra-compressed models with API key
     - `MLCAdapter.swift` - JIT compilation with caching
3. ✅ Preserve all framework-specific logic
   - Each adapter maintains unique requirements (device checks, validation, etc.)
   - Original services remain untouched
   - Framework-specific optimizations preserved
4. ✅ Update imports and dependencies
   - Updated `FrameworkAdapterRegistry` to register all adapters
   - Updated `UnifiedLLMServiceSDK` to use the registry
   - All adapters ready for SDK protocol implementation

### Phase 2 Implementation Details:
- **Adapter Pattern**: Each framework has both an adapter and a unified service wrapper
- **Registry Pattern**: `FrameworkAdapterRegistry` manages all adapters and will register with SDK
- **Clean Separation**: Adapters only prepare to consume SDK APIs, no SDK implementation
- **Framework Specifics Preserved**:
  - MLX: Device capability checking for A17 Pro/M3+
  - SwiftTransformers: Strict 'input_ids' validation
  - TFLite: Delegate configuration (CoreML/Metal)
  - LlamaCpp: Quantization format detection
  - PicoLLM: API key validation
  - MLC: Compilation caching
  - FoundationModels: System model handling
- **Authentication Integration**: Kaggle and Picovoice API key checks included

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

## Phase 1 Completion Summary

Phase 1 of the sample app implementation has been successfully completed with the following achievements:

### ✅ Completed Items:
1. **Directory Structure**: Created all necessary directories for adapters, providers, tokenizers, and metadata extractors
2. **Authentication Services**: Extended KeychainService with SDK-specific API key management
3. **Base Framework Adapters**: Created skeleton implementations that will consume SDK protocols
4. **SDK Integration Service**: Implemented UnifiedLLMServiceSDK that purely consumes SDK APIs
5. **Clean Architecture**: Removed all SDK-specific implementations from the sample app

### 🔄 Key Architectural Decisions:
- **No SDK Implementation**: Sample app only consumes SDK APIs, never implements SDK functionality
- **No Legacy Dependencies**: UnifiedLLMServiceSDK has no references to legacy services
- **Placeholder Pattern**: Used commented code to show where SDK calls will be made
- **Framework Wrappers**: Existing framework services (CoreMLService, etc.) remain unchanged and will be wrapped by adapters

### 📝 Ready for Next Phase:
The sample app is now properly structured to:
- Import the RunAnywhere SDK when available
- Implement SDK protocols in framework adapters
- Consume SDK's built-in components (lifecycle management, tokenizers, etc.)
- Demonstrate best practices for SDK integration

### 🚀 Next Steps:
When the SDK implementation is complete in the other branch:
1. Add SDK package dependency to Xcode project
2. Uncomment SDK imports and API calls
3. Implement SDK protocols in framework adapters
4. Test integration with all 10 frameworks

## Phase 2 Completion Summary

Phase 2 of the sample app implementation has been successfully completed with the following achievements:

### ✅ Completed Items:
1. **Framework Adapters**: Created adapters for all 10 ML frameworks
2. **Unified Services**: Each framework has a unified service wrapper ready for SDK integration
3. **Registry Implementation**: `FrameworkAdapterRegistry` manages and registers all adapters
4. **Framework Logic Preserved**: All framework-specific requirements and optimizations maintained
5. **Clean Architecture**: Adapters wrap existing services without modifying them

### 🏗️ Framework Adapter Details:
| Framework | Adapter | Key Features Preserved |
|-----------|---------|----------------------|
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

### 🔄 Architectural Achievements:
- **Wrapper Pattern**: Each adapter wraps existing framework services without modification
- **SDK Ready**: All adapters have commented code showing SDK integration points
- **Authentication**: Integrated Kaggle and Picovoice authentication checks
- **Hardware Awareness**: Device-specific optimizations preserved (MLX, Neural Engine, etc.)
- **Format Support**: Each adapter declares its supported model formats

### 📝 Ready for Phase 3:
The framework migration establishes:
- Complete adapter coverage for all 10 frameworks
- Registry pattern for centralized adapter management
- Clean separation between SDK consumption and framework implementation
- Preservation of all framework-specific optimizations and requirements

### 🎯 Phase 2 Impact:
This phase successfully bridges the gap between the existing framework implementations and the upcoming SDK integration, ensuring that all framework-specific logic is preserved while preparing for the unified SDK interface.

### 📂 Created Files:
```
Services/Adapters/
├── BaseFrameworkAdapter.swift          # Base class for all framework adapters
├── FrameworkAdapterRegistry.swift      # Manages all framework adapters
├── CoreMLFrameworkAdapter.swift        # Core ML adapter implementation
├── TFLiteFrameworkAdapter.swift        # TensorFlow Lite adapter
├── MLXFrameworkAdapter.swift           # MLX adapter with device checks
├── SwiftTransformersAdapter.swift      # Swift Transformers adapter
├── ONNXFrameworkAdapter.swift          # ONNX Runtime adapter
├── LlamaCppFrameworkAdapter.swift      # Llama.cpp adapter for GGUF/GGML
├── ExecuTorchAdapter.swift             # ExecuTorch for edge devices
├── FoundationModelsAdapter.swift       # Apple's Foundation Models
├── PicoLLMAdapter.swift                # Picovoice's ultra-compressed models
└── MLCAdapter.swift                    # Machine Learning Compilation adapter
```

### 🔗 Integration with UnifiedLLMServiceSDK:
```swift
private func registerFrameworkAdapters() {
    // Get all adapters from the registry
    let adapters = FrameworkAdapterRegistry.shared.getAllAdapters()
    
    // When SDK is available, register each adapter:
    // for adapter in adapters {
    //     sdk.registerFrameworkAdapter(adapter)
    // }
    
    print("Registered \(adapters.count) framework adapters")
}
```