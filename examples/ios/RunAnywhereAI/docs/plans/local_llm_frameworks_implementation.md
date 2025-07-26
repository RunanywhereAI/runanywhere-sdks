# Local LLM Frameworks Implementation Plan

## Overview

This plan outlines the implementation of 10 real LLM framework integrations for the iOS Local LLM sample app, replacing mock implementations and adding missing frameworks to demonstrate comprehensive local AI capabilities on iOS devices.

## Current State Analysis

### What Exists Now:
- ✅ Basic SwiftUI app structure with tab navigation
- ✅ LLM protocol and service architecture established
- ✅ Chat interface with streaming support implemented
- ✅ Model selection and management UI completed
- ✅ Settings view with generation parameters
- ✅ Performance monitoring infrastructure
- ✅ Created 3 LLM framework services (Mock, llama.cpp, Core ML, MLX)
- ✅ Implemented memory management and optimization
- ❌ All LLM services are still mock implementations (no real inference)
- ❌ No real model loading or tokenization
- ❌ Missing 7 framework implementations (MLC-LLM, ONNX Runtime, ExecuTorch, TensorFlow Lite, picoLLM, Swift Transformers, Apple Foundation Models)

### Key Files Created/Modified:
- `Services/LLMProtocol.swift` - Protocol definition
- `Services/UnifiedLLMService.swift` - Service manager
- `Services/MockLLMService.swift` - Current mock implementation
- `Services/LlamaCppService.swift` - Mock llama.cpp service (needs real implementation)
- `Services/CoreMLService.swift` - Mock Core ML service (needs real implementation)
- `Services/MLXService.swift` - Mock MLX service (needs real implementation)
- `Models/ModelInfo.swift` - Model data structure
- `Models/ChatMessage.swift` - Chat message model
- `Models/GenerationOptions.swift` - Generation parameters
- `ViewModels/ChatViewModel.swift` - Chat logic
- `ViewModels/ModelListViewModel.swift` - Model management
- `Views/ChatView.swift` - Chat interface
- `Views/ModelListView.swift` - Model selection UI
- `Views/SettingsView.swift` - Settings interface
- `Utilities/Constants.swift` - App constants
- `Services/ModelManager.swift` - Model management service
- `Services/PerformanceMonitor.swift` - Performance tracking

## What's Been Completed

### ✅ Phase 0: Basic App Structure (COMPLETED)
- Created tab-based navigation with ContentView
- Implemented ChatView with streaming message support
- Built ModelListView for model selection
- Added SettingsView with generation parameters
- Created all necessary data models (ChatMessage, ModelInfo, GenerationOptions)
- Established LLMProtocol for framework abstraction
- Implemented UnifiedLLMService for framework management
- Added PerformanceMonitor for metrics tracking
- Created ModelManager for model lifecycle

### ✅ Partial Framework Setup (COMPLETED)
- Created mock implementations for 3 frameworks:
  - MockLLMService (working mock with simulated streaming)
  - LlamaCppService (skeleton only, needs real implementation)
  - CoreMLService (skeleton only, needs real implementation)  
  - MLXService (skeleton only, needs real implementation)

## What We're NOT Doing

- Not implementing model conversion tools (users will download pre-converted models)
- Not building custom tokenizers (will use framework-provided ones)
- Not creating model training capabilities
- Not implementing cloud-based inference
- Not building a model marketplace

## Implementation Approach

We'll implement each framework service following a consistent pattern:
1. Add framework dependencies via SPM or CocoaPods
2. Create service implementation conforming to LLMProtocol
3. Implement model loading and initialization
4. Add text generation with streaming support
5. Handle cleanup and memory management
6. Test with real models

## What Still Needs Implementation

### 🔴 Critical Missing Components:

1. **Real Model Loading**: All services currently use mock implementations
2. **Tokenization**: No real tokenizers implemented
3. **Actual Inference**: No framework is actually running models
4. **Model Download**: ModelDownloader exists but needs implementation
5. **7 Missing Frameworks**: Need to add MLC-LLM, ONNX Runtime, ExecuTorch, TensorFlow Lite, picoLLM, Swift Transformers, and Apple Foundation Models

### 📋 Task Breakdown by Priority:

#### Priority 1: Make ONE Framework Work End-to-End
Pick llama.cpp as the first real implementation since:
- It has the most available pre-converted models (GGUF format)
- CPU-only is fine for iOS
- Well-documented C API
- No complex dependencies

#### Priority 2: Add Model Download/Import
- Implement ModelDownloader.swift properly
- Add model verification
- Create model catalog with real download URLs
- Add import from Files functionality

#### Priority 3: Implement Remaining Frameworks
- Core ML (already has skeleton)
- MLX (already has skeleton)
- MLC-LLM
- ONNX Runtime
- Others as needed

## Phase 1: Core ML Implementation (NEEDS REAL IMPLEMENTATION)

### Overview
Implement Apple's Core ML framework for running converted neural network models with hardware acceleration.

### Current State:
- ✅ CoreMLService.swift file exists
- ❌ Still using mock implementation
- ❌ No actual Core ML model loading
- ❌ No tokenizer integration

### Changes Required:

#### 1. Update Core ML Service
**File**: `Services/CoreMLService.swift`
**Changes**: Replace mock with real Core ML implementation

```swift
import CoreML
import Vision

class CoreMLService: LLMProtocol {
    var name: String = "Core ML"
    var isInitialized: Bool = false
    
    private var model: MLModel?
    private var tokenizer: Tokenizer?
    private let maxSequenceLength = 512
    
    func initialize(modelPath: String) async throws {
        // Load Core ML model
        let modelURL = URL(fileURLWithPath: modelPath)
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
        model = try MLModel(contentsOf: modelURL, configuration: config)
        
        // Initialize tokenizer (assuming it's bundled with model)
        let tokenizerPath = modelURL.deletingLastPathComponent()
            .appendingPathComponent("tokenizer.json")
        tokenizer = try Tokenizer(configPath: tokenizerPath.path)
        
        isInitialized = true
    }
    
    func generate(prompt: String, options: GenerationOptions) async throws -> String {
        guard let model = model, let tokenizer = tokenizer else {
            throw LLMError.notInitialized
        }
        
        // Tokenize input
        let inputIds = tokenizer.encode(prompt)
        
        // Create input array
        let inputArray = try MLMultiArray(shape: [1, inputIds.count as NSNumber], dataType: .int32)
        for (index, token) in inputIds.enumerated() {
            inputArray[index] = NSNumber(value: token)
        }
        
        // Run inference
        let input = ModelInput(inputIds: inputArray)
        let output = try model.prediction(from: input)
        
        // Decode output
        return tokenizer.decode(output.tokens)
    }
    
    func streamGenerate(prompt: String, options: GenerationOptions, onToken: @escaping (String) -> Void) async throws {
        // Implement token-by-token generation
        var context = tokenizer.encode(prompt)
        
        for _ in 0..<options.maxTokens {
            let nextToken = try await generateNextToken(context: context)
            let text = tokenizer.decode([nextToken])
            onToken(text)
            
            context.append(nextToken)
            
            if nextToken == tokenizer.eosToken {
                break
            }
        }
    }
    
    func cleanup() {
        model = nil
        tokenizer = nil
        isInitialized = false
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Unit tests pass: `swift test --filter CoreMLServiceTests`
- [ ] Model loads without errors
- [ ] Memory usage stays under 2GB during inference
- [ ] No memory leaks detected in Instruments

#### Manual Verification:
- [ ] Can load and run Stable LM Core ML model
- [ ] Streaming generation displays smoothly
- [ ] App remains responsive during generation
- [ ] Proper error messages for unsupported models

---

## Phase 2: llama.cpp Integration (PRIORITY - START HERE)

### Overview
Integrate llama.cpp for efficient CPU-based inference with GGUF model support.

### Current State:
- ✅ LlamaCppService.swift file exists
- ❌ No actual llama.cpp library integrated
- ❌ Mock implementation only
- ❌ No GGUF model loading

### Changes Required:

#### 1. Add llama.cpp Dependency
**File**: `Package.swift`
**Changes**: Add llama.cpp as dependency

```swift
dependencies: [
    .package(url: "https://github.com/ggerganov/llama.cpp", branch: "master"),
]
```

#### 2. Create Bridging Header
**File**: `RunAnywhereAI-Bridging-Header.h`
**Changes**: Import llama.cpp headers

```objc
#import "llama.h"
```

#### 3. Implement llama.cpp Service
**File**: `Services/LlamaCppService.swift`
**Changes**: Full implementation with C++ interop

```swift
class LlamaCppService: LLMProtocol {
    var name: String = "llama.cpp"
    var isInitialized: Bool = false
    
    private var context: OpaquePointer?
    private var model: OpaquePointer?
    
    func initialize(modelPath: String) async throws {
        // Initialize backend
        llama_backend_init()
        
        // Model parameters
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 0 // CPU only on iOS
        
        // Load model
        model = llama_load_model_from_file(modelPath, modelParams)
        guard model != nil else {
            throw LLMError.modelLoadFailed
        }
        
        // Context parameters
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 2048
        contextParams.n_threads = Int32(ProcessInfo.processInfo.processorCount)
        
        // Create context
        context = llama_new_context_with_model(model, contextParams)
        guard context != nil else {
            throw LLMError.contextCreationFailed
        }
        
        isInitialized = true
    }
    
    func streamGenerate(prompt: String, options: GenerationOptions, onToken: @escaping (String) -> Void) async throws {
        guard let context = context, let model = model else {
            throw LLMError.notInitialized
        }
        
        // Tokenize prompt
        let tokens = tokenize(prompt)
        
        // Prepare batch
        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        defer { llama_batch_free(batch) }
        
        // Add tokens to batch
        for (i, token) in tokens.enumerated() {
            llama_batch_add(&batch, token, Int32(i), [0], false)
        }
        
        // Generation loop
        for _ in 0..<options.maxTokens {
            // Decode batch
            if llama_decode(context, batch) != 0 {
                throw LLMError.decodeFailed
            }
            
            // Sample next token
            let newToken = sampleToken(context: context, options: options)
            
            // Check for end
            if newToken == llama_token_eos(model) {
                break
            }
            
            // Decode to text
            let text = detokenize([newToken])
            onToken(text)
            
            // Prepare next batch
            llama_batch_clear(&batch)
            llama_batch_add(&batch, newToken, Int32(batch.n_tokens), [0], true)
        }
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] GGUF model loads successfully
- [ ] Tokenization matches expected output
- [ ] Generation produces coherent text
- [ ] Memory usage appropriate for model size

#### Manual Verification:
- [ ] Can run Llama 3.2 3B GGUF model
- [ ] Text generation quality is good
- [ ] CPU usage is reasonable
- [ ] No app crashes during extended use

---

## Phase 3: MLX Framework Implementation

### Overview
Implement Apple's MLX framework for optimized inference on Apple Silicon.

### Current State:
- ✅ MLXService.swift file exists
- ❌ No MLX packages added
- ❌ Mock implementation only
- ❌ No model loading or inference

### Changes Required:

#### 1. Add MLX Dependencies
**File**: `Package.swift`
**Changes**: Add MLX packages

```swift
dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.26.0"),
    .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "0.26.0"),
],
targets: [
    .target(
        name: "RunAnywhereAI",
        dependencies: [
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXNN", package: "mlx-swift"),
            .product(name: "LLM", package: "mlx-swift-examples"),
        ]
    )
]
```

#### 2. Implement MLX Service
**File**: `Services/MLXService.swift`
**Changes**: Full MLX implementation

```swift
import MLX
import MLXNN
import MLXLLM

class MLXService: LLMProtocol {
    var name: String = "MLX"
    var isInitialized: Bool = false
    
    private var model: LLMModel?
    private var tokenizer: Tokenizer?
    
    func initialize(modelPath: String) async throws {
        // Load model configuration
        let config = try await ModelConfiguration.load(from: modelPath)
        
        // Initialize model
        model = try LLMModel(configuration: config)
        
        // Load weights
        try await model?.loadWeights(from: modelPath)
        
        // Load tokenizer
        tokenizer = try await Tokenizer.load(from: modelPath)
        
        isInitialized = true
    }
    
    func streamGenerate(prompt: String, options: GenerationOptions, onToken: @escaping (String) -> Void) async throws {
        guard let model = model, let tokenizer = tokenizer else {
            throw LLMError.notInitialized
        }
        
        // Tokenize prompt
        let tokens = tokenizer.encode(prompt)
        var inputTokens = MLXArray(tokens)
        
        // KV cache for efficiency
        var cache = KVCache()
        
        // Generate tokens
        for _ in 0..<options.maxTokens {
            // Forward pass with cache
            let (logits, newCache) = model(inputTokens, cache: cache)
            cache = newCache
            
            // Sample next token
            let nextToken = sampleToken(
                logits: logits,
                temperature: options.temperature,
                topP: options.topP
            )
            
            // Decode and yield
            let text = tokenizer.decode([nextToken])
            onToken(text)
            
            // Update input
            inputTokens = MLXArray([nextToken])
            
            // Check for end token
            if nextToken == tokenizer.eosToken {
                break
            }
        }
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] MLX model loads and initializes
- [ ] Inference runs without errors
- [ ] GPU utilization is detected
- [ ] Memory management is efficient

#### Manual Verification:
- [ ] Can run Mistral 7B MLX model
- [ ] Generation speed is faster than CPU-only
- [ ] Quality matches expected output
- [ ] No thermal throttling issues

---

## Phase 4: Additional Framework Implementations

### Overview
Implement the remaining 7 frameworks that don't exist yet:

### Missing Frameworks:
1. **MLC-LLM** - No file exists yet
2. **ONNX Runtime** - No file exists yet
3. **ExecuTorch** - No file exists yet
4. **TensorFlow Lite** - No file exists yet
5. **picoLLM** - No file exists yet
6. **Swift Transformers** - No file exists yet
7. **Apple Foundation Models** (iOS 18+) - No file exists yet

### MLC-LLM Service
**File**: `Services/MLCService.swift`

```swift
import MLCSwift

class MLCService: LLMProtocol {
    private var engine: MLCEngine?
    
    func initialize(modelPath: String) async throws {
        let config = MLCEngineConfig(
            model: modelPath,
            modelLib: "model_iphone",
            device: .auto
        )
        
        engine = try await MLCEngine(config: config)
        isInitialized = true
    }
    
    func streamGenerate(prompt: String, options: GenerationOptions, onToken: @escaping (String) -> Void) async throws {
        let request = ChatCompletionRequest(
            messages: [ChatMessage(role: .user, content: prompt)],
            temperature: options.temperature,
            maxTokens: options.maxTokens,
            stream: true
        )
        
        for try await chunk in engine!.streamChatCompletion(request) {
            if let content = chunk.choices.first?.delta.content {
                onToken(content)
            }
        }
    }
}
```

### ONNX Runtime Service
**File**: `Services/ONNXService.swift`

```swift
import onnxruntime_objc

class ONNXService: LLMProtocol {
    private var session: ORTSession?
    private var env: ORTEnv?
    
    func initialize(modelPath: String) async throws {
        env = try ORTEnv(loggingLevel: .warning)
        
        let sessionOptions = try ORTSessionOptions()
        try sessionOptions.setGraphOptimizationLevel(.ortEnableAll)
        
        // Add CoreML provider for acceleration
        let coreMLOptions = ORTCoreMLExecutionProviderOptions()
        try sessionOptions.appendCoreMLExecutionProvider(with: coreMLOptions)
        
        session = try ORTSession(env: env!, modelPath: modelPath, sessionOptions: sessionOptions)
        isInitialized = true
    }
}
```

### Success Criteria (All Frameworks):

#### Automated Verification:
- [ ] Each framework service compiles without errors
- [ ] Unit tests pass for each service
- [ ] Model loading succeeds for supported formats
- [ ] Memory limits are respected

#### Manual Verification:
- [ ] Each framework can generate text
- [ ] Performance metrics are collected
- [ ] Framework switching works smoothly
- [ ] Error handling is robust

---

## Phase 5: Model Management & Download

### Overview
Implement real model downloading, caching, and management functionality.

### Current State:
- ✅ ModelManager.swift exists with basic structure
- ✅ ModelListView shows model selection UI
- ❌ No actual download implementation
- ❌ No model verification
- ❌ No real model URLs or catalog

### Changes Required:

#### 1. Model Downloader Implementation
**File**: `Services/ModelDownloader.swift`

```swift
class ModelDownloader: ObservableObject {
    @Published var downloadProgress: [String: Float] = [:]
    @Published var isDownloading: [String: Bool] = [:]
    
    func downloadModel(_ model: ModelInfo) async throws -> URL {
        let destination = getModelPath(for: model)
        
        // Check if already exists
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        
        // Create download task
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: model.downloadURL)
        
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw DownloadError.invalidResponse
        }
        
        let expectedSize = response.expectedContentLength
        var downloadedSize: Int64 = 0
        
        // Create file
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: destination)
        
        // Download with progress
        for try await chunk in asyncBytes {
            try fileHandle.write(contentsOf: chunk)
            downloadedSize += Int64(chunk.count)
            
            if expectedSize > 0 {
                let progress = Float(downloadedSize) / Float(expectedSize)
                await MainActor.run {
                    downloadProgress[model.id] = progress
                }
            }
        }
        
        try fileHandle.close()
        
        // Verify download
        try verifyModel(at: destination, for: model)
        
        return destination
    }
    
    private func verifyModel(at url: URL, for model: ModelInfo) throws {
        // Verify file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        guard fileSize > 0 else {
            throw DownloadError.invalidFile
        }
        
        // Verify format-specific headers
        switch model.format {
        case .gguf:
            try verifyGGUFHeader(at: url)
        case .mlpackage:
            try verifyCoreMLPackage(at: url)
        default:
            break
        }
    }
}
```

#### 2. Model Import from Files
**File**: `Views/ModelImportView.swift`

```swift
struct ModelImportView: View {
    @State private var isImporting = false
    @StateObject private var modelManager = ModelManager.shared
    
    var body: some View {
        VStack {
            Button("Import Model from Files") {
                isImporting = true
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.gguf, .onnx, .mlmodel],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task {
                            await importModel(from: url)
                        }
                    }
                case .failure(let error):
                    print("Import error: \(error)")
                }
            }
        }
    }
    
    private func importModel(from url: URL) async {
        // Copy to app's model directory
        let modelName = url.lastPathComponent
        let destination = ModelManager.modelsDirectory.appendingPathComponent(modelName)
        
        do {
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                
                try FileManager.default.copyItem(at: url, to: destination)
                
                // Create model info
                let modelInfo = ModelInfo(
                    id: UUID().uuidString,
                    name: modelName,
                    path: destination.path,
                    format: detectFormat(from: modelName),
                    size: getFileSize(at: destination)
                )
                
                await modelManager.addImportedModel(modelInfo)
            }
        } catch {
            print("Failed to import model: \(error)")
        }
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Download progress updates correctly
- [ ] File verification passes for valid models
- [ ] Import creates proper model entries
- [ ] Disk space is checked before download

#### Manual Verification:
- [ ] Can download models from Hugging Face
- [ ] Progress bar shows accurate progress
- [ ] Import from Files app works
- [ ] Models persist across app launches

---

## Phase 6: Testing & Polish

### Overview
Comprehensive testing, performance optimization, and polish.

### Testing Strategy:

#### 1. Framework-Specific Tests
**File**: `Tests/FrameworkTests.swift`

```swift
class FrameworkTests: XCTestCase {
    func testCoreMLService() async throws {
        let service = CoreMLService()
        let modelPath = Bundle.test.path(forResource: "test_model", ofType: "mlpackage")!
        
        try await service.initialize(modelPath: modelPath)
        XCTAssertTrue(service.isInitialized)
        
        let result = try await service.generate(
            prompt: "Hello",
            options: GenerationOptions(maxTokens: 10)
        )
        
        XCTAssertFalse(result.isEmpty)
    }
    
    // Similar tests for each framework...
}
```

#### 2. Performance Benchmarks
**File**: `Services/BenchmarkRunner.swift`

```swift
class BenchmarkRunner {
    func runComprehensiveBenchmark() async -> [BenchmarkResult] {
        let testPrompts = [
            "Short prompt",
            "Medium length prompt with more context to process",
            "Very long prompt " + String(repeating: "with lots of text ", count: 50)
        ]
        
        var results: [BenchmarkResult] = []
        
        for framework in LLMFramework.allCases {
            for model in getCompatibleModels(for: framework) {
                let result = await benchmarkConfiguration(
                    framework: framework,
                    model: model,
                    prompts: testPrompts
                )
                results.append(result)
            }
        }
        
        return results
    }
}
```

### Performance Optimizations:

1. **Memory Management**
   - Implement aggressive cleanup after each generation
   - Monitor memory warnings and reduce cache sizes
   - Use autoreleasepool for batch operations

2. **Thermal Management**
   - Monitor thermal state
   - Reduce thread count when device is warm
   - Implement generation throttling

3. **Battery Optimization**
   - Reduce generation frequency on low battery
   - Use efficient frameworks when unplugged
   - Implement power-aware scheduling

### Success Criteria:

#### Automated Verification:
- [ ] All framework tests pass
- [ ] No memory leaks in Instruments
- [ ] Performance benchmarks complete
- [ ] Code coverage > 80%

#### Manual Verification:
- [ ] App runs for 30+ minutes without issues
- [ ] All frameworks work with real models
- [ ] UI remains responsive during generation
- [ ] Error messages are user-friendly

---

## Summary of Current State vs. Plan

### What Was Planned:
- 10 different LLM framework implementations
- Real model inference on iOS
- Model downloading and management
- Performance benchmarking

### What Actually Exists:
- ✅ Complete UI and app structure
- ✅ Mock implementation that simulates the experience
- ✅ 3 framework skeletons (llama.cpp, Core ML, MLX)
- ❌ No real model inference
- ❌ No actual framework integration
- ❌ 7 frameworks not even started
- ❌ No model downloading

### Recommended Next Steps:
1. **Start with llama.cpp** - Add the real library and implement actual GGUF model loading
2. **Add a real tokenizer** - llama.cpp includes tokenization
3. **Test with TinyLlama** - Small model good for testing
4. **Then expand** - Once one framework works, use it as a template

## Migration Notes

For users upgrading from the mock implementation:
1. Download real models from the Models tab (once implemented)
2. Existing conversations will be preserved
3. Performance will vary based on device and model
4. Some frameworks require specific model formats

## Performance Considerations

- **Memory Usage**: Expect 1-4GB depending on model size
- **CPU Usage**: 50-100% during generation is normal
- **Battery Impact**: Significant, recommend plugged-in usage
- **Thermal**: Extended use may cause device warming

## References

- Original init plan: `examples/ios/RunAnywhereAI/docs/plans/init_plan.md`
- Framework guide: `examples/ios/RunAnywhereAI/docs/plans/LOCAL_LLM_SAMPLE_APP_IMPLEMENTATION.md`
- Apple Core ML: https://developer.apple.com/documentation/coreml
- llama.cpp: https://github.com/ggerganov/llama.cpp
- MLX: https://github.com/ml-explore/mlx-swift