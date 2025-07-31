# LLM Framework Lifecycle Analysis & Unified Interface Architecture

## Executive Summary

This document provides a comprehensive analysis of all LLM frameworks integrated in the RunAnywhereAI iOS application, documenting their complete lifecycles, identifying gaps and opportunities for improvement, and proposing a unified interface architecture.

## Table of Contents

1. [Framework Overview](#framework-overview)
2. [Framework Lifecycle Analysis](#framework-lifecycle-analysis)
3. [Common Patterns & Denominators](#common-patterns--denominators)
4. [Gaps & Opportunities](#gaps--opportunities)
5. [Unified Interface Architecture Proposal](#unified-interface-architecture-proposal)
6. [Implementation Plan](#implementation-plan)

## Framework Overview

### Currently Implemented Frameworks

#### Core Frameworks (Active)
1. **Core ML** - Apple's neural network framework
2. **TensorFlow Lite** - Google's mobile inference framework
3. **MLX** - Apple's array framework for Apple Silicon
4. **Swift Transformers** - Hugging Face's native Swift implementation
5. **ONNX Runtime** - Microsoft's cross-platform inference framework

#### Deferred Frameworks (Dependency/License Issues)
1. **ExecuTorch** - PyTorch's on-device framework (Active but needs bundled models)
2. **llama.cpp** - High-performance C++ inference (Version conflicts)
3. **MLC-LLM** - Universal deployment solution (Manual integration required)
4. **picoLLM** - Ultra-compressed models (Proprietary license required)

### Framework Comparison Matrix

| Framework | Status | Formats | Quantization | Hardware Acceleration | Auth Required |
|-----------|--------|---------|--------------|----------------------|---------------|
| Core ML | ✅ Active | .mlmodel, .mlpackage | FP16, INT8 | Neural Engine, GPU | No |
| TensorFlow Lite | ✅ Active | .tflite | INT4, INT8, FP16 | CoreML delegate, Metal | No* |
| MLX | ✅ Active | .safetensors, .npz | INT4, INT8, FP16 | Metal, MPS | No |
| Swift Transformers | ✅ Active | .mlmodel, .mlpackage | FP16, INT8 | Neural Engine | No |
| ONNX Runtime | ✅ Active | .onnx, .ort | INT4, INT8 | CoreML, CPU | No |
| ExecuTorch | ✅ Active | .pte | INT4, INT8, FP16 | CPU, GPU, NE | No |
| llama.cpp | ⏸️ Deferred | .gguf, .ggml | Q4_K_M, Q5_K_M, etc | Metal, CPU | No |
| MLC-LLM | ⏸️ Deferred | .tar, directory | Various | Auto-detection | No |
| picoLLM | ⏸️ Deferred | .pllm | Proprietary | CPU optimized | Yes |

*Note: Some TensorFlow Lite models require Kaggle authentication

## Framework Lifecycle Analysis

### 1. Core ML Framework Lifecycle

#### Download Stage
- **Format**: .mlmodel (single file) or .mlpackage (directory)
- **Providers**: Apple ML Assets, Hugging Face
- **Auth**: None required
- **Challenges**: 
  - .mlpackage files are directories requiring special handling
  - Large file sizes (often 1-4GB)
  - No built-in compression

#### Extract Stage
- **Process**: Direct use for .mlmodel, directory structure for .mlpackage
- **Challenges**: 
  - Directory-based models need proper path handling
  - No extraction needed but validation required

#### Initialize Stage
- **Process**:
  1. Verify model format (handler checks)
  2. Configure MLModelConfiguration (compute units)
  3. Compile .mlmodel to .mlmodelc if needed
  4. Check device capabilities (Neural Engine availability)
- **Challenges**:
  - Compilation can take several minutes for large models
  - Memory spike during compilation
  - iOS version requirements (iOS 17+ for stateful models)

#### Load Stage
- **Process**:
  1. Load compiled model with MLModel API
  2. Create model-specific adapter (GPT2CoreMLAdapter, etc.)
  3. Initialize tokenizer adapter
  4. Verify inputs/outputs match expected structure
- **Challenges**:
  - Model-specific adapters needed for different architectures
  - Tokenizer must be loaded separately
  - Memory management critical

#### Execute Stage
- **Process**:
  1. Tokenize input using adapter
  2. Create MLMultiArray inputs
  3. Run prediction
  4. Sample from output logits
  5. Decode tokens back to text
- **Challenges**:
  - Autoregressive generation requires loop management
  - Context window limitations
  - Temperature sampling implementation

### 2. TensorFlow Lite Framework Lifecycle

#### Download Stage
- **Format**: .tflite
- **Providers**: Google Storage, Kaggle (auth required)
- **Auth**: Some models require Kaggle credentials
- **Challenges**:
  - Kaggle models need API key configuration
  - Some models come as .tar.gz archives

#### Extract Stage
- **Process**: Direct use for .tflite, extraction for archives
- **Challenges**:
  - tar.gz extraction not implemented on iOS
  - Multiple files in archives (model + config)

#### Initialize Stage
- **Process**:
  1. Create Interpreter.Options
  2. Configure delegates (CoreML, Metal)
  3. Set thread count and optimization level
  4. Create Interpreter instance
  5. Allocate tensors
- **Challenges**:
  - Delegate selection based on device capabilities
  - CocoaPods dependency management
  - Framework availability checks

#### Load Stage
- **Process**:
  1. Load model file into interpreter
  2. Get input/output tensor information
  3. Initialize tokenizer (often embedded)
- **Challenges**:
  - Different tensor layouts than other frameworks
  - Limited model variety for LLMs

#### Execute Stage
- **Process**:
  1. Prepare input data matching tensor shape
  2. Copy data to input tensor
  3. Invoke interpreter
  4. Extract and process output
- **Challenges**:
  - Manual tensor shape management
  - Complex output decoding
  - Performance optimization

### 3. MLX Framework Lifecycle

#### Download Stage
- **Format**: .safetensors, .npz, directories
- **Providers**: mlx-community on Hugging Face
- **Auth**: None required
- **Challenges**:
  - Models often split across multiple files
  - Large directory structures
  - Config files needed separately

#### Extract Stage
- **Process**: tar.gz extraction for archives
- **Challenges**:
  - iOS lacks native tar.gz support
  - Complex directory structures
  - Multiple required files (weights, config, tokenizer)

#### Initialize Stage
- **Process**:
  1. Check Apple Silicon compatibility
  2. Locate model directory and files
  3. Create MLXModelWrapper
  4. Initialize with GPU support
- **Challenges**:
  - Device compatibility (A17 Pro/M3+ preferred)
  - Framework not available via SPM initially
  - Complex model directory structure

#### Load Stage
- **Process**:
  1. Load weights and config
  2. Initialize MLX arrays
  3. Set up tokenizer
- **Challenges**:
  - Memory management for large models
  - GPU memory allocation
  - Tokenizer compatibility

#### Execute Stage
- **Process**:
  1. Create MLX arrays from tokens
  2. Perform forward pass
  3. Sample using MLX operations
  4. Decode output tokens
- **Challenges**:
  - Unified memory architecture utilization
  - Efficient array operations
  - Real-time performance

### 4. Swift Transformers Framework Lifecycle

#### Download Stage
- **Format**: .mlmodel, .mlpackage (Core ML based)
- **Providers**: Hugging Face (apple/, corenet-community/)
- **Auth**: None required (public models)
- **Challenges**:
  - Models must be specifically converted for Swift Transformers
  - Limited model availability
  - Large file sizes

#### Extract Stage
- **Process**: Same as Core ML (direct or directory)
- **Challenges**:
  - Directory-based models common
  - Metadata requirements

#### Initialize Stage
- **Process**:
  1. Verify model compatibility (metadata check)
  2. Check for required inputs (input_ids)
  3. Compile if needed
  4. Configure compute units
- **Challenges**:
  - Strict model requirements
  - Not all Core ML models compatible
  - Crash-prone if wrong model format

#### Load Stage
- **Process**:
  1. Use LanguageModel.loadCompiled
  2. Model validates internal structure
  3. Tokenizer embedded in model
- **Challenges**:
  - Array bounds exceptions if incompatible
  - Limited error messages
  - Framework expectations rigid

#### Execute Stage
- **Process**:
  1. Use built-in generation config
  2. Simple generate() API
  3. Streaming via callback
- **Challenges**:
  - Less control over generation
  - Fixed tokenization
  - Limited customization

### 5. ONNX Runtime Framework Lifecycle

#### Download Stage
- **Format**: .onnx, .ort
- **Providers**: Microsoft, Hugging Face
- **Auth**: None required
- **Challenges**:
  - Model size variations
  - Quantization format differences

#### Extract Stage
- **Process**: Direct use, no extraction needed
- **Challenges**: None significant

#### Initialize Stage
- **Process**:
  1. Create ORTEnv
  2. Configure session options
  3. Add execution providers (CoreML, CPU)
  4. Set optimization level
- **Challenges**:
  - SPM integration issues
  - Provider selection
  - Thread configuration

#### Load Stage
- **Process**:
  1. Create ORTSession with model
  2. Get input/output names
  3. Initialize tokenizer
- **Challenges**:
  - Session configuration complexity
  - Memory management
  - Provider compatibility

#### Execute Stage
- **Process**:
  1. Create ORTValue tensors
  2. Run session with inputs
  3. Process outputs
- **Challenges**:
  - Tensor creation overhead
  - Output processing complexity
  - Performance optimization

### 6. ExecuTorch Framework Lifecycle

#### Download Stage
- **Format**: .pte (PyTorch Edge)
- **Providers**: executorch-community on Hugging Face
- **Auth**: None required
- **Challenges**:
  - Limited model availability
  - New format, less tooling

#### Extract Stage
- **Process**: Direct use
- **Challenges**: None

#### Initialize Stage
- **Process**:
  1. Create Module instance
  2. Load model file
  3. Find tokenizer files
- **Challenges**:
  - Module API differences
  - Backend selection
  - Tokenizer separation

#### Load Stage
- **Process**:
  1. Module.load("forward")
  2. Initialize tokenizer
  3. Select optimal backend
- **Challenges**:
  - Limited documentation
  - Backend configuration
  - Memory constraints

#### Execute Stage
- **Process**:
  1. Manual token generation loop
  2. Module.forward() calls
  3. Custom sampling logic
- **Challenges**:
  - Low-level API
  - Manual generation loop
  - Performance tuning

## Common Patterns & Denominators

### Universal Lifecycle Stages

1. **Discovery** → 2. **Download** → 3. **Extract** → 4. **Validate** → 5. **Initialize** → 6. **Load** → 7. **Execute** → 8. **Cleanup**

### Common Requirements

1. **Model Discovery**
   - Registry of available models
   - Metadata (size, format, requirements)
   - Compatibility checking

2. **Download Management**
   - Progress tracking
   - Resume capability
   - Storage verification
   - Checksum validation

3. **Format Handling**
   - Single file vs directory
   - Compressed archives
   - Multiple component files

4. **Initialization**
   - Framework setup
   - Hardware configuration
   - Memory allocation

5. **Model Loading**
   - File/directory loading
   - Compilation if needed
   - Tokenizer initialization

6. **Inference**
   - Input preparation
   - Forward pass
   - Output processing
   - Token generation

7. **Resource Management**
   - Memory cleanup
   - Cache management
   - State persistence

### Common Challenges

1. **Tokenization**
   - Each framework has different tokenizer requirements
   - Some embed tokenizers, others need separate files
   - Format incompatibilities

2. **Memory Management**
   - Large model sizes
   - Loading spikes
   - iOS memory limits

3. **Hardware Utilization**
   - Different acceleration options
   - Framework-specific optimizations
   - Device capability detection

4. **Error Handling**
   - Inconsistent error types
   - Poor error messages
   - Silent failures

5. **Progress Tracking**
   - Multiple stages to track
   - Different timing characteristics
   - User feedback requirements

## Gaps & Opportunities

### Current Architecture Gaps

1. **Fragmented Lifecycle Management**
   - Each service implements its own lifecycle
   - No consistent state machine
   - Duplicate code across services

2. **Inconsistent Error Handling**
   - Different error types per framework
   - No unified error recovery
   - Poor user feedback

3. **Tokenizer Chaos**
   - Multiple tokenizer implementations
   - No unified tokenizer interface
   - Manual adapter creation

4. **Model Discovery Issues**
   - Models defined in multiple places
   - No dynamic model discovery
   - Hard-coded model lists

5. **Download Management**
   - Basic download implementation
   - No proper queue management
   - Limited error recovery

6. **Memory Management**
   - No coordinated memory management
   - Framework-specific approaches
   - No memory pressure handling

7. **Progress Tracking**
   - Inconsistent progress reporting
   - No unified progress interface
   - Missing stage information

8. **Hardware Optimization**
   - Manual hardware detection
   - No dynamic optimization
   - Framework-specific approaches

### Improvement Opportunities

1. **Unified Lifecycle Manager**
   - State machine for model lifecycle
   - Consistent stage progression
   - Framework-agnostic implementation

2. **Smart Model Loader**
   - Automatic format detection
   - Framework selection based on model
   - Optimal hardware utilization

3. **Universal Tokenizer System**
   - Plugin-based tokenizer architecture
   - Automatic tokenizer discovery
   - Format conversion utilities

4. **Enhanced Download System**
   - Queue-based downloads
   - Automatic retry with backoff
   - Parallel download support

5. **Intelligent Memory Manager**
   - Predictive memory allocation
   - Automatic model unloading
   - Memory pressure responses

6. **Unified Progress System**
   - Stage-based progress tracking
   - Time estimation
   - Detailed status updates

7. **Dynamic Model Registry**
   - Runtime model discovery
   - Capability-based filtering
   - Automatic compatibility checking

8. **Hardware Abstraction Layer**
   - Unified hardware capabilities API
   - Automatic optimization selection
   - Performance profiling

## Unified Interface Architecture Proposal

### Core Components

#### 1. Model Lifecycle Manager

```swift
protocol ModelLifecycleManager {
    // Lifecycle state machine
    var currentState: ModelLifecycleState { get }
    var stateHistory: [ModelLifecycleTransition] { get }
    
    // State transitions
    func transitionTo(_ state: ModelLifecycleState) async throws
    func canTransitionTo(_ state: ModelLifecycleState) -> Bool
    
    // Observers
    func addObserver(_ observer: ModelLifecycleObserver)
    func removeObserver(_ observer: ModelLifecycleObserver)
}

enum ModelLifecycleState {
    case uninitialized
    case discovered(ModelMetadata)
    case downloading(progress: Double)
    case downloaded(location: URL)
    case extracting
    case extracted(location: URL)
    case validating
    case validated
    case initializing
    case initialized
    case loading
    case loaded
    case ready
    case executing
    case error(Error)
    case cleanup
}
```

#### 2. Unified Model Loader

```swift
protocol UnifiedModelLoader {
    // Model operations
    func loadModel(_ model: ModelInfo) async throws -> LoadedModel
    func unloadModel(_ modelId: String) async throws
    func isModelLoaded(_ modelId: String) -> Bool
    
    // Framework detection
    func detectOptimalFramework(for model: ModelInfo) -> LLMFramework
    func canLoad(_ model: ModelInfo, with framework: LLMFramework) -> Bool
    
    // Resource management
    func estimateMemoryRequirement(_ model: ModelInfo) -> Int64
    func checkAvailableResources() -> ResourceAvailability
}

struct LoadedModel {
    let id: String
    let framework: LLMFramework
    let service: LLMService
    let tokenizer: UnifiedTokenizer
    let metadata: ModelMetadata
}
```

#### 3. Universal Tokenizer Interface

```swift
protocol UnifiedTokenizer {
    // Core operations
    func encode(_ text: String) -> [Int]
    func decode(_ tokens: [Int]) -> String
    func decodeToken(_ token: Int) -> String
    
    // Properties
    var vocabularySize: Int { get }
    var bosToken: Int? { get }
    var eosToken: Int? { get }
    var padToken: Int? { get }
    
    // Configuration
    var maxLength: Int { get }
    var truncationStrategy: TruncationStrategy { get }
}

protocol TokenizerProvider {
    func createTokenizer(for model: ModelInfo) async throws -> UnifiedTokenizer
    func downloadTokenizerFiles(for model: ModelInfo) async throws
    var supportedFormats: [TokenizerFormat] { get }
}
```

#### 4. Model Discovery & Registry

```swift
protocol ModelRegistry {
    // Discovery
    func discoverModels() async -> [ModelInfo]
    func searchModels(query: String) async -> [ModelInfo]
    func getModelInfo(id: String) -> ModelInfo?
    
    // Filtering
    func filterModels(by criteria: ModelCriteria) -> [ModelInfo]
    func getCompatibleModels(for device: DeviceInfo) -> [ModelInfo]
    
    // Registration
    func registerModel(_ model: ModelInfo)
    func unregisterModel(_ modelId: String)
    func updateModel(_ model: ModelInfo)
}

struct ModelCriteria {
    var framework: LLMFramework?
    var maxSize: Int64?
    var minContextLength: Int?
    var quantization: [QuantizationFormat]?
    var hardwareRequirements: [HardwareAcceleration]?
}
```

#### 5. Download & Storage Manager

```swift
protocol ModelStorageManager {
    // Download operations
    func downloadModel(_ model: ModelInfo) async throws -> DownloadTask
    func pauseDownload(_ taskId: String)
    func resumeDownload(_ taskId: String)
    func cancelDownload(_ taskId: String)
    
    // Storage operations
    func storeModel(_ data: Data, for model: ModelInfo) async throws -> URL
    func deleteModel(_ modelId: String) async throws
    func moveModel(_ modelId: String, to location: URL) async throws
    
    // Query operations
    func getStoredModels() -> [StoredModel]
    func getModelLocation(_ modelId: String) -> URL?
    func calculateStorageUsed() -> Int64
}

struct DownloadTask {
    let id: String
    let modelId: String
    let progress: AsyncStream<DownloadProgress>
    let result: Task<URL, Error>
}
```

#### 6. Hardware Abstraction Layer

```swift
protocol HardwareCapabilities {
    // Detection
    var availableAccelerators: [HardwareAcceleration] { get }
    var totalMemory: Int64 { get }
    var availableMemory: Int64 { get }
    var supportedQuantizations: [QuantizationFormat] { get }
    
    // Optimization
    func recommendedConfiguration(for model: ModelInfo) -> HardwareConfiguration
    func canRun(_ model: ModelInfo) -> Bool
    func estimatePerformance(_ model: ModelInfo) -> PerformanceEstimate
}

struct HardwareConfiguration {
    let accelerator: HardwareAcceleration
    let threads: Int
    let memoryLimit: Int64
    let powerMode: PowerMode
}
```

#### 7. Unified Progress Tracking

```swift
protocol ProgressTracker {
    // Progress reporting
    func reportProgress(_ progress: StageProgress)
    func getCurrentProgress() -> OverallProgress
    
    // Stage management
    func startStage(_ stage: LifecycleStage)
    func completeStage(_ stage: LifecycleStage)
    func failStage(_ stage: LifecycleStage, error: Error)
    
    // Observers
    func addProgressObserver(_ observer: ProgressObserver)
    func removeProgressObserver(_ observer: ProgressObserver)
}

struct StageProgress {
    let stage: LifecycleStage
    let progress: Double
    let message: String
    let estimatedTimeRemaining: TimeInterval?
}

enum LifecycleStage {
    case discovery
    case download
    case extraction
    case validation
    case initialization
    case loading
    case ready
}
```

### Integration Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐   │
│  │   Chat UI   │  │  Models View │  │  Settings View  │   │
│  └─────────────┘  └──────────────┘  └─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                 Unified LLM Service Layer                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │            UnifiedLLMService (Facade)                │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│              Model Lifecycle Management Layer                │
│  ┌──────────────┐  ┌────────────────┐  ┌──────────────┐   │
│  │  Lifecycle   │  │  Model Loader  │  │  Progress    │   │
│  │   Manager    │  │   (Unified)    │  │   Tracker    │   │
│  └──────────────┘  └────────────────┘  └──────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                  Core Services Layer                         │
│  ┌──────────────┐  ┌────────────────┐  ┌──────────────┐   │
│  │   Model      │  │   Download     │  │  Hardware    │   │
│  │  Registry    │  │    Manager     │  │   Manager    │   │
│  └──────────────┘  └────────────────┘  └──────────────┘   │
│  ┌──────────────┐  ┌────────────────┐  ┌──────────────┐   │
│  │  Tokenizer   │  │    Memory      │  │   Storage    │   │
│  │   Manager    │  │    Manager     │  │   Manager    │   │
│  └──────────────┘  └────────────────┘  └──────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│               Framework Adapters Layer                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ Core ML  │ │  TFLite  │ │   MLX    │ │Swift Trans.  │  │
│  │ Adapter  │ │ Adapter  │ │ Adapter  │ │   Adapter    │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │   ONNX   │ │ExecuTorch│ │llama.cpp │ │  MLC-LLM     │  │
│  │ Adapter  │ │ Adapter  │ │ Adapter  │ │   Adapter    │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│              Native Framework Layer                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ Core ML  │ │TensorFlow│ │   MLX    │ │    Swift     │  │
│  │Framework │ │   Lite   │ │Framework │ │Transformers  │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Separation of Concerns**
   - Each layer has clear responsibilities
   - No framework-specific code above adapter layer
   - Clean interfaces between layers

2. **Dependency Inversion**
   - High-level modules don't depend on low-level modules
   - Both depend on abstractions (protocols)
   - Framework adapters implement common protocols

3. **Open/Closed Principle**
   - Open for extension (new frameworks)
   - Closed for modification (core logic unchanged)
   - Plugin architecture for frameworks

4. **Single Responsibility**
   - Each component has one reason to change
   - Lifecycle manager only handles state
   - Tokenizer manager only handles tokenization

5. **Interface Segregation**
   - Multiple focused protocols
   - Services implement only what they need
   - No "fat" interfaces

## Implementation Plan

### Phase 1: Foundation (Weeks 1-2)
1. Create protocol definitions
2. Implement ModelLifecycleManager
3. Create UnifiedTokenizer interface
4. Build HardwareCapabilities detection

### Phase 2: Core Services (Weeks 3-4)
1. Implement ModelRegistry with dynamic discovery
2. Build enhanced DownloadManager
3. Create MemoryManager with pressure handling
4. Implement ProgressTracker

### Phase 3: Framework Adapters (Weeks 5-6)
1. Create base FrameworkAdapter class
2. Implement adapters for each framework
3. Standardize error handling
4. Add comprehensive logging

### Phase 4: Integration (Weeks 7-8)
1. Integrate with existing UnifiedLLMService
2. Update UI to use new architecture
3. Migrate existing models
4. Add backward compatibility

### Phase 5: Testing & Optimization (Weeks 9-10)
1. Unit tests for all components
2. Integration tests
3. Performance optimization
4. Memory leak detection

### Migration Strategy

1. **Parallel Implementation**
   - Keep existing services working
   - Implement new architecture alongside
   - Switch over when ready

2. **Gradual Migration**
   - Start with one framework (Core ML)
   - Validate approach
   - Migrate others incrementally

3. **Feature Flags**
   - Use flags to toggle new implementation
   - A/B test performance
   - Rollback capability

## Specific Implementation Recommendations

### 1. Immediate Fixes

1. **Tokenizer Consolidation**
   ```swift
   // Create TokenizerRegistry
   class TokenizerRegistry {
       static let shared = TokenizerRegistry()
       private var tokenizers: [String: UnifiedTokenizer] = [:]
       
       func register(_ tokenizer: UnifiedTokenizer, for modelId: String) {
           tokenizers[modelId] = tokenizer
       }
   }
   ```

2. **Error Standardization**
   ```swift
   enum UnifiedLLMError: LocalizedError {
       case lifecycle(stage: LifecycleStage, underlying: Error)
       case framework(name: String, error: Error)
       case resource(type: ResourceType, reason: String)
       // ... comprehensive error cases
   }
   ```

3. **Progress Unification**
   ```swift
   class UnifiedProgressReporter {
       private let progressSubject = PassthroughSubject<ProgressUpdate, Never>()
       
       func report(stage: LifecycleStage, progress: Double, message: String) {
           // Unified progress reporting
       }
   }
   ```

### 2. Model Format Handlers

```swift
// Enhance existing ModelFormatHandler
protocol EnhancedModelFormatHandler: ModelFormatHandler {
    func extractModel(from archive: URL) async throws -> URL
    func validateModel(at url: URL) async throws -> ValidationResult
    func prepareForFramework(_ framework: LLMFramework, at url: URL) async throws -> URL
}
```

### 3. Smart Framework Selection

```swift
class FrameworkSelector {
    func selectOptimalFramework(for model: ModelInfo, on device: DeviceInfo) -> LLMFramework {
        // Consider:
        // - Model format
        // - Device capabilities
        // - Memory availability
        // - User preferences
        // - Performance requirements
    }
}
```

### 4. Lifecycle State Machine

```swift
class ModelLifecycleStateMachine {
    private var state: ModelLifecycleState = .uninitialized
    private let transitions: [StateTransition] = [
        StateTransition(from: .uninitialized, to: .discovered, action: discoverModel),
        StateTransition(from: .discovered, to: .downloading, action: startDownload),
        // ... all valid transitions
    ]
    
    func transition(to newState: ModelLifecycleState) async throws {
        guard let transition = findTransition(from: state, to: newState) else {
            throw UnifiedLLMError.invalidStateTransition(from: state, to: newState)
        }
        try await transition.action()
        state = newState
    }
}
```

## Conclusion

The current implementation has served well as a proof of concept, but the lack of unified abstractions creates maintenance challenges and limits extensibility. The proposed unified architecture addresses these issues by:

1. **Standardizing the model lifecycle** across all frameworks
2. **Creating clean abstractions** for common operations
3. **Improving error handling** and user feedback
4. **Optimizing resource usage** through coordinated management
5. **Enabling easy addition** of new frameworks

By implementing this architecture, the app will be more maintainable, performant, and user-friendly, while providing a solid foundation for future enhancements.