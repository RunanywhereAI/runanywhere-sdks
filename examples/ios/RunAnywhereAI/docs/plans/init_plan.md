# iOS Local LLM Implementation Guide

## 🎯 Executive Summary

This comprehensive guide covers all mainstream frameworks and SDKs for running Large Language Models (LLMs) locally on iOS devices. Each framework is detailed with installation instructions, code examples, model management, and performance considerations.

## 📋 Table of Contents

1. [Apple Foundation Models Framework](#1-apple-foundation-models-framework)
2. [Core ML](#2-core-ml)
3. [MLX Framework](#3-mlx-framework)
4. [MLC-LLM](#4-mlc-llm)
5. [ONNX Runtime](#5-onnx-runtime)
6. [ExecuTorch](#6-executorch)
7. [llama.cpp (GGUF)](#7-llamacpp-gguf)
8. [TensorFlow Lite (LiteRT)](#8-tensorflow-lite-litert)
9. [picoLLM](#9-picollm)
10. [Swift Transformers](#10-swift-transformers)
11. [Sample App Architecture](#11-sample-app-architecture)
12. [Model Recommendations](#12-model-recommendations)
13. [Performance Optimization](#13-performance-optimization)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Apple Foundation Models Framework

### Overview
Apple's native framework for on-device AI, introduced in iOS 18+. Provides ~3B parameter models with sophisticated APIs including streaming, tool calling, and structured outputs.

### Requirements
- **iOS Version**: 18.0+
- **Devices**: iPhone 15 Pro or later (8GB+ RAM)
- **Xcode**: 16.0+
- **Swift**: 6.0+

### Installation

```swift
// No additional installation needed - built into iOS 18+
import FoundationModels
```

### Implementation

```swift
import FoundationModels

class FoundationModelChat {
    private let model = FoundationModel.shared
    
    // Basic text generation
    func generateText(_ prompt: String) async throws -> String {
        let request = TextProcessingRequest(
            input: prompt,
            maxTokens: 150,
            temperature: 0.7,
            topP: 0.95,
            stopSequences: ["Human:", "Assistant:"]
        )
        
        let response = try await model.generateText(request)
        return response.text
    }
    
    // Streaming generation
    func streamGenerate(_ prompt: String) -> AsyncThrowingStream<String, Error> {
        model.streamGenerate(prompt: prompt) { partialResult in
            // Handle partial results
        }
    }
    
    // Structured output with Generable protocol
    @Generable
    struct CodeSuggestion {
        let language: String
        let code: String
        let explanation: String
        let complexity: String
    }
    
    func generateCode(for task: String) async throws -> CodeSuggestion {
        return try await model.generate(
            prompt: "Generate code for: \(task)",
            outputType: CodeSuggestion.self
        )
    }
    
    // Tool calling
    func executeWithTools(_ prompt: String) async throws -> String {
        let calculatorTool = Tool(
            name: "calculator",
            description: "Performs mathematical calculations",
            parameters: [
                "operation": .string,
                "numbers": .array(.number)
            ]
        ) { parameters in
            // Implement calculator logic
            return calculateResult(parameters)
        }
        
        let result = try await model.executeWithTools(
            prompt: prompt,
            tools: [calculatorTool]
        )
        
        return result.finalResponse
    }
    
    // Multimodal support
    func analyzeImageWithText(image: UIImage, question: String) async throws -> String {
        let request = MultimodalRequest(
            image: image,
            text: question,
            maxTokens: 200
        )
        
        let response = try await model.processMultimodal(request)
        return response.text
    }
}
```

### Model Management

```swift
class FoundationModelManager {
    // Check model availability
    func isModelAvailable() -> Bool {
        return FoundationModel.isAvailable
    }
    
    // Get model info
    func getModelInfo() -> ModelInfo {
        return FoundationModel.currentModelInfo
    }
    
    // Handle model updates
    func checkForUpdates() async throws {
        if await FoundationModel.hasUpdate {
            try await FoundationModel.updateModel()
        }
    }
}
```

### Performance Characteristics
- **First Token Latency**: <100ms
- **Generation Speed**: 30-50 tokens/second
- **Memory Usage**: ~2GB for 3B model
- **Battery Impact**: Optimized with Neural Engine

---

## 2. Core ML

### Overview
Apple's machine learning framework for on-device inference, supporting various model formats with hardware acceleration.

### Requirements
- **iOS Version**: 11.0+ (17.0+ for advanced features)
- **Devices**: All iOS devices
- **Xcode**: 14.0+
- **Model Format**: .mlmodel, .mlpackage

### Installation

```swift
import CoreML
import Vision // For image models
```

### Model Conversion

```bash
# Install coremltools
pip install coremltools

# Convert PyTorch model
import coremltools as ct
import torch

# Load PyTorch model
pytorch_model = torch.load('model.pt')
pytorch_model.eval()

# Trace the model
example_input = torch.rand(1, 3, 224, 224)
traced_model = torch.jit.trace(pytorch_model, example_input)

# Convert to Core ML
model = ct.convert(
    traced_model,
    inputs=[ct.TensorType(shape=example_input.shape)],
    minimum_deployment_target=ct.target.iOS17
)

# Save the model
model.save('model.mlpackage')
```

### Implementation

```swift
import CoreML

class CoreMLModel {
    private var model: MLModel?
    
    init(modelName: String) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all // CPU, GPU, and Neural Engine
        
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") else {
            throw ModelError.notFound
        }
        
        model = try MLModel(contentsOf: modelURL, configuration: config)
    }
    
    // Text generation with Core ML
    func generateText(prompt: String, maxLength: Int = 100) throws -> String {
        guard let model = model else { throw ModelError.notLoaded }
        
        // Tokenize input
        let tokenizedInput = tokenize(prompt)
        
        // Create MLMultiArray for input
        let inputArray = try MLMultiArray(shape: [1, tokenizedInput.count as NSNumber], dataType: .int32)
        for (index, token) in tokenizedInput.enumerated() {
            inputArray[index] = NSNumber(value: token)
        }
        
        // Create input provider
        let input = ModelInput(tokens: inputArray)
        
        // Run prediction
        let output = try model.prediction(from: input)
        
        // Decode output
        return decodeTokens(output.tokens)
    }
    
    // Stateful model support (iOS 17+)
    @available(iOS 17.0, *)
    func generateWithState(prompt: String) async throws -> String {
        guard let model = model else { throw ModelError.notLoaded }
        
        // Create stateful session
        let session = try model.predictionSession()
        
        var generatedText = ""
        let tokens = tokenize(prompt)
        
        for token in tokens {
            let input = try createInput(token: token)
            let prediction = try await session.prediction(from: input)
            generatedText += decodeToken(prediction.outputToken)
        }
        
        return generatedText
    }
}

// Model Input/Output protocols
class ModelInput: MLFeatureProvider {
    let tokens: MLMultiArray
    
    init(tokens: MLMultiArray) {
        self.tokens = tokens
    }
    
    var featureNames: Set<String> {
        return ["tokens"]
    }
    
    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "tokens" {
            return MLFeatureValue(multiArray: tokens)
        }
        return nil
    }
}
```

### Advanced Features

```swift
// ML Program format support (iOS 17+)
@available(iOS 17.0, *)
class AdvancedCoreMLModel {
    private var model: MLModel?
    
    // Load ML Program with flexible shapes
    func loadFlexibleModel(name: String) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
        // Enable flexible input shapes
        config.parameters = [
            "inputShape": MLParameterKey.flexibleShape
        ]
        
        model = try MLModel(contentsOf: modelURL, configuration: config)
    }
    
    // Use MLTensor for efficient data handling
    func processWithMLTensor(data: [Float]) throws -> [Float] {
        let tensor = MLTensor(shape: [1, data.count], data: data)
        
        let input = MLDictionaryFeatureProvider()
        input["input"] = MLFeatureValue(tensor: tensor)
        
        let output = try model?.prediction(from: input)
        return output?.featureValue(for: "output")?.tensorValue?.data ?? []
    }
}
```

### Performance Optimization

```swift
// Model compilation for optimal performance
func compileModel(at url: URL) throws -> URL {
    let compiledURL = try MLModel.compileModel(at: url)
    return compiledURL
}

// Background model loading
func loadModelInBackground(name: String, completion: @escaping (Result<MLModel, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        do {
            let model = try MLModel(contentsOf: modelURL)
            DispatchQueue.main.async {
                completion(.success(model))
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
}
```

---

## 3. MLX Framework

### Overview
Apple's array framework for machine learning on Apple Silicon, designed for LLM inference with unified memory architecture.

### Requirements
- **iOS Version**: 17.0+
- **Devices**: Apple Silicon devices (A17 Pro+)
- **Swift**: 5.9+
- **Memory**: 6GB+ recommended

### Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.26.0"),
    .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "0.26.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXNN", package: "mlx-swift"),
            .product(name: "MLXRandom", package: "mlx-swift"),
            .product(name: "MLXFFT", package: "mlx-swift"),
            .product(name: "MLXLinalg", package: "mlx-swift"),
            .product(name: "LLM", package: "mlx-swift-examples"),
            .product(name: "MLXLLM", package: "mlx-swift-examples")
        ]
    )
]
```

### Implementation

```swift
import MLX
import MLXNN
import MLXLLM
import MLXRandom

class MLXLLMChat {
    private var model: LLMModel?
    private var tokenizer: Tokenizer?
    
    // Initialize with model
    func initialize(modelPath: String) async throws {
        // Load model configuration
        let config = try await ModelConfiguration.load(from: modelPath)
        
        // Initialize model
        model = try LLMModel(configuration: config)
        
        // Load tokenizer
        tokenizer = try await Tokenizer.load(from: modelPath)
        
        // Load weights
        try await model?.loadWeights(from: modelPath)
    }
    
    // Generate text with streaming
    func generate(
        prompt: String,
        maxTokens: Int = 200,
        temperature: Float = 0.7
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let model = model, let tokenizer = tokenizer else {
                        throw ModelError.notInitialized
                    }
                    
                    // Tokenize prompt
                    let tokens = tokenizer.encode(prompt)
                    var inputTokens = MLXArray(tokens)
                    
                    // Generate tokens
                    for _ in 0..<maxTokens {
                        // Forward pass
                        let logits = model(inputTokens)
                        
                        // Sample next token
                        let nextToken = sampleToken(
                            logits: logits,
                            temperature: temperature
                        )
                        
                        // Decode and yield
                        let text = tokenizer.decode([nextToken])
                        continuation.yield(text)
                        
                        // Update input
                        inputTokens = MLXArray.concatenate([inputTokens, [nextToken]])
                        
                        // Check for end token
                        if nextToken == tokenizer.eosToken {
                            break
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // Custom transformer implementation
    class TransformerBlock: Module {
        let attention: MultiHeadAttention
        let mlp: MLP
        let norm1: LayerNorm
        let norm2: LayerNorm
        
        init(dims: Int, numHeads: Int, mlpDims: Int) {
            attention = MultiHeadAttention(
                dims: dims,
                numHeads: numHeads,
                kvHeads: numHeads
            )
            mlp = MLP(dims: dims, hiddenDims: mlpDims)
            norm1 = LayerNorm(dims: dims)
            norm2 = LayerNorm(dims: dims)
            
            super.init()
        }
        
        func callAsFunction(_ x: MLXArray, mask: MLXArray? = nil) -> MLXArray {
            // Self-attention with residual
            var h = norm1(x)
            h = attention(h, h, h, mask: mask)
            let y = x + h
            
            // MLP with residual
            h = norm2(y)
            h = mlp(h)
            return y + h
        }
    }
    
    // Sampling strategies
    private func sampleToken(logits: MLXArray, temperature: Float) -> Int {
        // Apply temperature
        let scaledLogits = logits / temperature
        
        // Softmax
        let probs = MLX.softmax(scaledLogits, axis: -1)
        
        // Sample from distribution
        return MLXRandom.categorical(probs)
    }
}

// Memory-efficient model loading
extension MLXLLMChat {
    func loadQuantizedModel(path: String, bits: Int = 4) async throws {
        let config = QuantizationConfig(bits: bits)
        model = try await LLMModel.loadQuantized(
            from: path,
            config: config
        )
    }
    
    // KV-cache management for efficient generation
    class KVCache {
        private var keys: [MLXArray] = []
        private var values: [MLXArray] = []
        
        func update(key: MLXArray, value: MLXArray, layer: Int) {
            if layer < keys.count {
                keys[layer] = MLXArray.concatenate([keys[layer], key], axis: 1)
                values[layer] = MLXArray.concatenate([values[layer], value], axis: 1)
            } else {
                keys.append(key)
                values.append(value)
            }
        }
        
        func clear() {
            keys.removeAll()
            values.removeAll()
        }
    }
}
```

### Model Conversion

```swift
// Convert Hugging Face model to MLX format
class MLXModelConverter {
    static func convertFromHuggingFace(
        modelId: String,
        outputPath: String,
        quantizeBits: Int? = nil
    ) async throws {
        // Download model
        let hfModel = try await HuggingFaceModel.download(modelId)
        
        // Convert to MLX format
        let mlxModel = try MLXModel(from: hfModel)
        
        // Quantize if requested
        if let bits = quantizeBits {
            try mlxModel.quantize(bits: bits)
        }
        
        // Save
        try mlxModel.save(to: outputPath)
    }
}
```

### Performance Optimization

```swift
// Optimized batch processing
func processBatch(prompts: [String]) async throws -> [String] {
    // Tokenize all prompts
    let tokenizedBatch = prompts.map { tokenizer.encode($0) }
    
    // Pad to same length
    let maxLength = tokenizedBatch.map { $0.count }.max() ?? 0
    let paddedBatch = tokenizedBatch.map { tokens in
        tokens + Array(repeating: tokenizer.padToken, count: maxLength - tokens.count)
    }
    
    // Create batch tensor
    let batchTensor = MLXArray(paddedBatch)
    
    // Process entire batch
    let outputs = model(batchTensor)
    
    // Decode results
    return outputs.map { tokenizer.decode($0) }
}
```

---

## 4. MLC-LLM

### Overview
Machine Learning Compilation framework for universal LLM deployment with hardware-agnostic optimization.

### Requirements
- **iOS Version**: 14.0+
- **Devices**: iPhone 6s+ (A9+)
- **Memory**: 4GB+ for quantized models
- **Storage**: 1-4GB per model

### Installation

```ruby
# Podfile
pod 'MLCSwift', '~> 0.1.0'
```

```swift
// Swift Package Manager
dependencies: [
    .package(url: "https://github.com/mlc-ai/mlc-swift", from: "0.1.0")
]
```

### Implementation

```swift
import MLCSwift

class MLCChat {
    private var engine: MLCEngine?
    private let modelPath: String
    
    init(modelPath: String) {
        self.modelPath = modelPath
    }
    
    // Initialize engine with configuration
    func initialize() async throws {
        let config = MLCEngineConfig(
            model: modelPath,
            modelLib: "model_iphone",
            device: .auto, // Automatically select best device
            maxBatchSize: 1,
            maxSequenceLength: 2048
        )
        
        engine = try await MLCEngine(config: config)
    }
    
    // Chat completion with OpenAI-compatible API
    func chatCompletion(messages: [ChatMessage]) async throws -> String {
        guard let engine = engine else {
            throw MLCError.engineNotInitialized
        }
        
        let request = ChatCompletionRequest(
            model: modelPath,
            messages: messages,
            temperature: 0.7,
            maxTokens: 150,
            stream: false
        )
        
        let response = try await engine.chatCompletion(request)
        return response.choices.first?.message.content ?? ""
    }
    
    // Streaming generation
    func streamChat(
        messages: [ChatMessage],
        onToken: @escaping (String) -> Void
    ) async throws {
        guard let engine = engine else {
            throw MLCError.engineNotInitialized
        }
        
        let request = ChatCompletionRequest(
            model: modelPath,
            messages: messages,
            temperature: 0.7,
            maxTokens: 200,
            stream: true
        )
        
        let stream = try await engine.streamChatCompletion(request)
        
        for try await chunk in stream {
            if let content = chunk.choices.first?.delta.content {
                onToken(content)
            }
        }
    }
    
    // Advanced generation with JSON mode
    func generateJSON<T: Codable>(
        prompt: String,
        schema: T.Type
    ) async throws -> T {
        let request = ChatCompletionRequest(
            model: modelPath,
            messages: [
                ChatMessage(role: .system, content: "Respond only with valid JSON"),
                ChatMessage(role: .user, content: prompt)
            ],
            responseFormat: .json,
            jsonSchema: JSONSchema(type: schema)
        )
        
        let response = try await engine.chatCompletion(request)
        let jsonString = response.choices.first?.message.content ?? "{}"
        
        return try JSONDecoder().decode(T.self, from: jsonString.data(using: .utf8)!)
    }
    
    // Multi-LoRA support
    func switchLoRA(adapter: String) async throws {
        try await engine?.loadLoRA(adapter)
    }
}

// Model management
class MLCModelManager {
    static let shared = MLCModelManager()
    
    // Download model from MLC repository
    func downloadModel(
        modelId: String,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        let downloader = MLCModelDownloader()
        
        return try await downloader.download(
            model: modelId,
            progressHandler: { downloadProgress in
                DispatchQueue.main.async {
                    progress(downloadProgress.fractionCompleted)
                }
            }
        )
    }
    
    // Compile model for optimal performance
    func compileModel(
        sourcePath: String,
        targetDevice: MLCDevice = .auto
    ) async throws -> String {
        let compiler = MLCCompiler()
        
        let config = CompilationConfig(
            model: sourcePath,
            target: targetDevice,
            optimization: .O3, // Maximum optimization
            quantization: .int4 // 4-bit quantization
        )
        
        return try await compiler.compile(config)
    }
    
    // List available models
    func listAvailableModels() -> [MLCModel] {
        return [
            MLCModel(id: "Llama-3.2-3B-Instruct-q4f16_1-MLC", size: "1.7GB"),
            MLCModel(id: "Mistral-7B-Instruct-v0.3-q4f16_1-MLC", size: "3.8GB"),
            MLCModel(id: "Phi-3-mini-4k-instruct-q4f16_1-MLC", size: "1.5GB"),
            MLCModel(id: "Qwen2.5-1.5B-Instruct-q4f16_1-MLC", size: "0.8GB")
        ]
    }
}
```

### Hardware-Specific Optimization

```swift
// Configure for specific hardware
extension MLCEngineConfig {
    static func optimizedForDevice() -> MLCEngineConfig {
        let device = UIDevice.current
        let memorySize = ProcessInfo.processInfo.physicalMemory
        
        // Determine optimal configuration
        let config = MLCEngineConfig()
        
        if device.userInterfaceIdiom == .pad && memorySize > 8_000_000_000 {
            // iPad with 8GB+ RAM
            config.device = .metal
            config.maxBatchSize = 4
            config.maxSequenceLength = 4096
        } else if memorySize > 6_000_000_000 {
            // iPhone with 6GB+ RAM
            config.device = .metal
            config.maxBatchSize = 1
            config.maxSequenceLength = 2048
        } else {
            // Lower-end devices
            config.device = .cpu
            config.maxBatchSize = 1
            config.maxSequenceLength = 1024
        }
        
        return config
    }
}
```

---

## 5. ONNX Runtime

### Overview
Microsoft's cross-platform inference accelerator supporting models from multiple frameworks.

### Requirements
- **iOS Version**: 11.0+
- **Devices**: All iOS devices
- **Framework Size**: ~20MB
- **Supported Formats**: .onnx, .ort

### Installation

```ruby
# CocoaPods
pod 'onnxruntime-mobile-objc'
pod 'onnxruntime-mobile-c'  # For C API
```

```swift
// Swift Package Manager
dependencies: [
    .package(url: "https://github.com/microsoft/onnxruntime", from: "1.19.0")
]
```

### Implementation

```swift
import onnxruntime_objc

class ONNXRuntimeModel {
    private var session: ORTSession?
    private var env: ORTEnv?
    
    init(modelPath: String) throws {
        // Create environment
        env = try ORTEnv(loggingLevel: .warning)
        
        // Create session options
        let sessionOptions = try ORTSessionOptions()
        try sessionOptions.setGraphOptimizationLevel(.ortEnableAll)
        try sessionOptions.setInterOpNumThreads(4)
        try sessionOptions.setIntraOpNumThreads(4)
        
        // Add execution providers
        try addExecutionProviders(to: sessionOptions)
        
        // Create session
        guard let env = env else { throw ORTError.envNotCreated }
        session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: sessionOptions)
    }
    
    // Configure execution providers
    private func addExecutionProviders(to options: ORTSessionOptions) throws {
        // CoreML provider for iOS
        let coreMLOptions = ORTCoreMLExecutionProviderOptions()
        coreMLOptions.enableOnSubgraphs = true
        coreMLOptions.onlyEnableDeviceWithANE = true // Use Neural Engine only
        try options.appendCoreMLExecutionProvider(with: coreMLOptions)
        
        // CPU provider as fallback
        try options.appendCPUExecutionProvider()
    }
    
    // Text generation
    func generate(prompt: String, maxLength: Int = 100) throws -> String {
        guard let session = session else {
            throw ORTError.sessionNotCreated
        }
        
        // Tokenize input
        let tokens = tokenize(prompt)
        let inputTensor = try createTensor(from: tokens)
        
        // Create inputs
        let inputs = ["input_ids": inputTensor]
        
        var generatedTokens: [Int64] = []
        var currentInput = inputTensor
        
        // Generate tokens one by one
        for _ in 0..<maxLength {
            // Run inference
            let outputs = try session.run(
                withInputs: inputs,
                outputNames: ["logits"],
                runOptions: nil
            )
            
            guard let logits = outputs["logits"] else {
                throw ORTError.outputNotFound
            }
            
            // Sample next token
            let nextToken = try sampleToken(from: logits)
            generatedTokens.append(nextToken)
            
            // Check for end token
            if nextToken == endTokenId {
                break
            }
            
            // Update input for next iteration
            currentInput = try createTensor(from: tokens + generatedTokens)
        }
        
        // Decode generated tokens
        return detokenize(generatedTokens)
    }
    
    // Create tensor from tokens
    private func createTensor(from tokens: [Int64]) throws -> ORTValue {
        let shape = [1, tokens.count] as [NSNumber]
        let tensorData = NSMutableData(
            bytes: tokens,
            length: tokens.count * MemoryLayout<Int64>.size
        )
        
        return try ORTValue(
            tensorData: tensorData,
            elementType: .int64,
            shape: shape
        )
    }
    
    // Advanced: Quantized model support
    func loadQuantizedModel(path: String, quantizationType: QuantizationType) throws {
        let sessionOptions = try ORTSessionOptions()
        
        switch quantizationType {
        case .dynamic:
            try sessionOptions.setGraphOptimizationLevel(.ortEnableAll)
        case .qat: // Quantization-aware training
            try sessionOptions.setExecutionMode(.ortParallel)
        case .static:
            // Load calibration data
            try sessionOptions.setOptimizedModelFilePath("model_optimized.onnx")
        }
        
        session = try ORTSession(
            env: env!,
            modelPath: path,
            sessionOptions: sessionOptions
        )
    }
}

// Streaming support
extension ONNXRuntimeModel {
    func streamGenerate(
        prompt: String,
        onToken: @escaping (String) -> Void,
        maxTokens: Int = 200
    ) async throws {
        let initialTokens = tokenize(prompt)
        var allTokens = initialTokens
        
        for _ in 0..<maxTokens {
            let inputTensor = try createTensor(from: allTokens)
            
            let outputs = try await withCheckedThrowingContinuation { continuation in
                do {
                    let result = try session?.run(
                        withInputs: ["input_ids": inputTensor],
                        outputNames: ["logits"],
                        runOptions: nil
                    )
                    continuation.resume(returning: result ?? [:])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            guard let logits = outputs["logits"] else { continue }
            
            let nextToken = try sampleToken(from: logits)
            allTokens.append(nextToken)
            
            let text = detokenize([nextToken])
            onToken(text)
            
            if nextToken == endTokenId { break }
        }
    }
}
```

### Model Optimization

```swift
// Optimize ONNX model for mobile
class ONNXModelOptimizer {
    static func optimizeForMobile(
        inputPath: String,
        outputPath: String,
        targetDevice: TargetDevice = .iPhone
    ) throws {
        let optimizer = ORTModelOptimizer()
        
        let config = OptimizationConfig(
            level: .aggressive,
            targetDevice: targetDevice,
            enableQuantization: true,
            quantizationBits: 8
        )
        
        try optimizer.optimize(
            inputModel: inputPath,
            outputModel: outputPath,
            config: config
        )
    }
}
```

---

## 6. ExecuTorch

### Overview
PyTorch's edge AI framework providing efficient on-device inference for PyTorch models.

### Requirements
- **iOS Version**: 12.0+
- **Devices**: iPhone 7+ (A10+)
- **Framework**: Distributed as XCFramework
- **Memory**: 2GB+ for small models

### Installation

```ruby
# CocoaPods
pod 'ExecuTorch', '~> 0.6.0'
```

```bash
# Manual framework integration
# Download from PyTorch releases
# Add ExecuTorch.xcframework to your project
```

### Implementation

```swift
import ExecuTorch

class ExecuTorchModel {
    private var module: ETModule?
    private let modelPath: String
    
    init(modelPath: String) {
        self.modelPath = modelPath
    }
    
    // Load ExecuTorch model
    func loadModel() throws {
        guard let path = Bundle.main.path(forResource: modelPath, ofType: "pte") else {
            throw ETError.modelNotFound
        }
        
        module = try ETModule(contentsOf: path)
    }
    
    // Configure execution
    func configureExecution() {
        module?.executionConfig = ETExecutionConfig(
            backend: .auto, // Automatically select best backend
            numThreads: ProcessInfo.processInfo.processorCount,
            enableProfiling: false
        )
    }
    
    // Text generation with ExecuTorch
    func generate(
        prompt: String,
        maxTokens: Int = 150,
        temperature: Float = 0.7
    ) async throws -> String {
        guard let module = module else {
            throw ETError.moduleNotLoaded
        }
        
        // Tokenize input
        let tokenizer = ETTokenizer(vocabPath: "tokenizer.json")
        let inputIds = tokenizer.encode(prompt)
        
        // Create input tensors
        let inputTensor = ETTensor(
            data: inputIds,
            shape: [1, inputIds.count],
            dtype: .int64
        )
        
        // Generation loop
        var generatedIds: [Int64] = []
        var currentInput = inputTensor
        
        for _ in 0..<maxTokens {
            // Forward pass
            let outputs = try await module.forward([currentInput])
            
            guard let logits = outputs.first else {
                throw ETError.forwardFailed
            }
            
            // Sample next token
            let nextToken = sampleFromLogits(
                logits,
                temperature: temperature
            )
            
            generatedIds.append(nextToken)
            
            // Check for end token
            if nextToken == tokenizer.eosTokenId {
                break
            }
            
            // Update input
            let allTokens = inputIds + generatedIds
            currentInput = ETTensor(
                data: allTokens,
                shape: [1, allTokens.count],
                dtype: .int64
            )
        }
        
        // Decode output
        return tokenizer.decode(generatedIds)
    }
    
    // Streaming generation
    func streamGenerate(
        prompt: String,
        onToken: @escaping (String) -> Void,
        options: GenerationOptions = .default
    ) {
        Task {
            guard let module = module else { return }
            
            let tokenizer = ETTokenizer(vocabPath: "tokenizer.json")
            var tokens = tokenizer.encode(prompt)
            
            for _ in 0..<options.maxTokens {
                let input = ETTensor(
                    data: tokens,
                    shape: [1, tokens.count],
                    dtype: .int64
                )
                
                let outputs = try await module.forward([input])
                let logits = outputs[0]
                
                let nextToken = sampleFromLogits(
                    logits,
                    temperature: options.temperature,
                    topP: options.topP,
                    topK: options.topK
                )
                
                tokens.append(nextToken)
                
                let text = tokenizer.decode([nextToken])
                DispatchQueue.main.async {
                    onToken(text)
                }
                
                if nextToken == tokenizer.eosTokenId {
                    break
                }
            }
        }
    }
    
    // Backend selection
    func selectOptimalBackend() -> ETBackend {
        let device = UIDevice.current
        let chipset = device.chipset // Custom extension
        
        switch chipset {
        case .a17Pro, .a18, .a18Pro:
            return .coreml // Best for latest chips
        case .a15, .a16:
            return .metal // Good GPU performance
        case .a14:
            return .accelerate // Optimized CPU
        default:
            return .xnnpack // Fallback
        }
    }
}

// Generation options
struct GenerationOptions {
    let maxTokens: Int
    let temperature: Float
    let topP: Float
    let topK: Int
    let repetitionPenalty: Float
    
    static let `default` = GenerationOptions(
        maxTokens: 150,
        temperature: 0.7,
        topP: 0.9,
        topK: 50,
        repetitionPenalty: 1.1
    )
}

// Model export from PyTorch
extension ExecuTorchModel {
    static func exportFromPyTorch(scriptPath: String) throws {
        // This would typically be done in Python
        let pythonScript = """
        import torch
        from executorch.exir import to_edge
        
        # Load model
        model = torch.load('model.pt')
        model.eval()
        
        # Export to ExecuTorch
        example_input = torch.randn(1, 512)
        edge_program = to_edge(model, (example_input,))
        
        # Save
        with open('model.pte', 'wb') as f:
            edge_program.write(f)
        """
        
        // Execute Python script
        try PythonRunner.execute(pythonScript)
    }
}
```

### Hardware Acceleration

```swift
// Configure hardware-specific optimizations
extension ETModule {
    func optimizeForDevice() {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let availableMemory = getAvailableMemory()
        
        if totalMemory > 8_000_000_000 {
            // High-end device optimizations
            self.executionConfig = ETExecutionConfig(
                backend: .coreml,
                numThreads: 6,
                enableProfiling: false,
                cacheSize: 512_000_000 // 512MB cache
            )
        } else if totalMemory > 4_000_000_000 {
            // Mid-range device
            self.executionConfig = ETExecutionConfig(
                backend: .metal,
                numThreads: 4,
                enableProfiling: false,
                cacheSize: 256_000_000 // 256MB cache
            )
        } else {
            // Low-end device
            self.executionConfig = ETExecutionConfig(
                backend: .xnnpack,
                numThreads: 2,
                enableProfiling: false,
                cacheSize: 128_000_000 // 128MB cache
            )
        }
    }
}
```

---

## 7. llama.cpp (GGUF)

### Overview
Efficient C++ implementation for LLM inference, optimized for CPU with GGUF format support.

### Requirements
- **iOS Version**: 10.0+
- **Devices**: All iOS devices
- **Library**: C++ with Swift/Obj-C wrapper
- **Model Format**: .gguf files

### Installation

```ruby
# CocoaPods
pod 'LlamaCpp', :git => 'https://github.com/ggerganov/llama.cpp.git'
```

```bash
# Manual integration
# 1. Clone llama.cpp repository
# 2. Build for iOS using provided scripts
# 3. Add to Xcode project
```

### Swift Wrapper Implementation

```swift
import Foundation

// Swift wrapper for llama.cpp
class LlamaCppModel {
    private var context: OpaquePointer?
    private var model: OpaquePointer?
    private let modelPath: String
    
    init(modelPath: String) {
        self.modelPath = modelPath
    }
    
    // Initialize model
    func initialize() throws {
        // Initialize backend
        llama_backend_init()
        
        // Model parameters
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 0 // CPU only on iOS
        modelParams.use_mmap = true
        modelParams.use_mlock = false
        
        // Load model
        model = llama_load_model_from_file(modelPath, modelParams)
        guard model != nil else {
            throw LlamaError.modelLoadFailed
        }
        
        // Context parameters
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 2048 // Context size
        contextParams.n_batch = 512
        contextParams.n_threads = Int32(ProcessInfo.processInfo.processorCount)
        contextParams.n_threads_batch = contextParams.n_threads
        
        // Create context
        context = llama_new_context_with_model(model, contextParams)
        guard context != nil else {
            throw LlamaError.contextCreationFailed
        }
    }
    
    // Generate text
    func generate(
        prompt: String,
        maxTokens: Int = 200,
        temperature: Float = 0.7,
        topP: Float = 0.95,
        topK: Int = 40
    ) -> String {
        guard let context = context else { return "" }
        
        // Tokenize prompt
        let tokens = tokenize(prompt)
        
        // Prepare batch
        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        defer { llama_batch_free(batch) }
        
        // Add tokens to batch
        for (i, token) in tokens.enumerated() {
            llama_batch_add(&batch, token, Int32(i), [0], false)
        }
        batch.logits[Int(batch.n_tokens - 1)] = 1 // Only need logits for last token
        
        // Decode batch
        if llama_decode(context, batch) != 0 {
            return "Decode failed"
        }
        
        // Generation loop
        var generatedTokens: [llama_token] = []
        var nCur = batch.n_tokens
        
        while generatedTokens.count < maxTokens {
            // Get logits
            let logits = llama_get_logits_ith(context, Int32(nCur - 1))
            let nVocab = llama_n_vocab(model)
            
            // Prepare candidates
            var candidates = Array<llama_token_data>()
            candidates.reserveCapacity(Int(nVocab))
            
            for tokenId in 0..<nVocab {
                candidates.append(llama_token_data(
                    id: tokenId,
                    logit: logits![Int(tokenId)],
                    p: 0.0
                ))
            }
            
            var candidatesP = llama_token_data_array(
                data: &candidates,
                size: Int(nVocab),
                sorted: false
            )
            
            // Apply sampling
            llama_sample_top_k(context, &candidatesP, Int32(topK), 1)
            llama_sample_top_p(context, &candidatesP, topP, 1)
            llama_sample_temp(context, &candidatesP, temperature)
            
            // Sample token
            let newTokenId = llama_sample_token(context, &candidatesP)
            
            // Check for end of generation
            if newTokenId == llama_token_eos(model) {
                break
            }
            
            generatedTokens.append(newTokenId)
            
            // Prepare next batch
            llama_batch_clear(&batch)
            llama_batch_add(&batch, newTokenId, Int32(nCur), [0], true)
            nCur += 1
            
            // Decode
            if llama_decode(context, batch) != 0 {
                break
            }
        }
        
        // Decode tokens to text
        return detokenize(generatedTokens)
    }
    
    // Tokenization
    private func tokenize(_ text: String) -> [llama_token] {
        let maxTokens = text.count + 1
        var tokens = Array<llama_token>(repeating: 0, count: maxTokens)
        
        let nTokens = llama_tokenize(
            model,
            text,
            Int32(text.count),
            &tokens,
            Int32(maxTokens),
            true,  // Add BOS
            false  // Special tokens
        )
        
        return Array(tokens.prefix(Int(nTokens)))
    }
    
    // Detokenization
    private func detokenize(_ tokens: [llama_token]) -> String {
        var result = ""
        
        for token in tokens {
            let bufferSize = 32
            let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            
            let nChars = llama_token_to_piece(model, token, buffer, Int32(bufferSize), false)
            
            if nChars > 0 {
                let piece = String(cString: buffer)
                result += piece
            }
        }
        
        return result
    }
    
    // Cleanup
    deinit {
        if let context = context {
            llama_free(context)
        }
        if let model = model {
            llama_free_model(model)
        }
        llama_backend_free()
    }
}

// Streaming wrapper
extension LlamaCppModel {
    func streamGenerate(
        prompt: String,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        options: GenerationOptions = .default
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let context = self.context else { return }
            
            let tokens = self.tokenize(prompt)
            var batch = llama_batch_init(Int32(tokens.count), 0, 1)
            defer { llama_batch_free(batch) }
            
            // Initial batch
            for (i, token) in tokens.enumerated() {
                llama_batch_add(&batch, token, Int32(i), [0], false)
            }
            batch.logits[Int(batch.n_tokens - 1)] = 1
            
            guard llama_decode(context, batch) == 0 else { return }
            
            var nCur = batch.n_tokens
            var generatedCount = 0
            
            while generatedCount < options.maxTokens {
                // Sample next token
                let newToken = self.sampleToken(
                    context: context,
                    lastIdx: Int32(nCur - 1),
                    options: options
                )
                
                if newToken == llama_token_eos(self.model) {
                    break
                }
                
                // Decode token to text
                let text = self.detokenize([newToken])
                
                DispatchQueue.main.async {
                    onToken(text)
                }
                
                // Prepare next iteration
                llama_batch_clear(&batch)
                llama_batch_add(&batch, newToken, Int32(nCur), [0], true)
                nCur += 1
                generatedCount += 1
                
                if llama_decode(context, batch) != 0 {
                    break
                }
            }
            
            DispatchQueue.main.async {
                onComplete()
            }
        }
    }
}
```

### Model Management

```swift
// GGUF model manager
class GGUFModelManager {
    // Check if model is valid GGUF
    static func validateModel(at path: String) -> Bool {
        guard let file = fopen(path, "rb") else { return false }
        defer { fclose(file) }
        
        var magic: UInt32 = 0
        fread(&magic, MemoryLayout<UInt32>.size, 1, file)
        
        return magic == 0x46554747 // "GGUF" in little-endian
    }
    
    // Get model metadata
    static func getModelInfo(path: String) -> ModelInfo? {
        // This would parse GGUF metadata
        // Implementation depends on GGUF format specification
        return nil
    }
    
    // Quantize model
    static func quantizeModel(
        inputPath: String,
        outputPath: String,
        quantizationType: String = "Q4_K_M"
    ) throws {
        // Call llama.cpp quantization tool
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "quantize")
        process.arguments = [inputPath, outputPath, quantizationType]
        
        try process.run()
        process.waitUntilExit()
    }
}
```

---

## 8. TensorFlow Lite (LiteRT)

### Overview
Google's lightweight ML framework, now rebranded as LiteRT, for mobile and embedded devices.

### Requirements
- **iOS Version**: 11.0+
- **Devices**: All iOS devices
- **Framework Size**: ~1MB (base)
- **Model Format**: .tflite

### Installation

```ruby
# CocoaPods
pod 'TensorFlowLiteSwift'
pod 'TensorFlowLiteSwift/Metal' # For GPU acceleration
```

```swift
// Swift Package Manager
dependencies: [
    .package(url: "https://github.com/tensorflow/tensorflow", from: "2.16.0")
]
```

### Implementation

```swift
import TensorFlowLite

class TFLiteModel {
    private var interpreter: Interpreter?
    private let modelPath: String
    
    init(modelPath: String) {
        self.modelPath = modelPath
    }
    
    // Initialize interpreter
    func initialize() throws {
        guard let modelPath = Bundle.main.path(
            forResource: modelPath,
            ofType: "tflite"
        ) else {
            throw TFLiteError.modelNotFound
        }
        
        // Configure options
        var options = Interpreter.Options()
        options.threadCount = ProcessInfo.processInfo.processorCount
        
        // Add delegates for acceleration
        let metalDelegate = MetalDelegate()
        options.addDelegate(metalDelegate)
        
        // Create interpreter
        interpreter = try Interpreter(modelPath: modelPath, options: options)
        
        // Allocate tensors
        try interpreter?.allocateTensors()
    }
    
    // Text generation
    func generate(prompt: String, maxLength: Int = 100) throws -> String {
        guard let interpreter = interpreter else {
            throw TFLiteError.interpreterNotInitialized
        }
        
        // Get input/output tensor info
        let inputTensor = try interpreter.input(at: 0)
        let outputTensor = try interpreter.output(at: 0)
        
        // Tokenize input
        let tokenizer = TFLiteTokenizer()
        let inputIds = tokenizer.encode(prompt)
        
        // Prepare input data
        let inputData = createInputData(tokens: inputIds, shape: inputTensor.shape)
        try interpreter.copy(inputData, toInputAt: 0)
        
        // Run inference
        try interpreter.invoke()
        
        // Get output
        let outputData = try interpreter.output(at: 0).data
        let generatedTokens = decodeOutput(outputData, shape: outputTensor.shape)
        
        return tokenizer.decode(generatedTokens)
    }
    
    // Streaming generation with dynamic shapes
    func streamGenerate(
        prompt: String,
        onToken: @escaping (String) -> Void
    ) throws {
        guard let interpreter = interpreter else { return }
        
        let tokenizer = TFLiteTokenizer()
        var allTokens = tokenizer.encode(prompt)
        
        for _ in 0..<100 { // Max iterations
            // Resize input if needed
            try interpreter.resizeInput(at: 0, to: [1, allTokens.count])
            try interpreter.allocateTensors()
            
            // Prepare input
            let inputData = createInputData(tokens: allTokens)
            try interpreter.copy(inputData, toInputAt: 0)
            
            // Run inference
            try interpreter.invoke()
            
            // Get next token
            let outputData = try interpreter.output(at: 0).data
            let nextToken = sampleFromOutput(outputData)
            
            allTokens.append(nextToken)
            
            let text = tokenizer.decode([nextToken])
            onToken(text)
            
            if nextToken == tokenizer.eosToken {
                break
            }
        }
    }
    
    // GPU Delegate configuration
    func configureGPUAcceleration() throws {
        var options = Interpreter.Options()
        
        // Metal delegate for iOS
        let metalOptions = MetalDelegate.Options()
        metalOptions.isPrecisionLossAllowed = true
        metalOptions.waitType = .passive
        metalOptions.isQuantizationEnabled = true
        
        let metalDelegate = MetalDelegate(options: metalOptions)
        options.addDelegate(metalDelegate)
        
        // Recreate interpreter with GPU support
        interpreter = try Interpreter(
            modelPath: Bundle.main.path(forResource: modelPath, ofType: "tflite")!,
            options: options
        )
    }
}

// Model conversion utilities
class TFLiteConverter {
    // Convert from SavedModel format
    static func convertFromSavedModel(
        modelPath: String,
        outputPath: String,
        optimization: Optimization = .default
    ) throws {
        // This would typically be done in Python
        let pythonScript = """
        import tensorflow as tf
        
        # Load model
        model = tf.saved_model.load('\(modelPath)')
        
        # Convert to TFLite
        converter = tf.lite.TFLiteConverter.from_saved_model('\(modelPath)')
        
        # Apply optimizations
        converter.optimizations = [tf.lite.Optimize.\(optimization.rawValue)]
        
        # Set representative dataset for quantization
        if optimization == .int8:
            converter.representative_dataset = representative_dataset_gen
        
        # Convert
        tflite_model = converter.convert()
        
        # Save
        with open('\(outputPath)', 'wb') as f:
            f.write(tflite_model)
        """
        
        // Execute conversion
        try PythonRunner.execute(pythonScript)
    }
    
    enum Optimization: String {
        case `default` = "DEFAULT"
        case size = "OPTIMIZE_FOR_SIZE"
        case latency = "OPTIMIZE_FOR_LATENCY"
        case int8 = "DEFAULT"
    }
}

// Quantization support
extension TFLiteModel {
    func loadQuantizedModel(path: String, type: QuantizationType) throws {
        var options = Interpreter.Options()
        
        switch type {
        case .float16:
            // No special handling needed
            break
        case .int8:
            // Configure for int8 quantization
            options.isXNNPackDelegateEnabled = true
        case .dynamic:
            // Dynamic quantization at runtime
            let coreMLDelegate = CoreMLDelegate()
            options.addDelegate(coreMLDelegate)
        }
        
        interpreter = try Interpreter(modelPath: path, options: options)
        try interpreter?.allocateTensors()
    }
}
```

---

## 9. picoLLM

### Overview
Cross-platform inference engine for running compressed LLMs with minimal memory footprint.

### Requirements
- **iOS Version**: 11.0+
- **Devices**: All iOS devices
- **SDK**: Proprietary (requires access key)
- **Model Support**: Custom compressed formats

### Installation

```ruby
# CocoaPods
pod 'picoLLM-iOS'
```

```swift
// Swift Package Manager
dependencies: [
    .package(url: "https://github.com/Picovoice/picollm-ios", from: "1.0.0")
]
```

### Implementation

```swift
import PicoLLM

class PicoLLMChat {
    private var picoLLM: PicoLLM?
    private let accessKey: String
    
    init(accessKey: String) {
        self.accessKey = accessKey
    }
    
    // Initialize with model
    func initialize(modelPath: String) throws {
        picoLLM = try PicoLLM(
            accessKey: accessKey,
            modelPath: modelPath,
            device: "auto" // Automatically select best hardware
        )
    }
    
    // Generate text
    func generate(
        prompt: String,
        completionTokenLimit: Int = 200,
        stopPhrases: Set<String> = [],
        temperature: Float = 0.7,
        topP: Float = 0.9
    ) throws -> String {
        guard let picoLLM = picoLLM else {
            throw PicoLLMError.notInitialized
        }
        
        let options = PicoLLMGenerateOptions(
            completionTokenLimit: completionTokenLimit,
            stopPhrases: stopPhrases,
            presencePenalty: 0.0,
            frequencyPenalty: 0.0,
            temperature: temperature,
            topP: topP
        )
        
        let completion = try picoLLM.generate(
            prompt: prompt,
            options: options
        )
        
        return completion.text
    }
    
    // Streaming generation
    func streamGenerate(
        prompt: String,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        options: PicoLLMGenerateOptions? = nil
    ) throws {
        guard let picoLLM = picoLLM else {
            throw PicoLLMError.notInitialized
        }
        
        let generateOptions = options ?? PicoLLMGenerateOptions(
            completionTokenLimit: 200,
            temperature: 0.7,
            topP: 0.9
        )
        
        try picoLLM.generate(
            prompt: prompt,
            options: generateOptions,
            streamCallback: { token in
                DispatchQueue.main.async {
                    onToken(token)
                }
            },
            completionCallback: {
                DispatchQueue.main.async {
                    onComplete()
                }
            }
        )
    }
    
    // Dialog management
    func createDialog() throws -> PicoLLMDialog {
        guard let picoLLM = picoLLM else {
            throw PicoLLMError.notInitialized
        }
        
        return try picoLLM.createDialog()
    }
    
    // Multi-turn conversation
    func chat(dialog: PicoLLMDialog, message: String) throws -> String {
        let options = PicoLLMGenerateOptions(
            completionTokenLimit: 150,
            temperature: 0.7
        )
        
        return try dialog.generate(
            prompt: message,
            options: options
        ).text
    }
    
    // Model information
    func getModelInfo() -> PicoLLMModelInfo? {
        return picoLLM?.modelInfo
    }
    
    // Token usage tracking
    func getUsage() -> TokenUsage {
        guard let picoLLM = picoLLM else {
            return TokenUsage(prompt: 0, completion: 0)
        }
        
        return TokenUsage(
            prompt: picoLLM.promptTokenCount,
            completion: picoLLM.completionTokenCount
        )
    }
}

// Advanced features
extension PicoLLMChat {
    // Interrupt generation
    func interrupt() {
        picoLLM?.interrupt()
    }
    
    // Custom sampling
    func generateWithCustomSampling(
        prompt: String,
        sampler: @escaping (Float32Array) -> Int
    ) throws -> String {
        guard let picoLLM = picoLLM else {
            throw PicoLLMError.notInitialized
        }
        
        var result = ""
        let tokens = picoLLM.tokenize(prompt)
        var context = tokens
        
        for _ in 0..<200 {
            let logits = try picoLLM.forward(context)
            let nextToken = sampler(logits)
            
            if nextToken == picoLLM.eosToken {
                break
            }
            
            context.append(nextToken)
            result += picoLLM.decode([nextToken])
        }
        
        return result
    }
}
```

---

## 10. Swift Transformers

### Overview
Native Swift implementation for running transformer models using Core ML.

### Requirements
- **iOS Version**: 15.0+
- **Devices**: All iOS devices with Neural Engine
- **Framework**: Pure Swift with Core ML
- **Model Format**: Core ML models

### Installation

```swift
// Swift Package Manager
dependencies: [
    .package(url: "https://github.com/huggingface/swift-transformers", from: "0.1.0")
]
```

### Implementation

```swift
import SwiftTransformers
import CoreML

class SwiftTransformersModel {
    private var model: LanguageModel?
    private var tokenizer: GPT2Tokenizer?
    
    // Initialize with Hugging Face model
    func initialize(modelName: String) async throws {
        // Download and prepare model
        let modelLoader = ModelLoader()
        let modelBundle = try await modelLoader.download(modelName)
        
        // Load Core ML model
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
        model = try LanguageModel(
            modelBundle: modelBundle,
            configuration: config
        )
        
        // Initialize tokenizer
        tokenizer = try GPT2Tokenizer(
            vocabularyURL: modelBundle.vocabularyURL,
            mergesURL: modelBundle.mergesURL
        )
    }
    
    // Text generation
    func generate(
        prompt: String,
        maxLength: Int = 100,
        temperature: Double = 0.7,
        topK: Int = 50,
        topP: Double = 0.95
    ) async throws -> String {
        guard let model = model,
              let tokenizer = tokenizer else {
            throw TransformerError.notInitialized
        }
        
        // Encode prompt
        let inputIds = tokenizer.encode(text: prompt)
        
        // Generation config
        let config = GenerationConfig(
            maxLength: maxLength,
            temperature: temperature,
            topK: topK,
            topP: topP,
            repetitionPenalty: 1.2,
            doSample: true
        )
        
        // Generate
        let output = try await model.generate(
            inputIds: inputIds,
            config: config
        )
        
        // Decode output
        return tokenizer.decode(tokens: output)
    }
    
    // Streaming generation with attention
    func streamGenerateWithAttention(
        prompt: String,
        onToken: @escaping (String, AttentionWeights?) -> Void
    ) async throws {
        guard let model = model,
              let tokenizer = tokenizer else { return }
        
        var tokens = tokenizer.encode(text: prompt)
        let maxNewTokens = 100
        
        for _ in 0..<maxNewTokens {
            // Get model output with attention
            let output = try await model.forward(
                inputIds: tokens,
                returnAttention: true
            )
            
            // Sample next token
            let nextToken = sampleFromLogits(
                output.logits,
                temperature: 0.7,
                topK: 50
            )
            
            tokens.append(nextToken)
            
            // Decode token
            let text = tokenizer.decode(tokens: [nextToken])
            
            // Yield token and attention
            onToken(text, output.attention)
            
            // Check for end
            if nextToken == tokenizer.eosTokenId {
                break
            }
        }
    }
    
    // Batch processing
    func generateBatch(
        prompts: [String],
        maxLength: Int = 100
    ) async throws -> [String] {
        guard let model = model,
              let tokenizer = tokenizer else {
            throw TransformerError.notInitialized
        }
        
        // Tokenize all prompts
        let batchInputIds = prompts.map { tokenizer.encode(text: $0) }
        
        // Pad to same length
        let paddedBatch = TokenizerUtils.padBatch(
            batchInputIds,
            padToken: tokenizer.padTokenId
        )
        
        // Generate for batch
        let outputs = try await model.generateBatch(
            inputIds: paddedBatch,
            config: GenerationConfig(maxLength: maxLength)
        )
        
        // Decode outputs
        return outputs.map { tokenizer.decode(tokens: $0) }
    }
}

// Custom Core ML integration
extension SwiftTransformersModel {
    // Direct Core ML model usage
    func loadCustomCoreMLModel(path: String) throws {
        let compiledURL = try MLModel.compileModel(at: URL(fileURLWithPath: path))
        let mlModel = try MLModel(contentsOf: compiledURL)
        
        // Wrap in transformer interface
        model = LanguageModel(coreMLModel: mlModel)
    }
    
    // Optimize for specific hardware
    func optimizeForDevice() {
        guard var model = model else { return }
        
        let device = UIDevice.current
        if device.supportsNeuralEngine {
            model.preferredComputeUnits = .neuralEngine
        } else if device.supportsGPU {
            model.preferredComputeUnits = .cpuAndGPU
        } else {
            model.preferredComputeUnits = .cpuOnly
        }
    }
}
```

---

## 11. Sample App Architecture

### Project Structure

```
LocalLLMSample/
├── App/
│   ├── LocalLLMSampleApp.swift
│   └── Info.plist
├── Views/
│   ├── ContentView.swift
│   ├── ChatView.swift
│   ├── ModelListView.swift
│   └── SettingsView.swift
├── ViewModels/
│   ├── ChatViewModel.swift
│   ├── ModelManagerViewModel.swift
│   └── BenchmarkViewModel.swift
├── Models/
│   ├── ChatMessage.swift
│   ├── ModelInfo.swift
│   └── BenchmarkResult.swift
├── Services/
│   ├── LLMService/
│   │   ├── LLMProtocol.swift
│   │   ├── FoundationModelsService.swift
│   │   ├── CoreMLService.swift
│   │   ├── MLXService.swift
│   │   ├── MLCService.swift
│   │   ├── ONNXService.swift
│   │   ├── ExecuTorchService.swift
│   │   ├── LlamaCppService.swift
│   │   ├── TFLiteService.swift
│   │   ├── PicoLLMService.swift
│   │   └── SwiftTransformersService.swift
│   ├── ModelManager.swift
│   ├── PerformanceMonitor.swift
│   └── TokenizerService.swift
├── Utilities/
│   ├── Extensions/
│   ├── Helpers/
│   └── Constants.swift
└── Resources/
    ├── Models/
    └── Assets.xcassets
```

### Core Implementation

```swift
// LLMProtocol.swift
protocol LLMService {
    var name: String { get }
    var isInitialized: Bool { get }
    
    func initialize(modelPath: String) async throws
    func generate(prompt: String, options: GenerationOptions) async throws -> String
    func streamGenerate(
        prompt: String,
        options: GenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws
    func getModelInfo() -> ModelInfo?
    func cleanup()
}

// Unified chat interface
class UnifiedLLMService: ObservableObject {
    @Published var currentService: LLMService?
    @Published var availableServices: [LLMService] = []
    
    init() {
        setupServices()
    }
    
    private func setupServices() {
        // Add all available services
        if #available(iOS 18.0, *) {
            availableServices.append(FoundationModelsService())
        }
        
        availableServices.append(contentsOf: [
            CoreMLService(),
            MLXService(),
            MLCService(),
            ONNXService(),
            ExecuTorchService(),
            LlamaCppService(),
            TFLiteService(),
            PicoLLMService(),
            SwiftTransformersService()
        ])
    }
    
    func selectService(named name: String) {
        currentService = availableServices.first { $0.name == name }
    }
    
    func generate(prompt: String, options: GenerationOptions) async throws -> String {
        guard let service = currentService else {
            throw LLMError.noServiceSelected
        }
        
        return try await service.generate(prompt: prompt, options: options)
    }
}

// Chat View Model
@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var currentInput = ""
    
    private let llmService: UnifiedLLMService
    private let performanceMonitor = PerformanceMonitor()
    
    init(llmService: UnifiedLLMService) {
        self.llmService = llmService
    }
    
    func sendMessage() async {
        let userMessage = ChatMessage(role: .user, content: currentInput)
        messages.append(userMessage)
        
        let prompt = currentInput
        currentInput = ""
        isGenerating = true
        
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        messages.append(assistantMessage)
        
        do {
            // Start performance monitoring
            performanceMonitor.startMeasurement()
            
            // Stream generation
            try await llmService.streamGenerate(
                prompt: prompt,
                options: .default
            ) { token in
                DispatchQueue.main.async {
                    if let index = self.messages.lastIndex(where: { $0.role == .assistant }) {
                        self.messages[index].content += token
                    }
                }
            }
            
            // End measurement
            let metrics = performanceMonitor.endMeasurement()
            print("Generation metrics: \(metrics)")
            
        } catch {
            messages[messages.count - 1].content = "Error: \(error.localizedDescription)"
        }
        
        isGenerating = false
    }
}
```

### SwiftUI Views

```swift
// ChatView.swift
struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    
    init(llmService: UnifiedLLMService) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(llmService: llmService))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if viewModel.isGenerating {
                            TypingIndicator()
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                    }
                }
            }
            
            // Input bar
            HStack(spacing: 12) {
                TextField("Type a message...", text: $viewModel.currentInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isInputFocused)
                    .onSubmit {
                        Task {
                            await viewModel.sendMessage()
                        }
                    }
                
                Button(action: {
                    Task {
                        await viewModel.sendMessage()
                    }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(viewModel.currentInput.isEmpty || viewModel.isGenerating)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Message bubble component
struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user ? Color.blue : Color(.secondarySystemBackground))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(16)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
}
```

---

## 12. Model Recommendations

### Small Models (1-3B parameters)

| Model | Size | Quantized Size | Use Case |
|-------|------|----------------|----------|
| Phi-3-mini | 2.7B | ~1.5GB (4-bit) | General chat, code |
| Gemma-2B | 2B | ~1GB (4-bit) | General purpose |
| Qwen2.5-1.5B | 1.5B | ~800MB (4-bit) | Multilingual |
| TinyLlama-1.1B | 1.1B | ~550MB (4-bit) | Basic tasks |
| StableLM-3B | 3B | ~1.6GB (4-bit) | Instruction following |

### Medium Models (3-7B parameters)

| Model | Size | Quantized Size | Use Case |
|-------|------|----------------|----------|
| Llama-3.2-3B | 3B | ~1.7GB (4-bit) | Advanced chat |
| Mistral-7B | 7B | ~3.8GB (4-bit) | High quality |
| Vicuna-7B | 7B | ~3.8GB (4-bit) | Conversation |
| Gemma-7B | 7B | ~3.8GB (4-bit) | Google quality |

### Model Selection Criteria

```swift
class ModelSelector {
    static func recommendModel(for device: UIDevice) -> ModelRecommendation {
        let memory = ProcessInfo.processInfo.physicalMemory
        let chipset = device.chipset // Custom extension
        
        if memory > 12_000_000_000 && chipset.isA17OrNewer {
            // High-end device
            return ModelRecommendation(
                name: "Mistral-7B-Instruct",
                quantization: .int4,
                framework: .mlx
            )
        } else if memory > 8_000_000_000 {
            // Mid-range device
            return ModelRecommendation(
                name: "Llama-3.2-3B",
                quantization: .int4,
                framework: .mlc
            )
        } else if memory > 6_000_000_000 {
            // Lower-mid device
            return ModelRecommendation(
                name: "Phi-3-mini",
                quantization: .int4,
                framework: .onnx
            )
        } else {
            // Entry-level device
            return ModelRecommendation(
                name: "TinyLlama-1.1B",
                quantization: .int4,
                framework: .tflite
            )
        }
    }
}
```

---

## 13. Performance Optimization

### Memory Management

```swift
class MemoryOptimizer {
    static func configureForLLM() {
        // Increase memory limit
        let memoryLimit = ProcessInfo.processInfo.physicalMemory / 2
        
        // Configure image cache
        URLCache.shared.memoryCapacity = 50_000_000 // 50MB
        URLCache.shared.diskCapacity = 100_000_000 // 100MB
        
        // Monitor memory pressure
        let queue = DispatchQueue.global(qos: .utility)
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: queue
        )
        
        source.setEventHandler {
            let event = source.data
            if event.contains(.warning) {
                // Clear caches
                self.clearCaches()
            } else if event.contains(.critical) {
                // Emergency cleanup
                self.emergencyCleanup()
            }
        }
        
        source.resume()
    }
    
    static func clearCaches() {
        // Clear model caches
        URLCache.shared.removeAllCachedResponses()
        
        // Notify frameworks to clear internal caches
        NotificationCenter.default.post(
            name: .clearModelCaches,
            object: nil
        )
    }
    
    static func emergencyCleanup() {
        // Force clear all non-essential memory
        // This is framework-specific
    }
}
```

### Battery Optimization

```swift
class BatteryOptimizer {
    private var observer: NSObjectProtocol?
    
    func startMonitoring() {
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.adjustPerformance()
        }
        
        UIDevice.current.isBatteryMonitoringEnabled = true
    }
    
    func adjustPerformance() {
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState
        
        if batteryLevel < 0.2 && batteryState == .unplugged {
            // Low power mode
            setLowPowerConfiguration()
        } else if batteryState == .charging {
            // Maximum performance when charging
            setHighPerformanceConfiguration()
        } else {
            // Balanced mode
            setBalancedConfiguration()
        }
    }
    
    private func setLowPowerConfiguration() {
        // Reduce thread count
        ProcessInfo.processInfo.processorCount = 2
        
        // Use smaller models
        ModelManager.shared.preferSmallModels = true
        
        // Reduce generation length
        GenerationOptions.default.maxTokens = 50
    }
}
```

### Performance Monitoring

```swift
class PerformanceMonitor {
    private var startTime: CFAbsoluteTime = 0
    private var firstTokenTime: CFAbsoluteTime = 0
    private var tokenCount = 0
    
    func startMeasurement() {
        startTime = CFAbsoluteTimeGetCurrent()
        tokenCount = 0
    }
    
    func recordFirstToken() {
        if firstTokenTime == 0 {
            firstTokenTime = CFAbsoluteTimeGetCurrent()
        }
    }
    
    func recordToken() {
        tokenCount += 1
        recordFirstToken()
    }
    
    func endMeasurement() -> PerformanceMetrics {
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        let timeToFirstToken = firstTokenTime - startTime
        let tokensPerSecond = Double(tokenCount) / totalTime
        
        return PerformanceMetrics(
            totalTime: totalTime,
            timeToFirstToken: timeToFirstToken,
            tokensPerSecond: tokensPerSecond,
            tokenCount: tokenCount,
            memoryUsed: reportMemoryUsage()
        )
    }
    
    private func reportMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
}
```

---

## 14. Troubleshooting

### Common Issues and Solutions

#### Model Loading Failures

```swift
enum ModelLoadError: Error {
    case fileNotFound
    case insufficientMemory
    case unsupportedFormat
    case corruptedModel
}

class ModelDiagnostics {
    static func diagnoseLoadFailure(error: Error, modelPath: String) -> DiagnosisResult {
        // Check file existence
        if !FileManager.default.fileExists(atPath: modelPath) {
            return DiagnosisResult(
                issue: .fileNotFound,
                solution: "Ensure model file is included in app bundle or downloaded correctly"
            )
        }
        
        // Check available memory
        let availableMemory = getAvailableMemory()
        let modelSize = getFileSize(modelPath)
        
        if modelSize > availableMemory {
            return DiagnosisResult(
                issue: .insufficientMemory,
                solution: "Use quantized model or close other apps"
            )
        }
        
        // Validate model format
        if !isValidModelFormat(modelPath) {
            return DiagnosisResult(
                issue: .unsupportedFormat,
                solution: "Convert model to supported format"
            )
        }
        
        return DiagnosisResult(
            issue: .unknown,
            solution: "Check console logs for detailed error"
        )
    }
}
```

#### Performance Issues

```swift
class PerformanceDiagnostics {
    static func analyzeSlowGeneration() -> [PerformanceIssue] {
        var issues: [PerformanceIssue] = []
        
        // Check thermal state
        if ProcessInfo.processInfo.thermalState == .critical {
            issues.append(.thermalThrottling)
        }
        
        // Check memory pressure
        if isMemoryPressureHigh() {
            issues.append(.memoryPressure)
        }
        
        // Check background apps
        if UIApplication.shared.backgroundTimeRemaining < 30 {
            issues.append(.backgroundThrottling)
        }
        
        return issues
    }
    
    static func suggestOptimizations(for issues: [PerformanceIssue]) -> [String] {
        return issues.map { issue in
            switch issue {
            case .thermalThrottling:
                return "Device is overheating. Let it cool down."
            case .memoryPressure:
                return "Close other apps to free memory."
            case .backgroundThrottling:
                return "Keep app in foreground for best performance."
            case .slowStorage:
                return "Free up storage space."
            }
        }
    }
}
```

### Debug Utilities

```swift
// Enable detailed logging
class LLMDebugger {
    static var isEnabled = false
    
    static func log(_ message: String, file: String = #file, line: Int = #line) {
        guard isEnabled else { return }
        
        let filename = URL(fileURLWithPath: file).lastPathComponent
        print("🤖 [\(filename):\(line)] \(message)")
    }
    
    static func logPerformance(_ metrics: PerformanceMetrics) {
        guard isEnabled else { return }
        
        print("""
        📊 Performance Metrics:
        - Total time: \(String(format: "%.2f", metrics.totalTime))s
        - First token: \(String(format: "%.3f", metrics.timeToFirstToken))s
        - Tokens/sec: \(String(format: "%.1f", metrics.tokensPerSecond))
        - Memory: \(ByteCountFormatter.string(fromByteCount: Int64(metrics.memoryUsed), countStyle: .memory))
        """)
    }
}
```

---

## Conclusion

This comprehensive guide covers all major frameworks for running LLMs locally on iOS. Each framework has its strengths and optimal use cases:

- **Apple Foundation Models**: Best for iOS 18+ with native integration
- **Core ML**: Ideal for Apple ecosystem integration
- **MLX**: Optimal for Apple Silicon performance
- **MLC-LLM**: Best for cross-platform compatibility
- **ONNX Runtime**: Good for multi-framework model support
- **ExecuTorch**: Excellent for PyTorch models
- **llama.cpp**: Most efficient for CPU-only inference
- **TensorFlow Lite**: Mature ecosystem with good tooling
- **picoLLM**: Specialized for compression
- **Swift Transformers**: Native Swift implementation

Choose based on your specific requirements for performance, compatibility, and model support.