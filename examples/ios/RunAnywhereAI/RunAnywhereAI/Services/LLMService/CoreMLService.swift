//
//  CoreMLService.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation
import CoreML

// MARK: - Core ML Text Generation Input/Output

@objc(TextGenerationInput)
@available(iOS 17.0, *)
class TextGenerationInput: NSObject, MLFeatureProvider {
    let inputIds: MLMultiArray
    
    var featureNames: Set<String> {
        ["input_ids"]
    }
    
    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "input_ids" {
            return MLFeatureValue(multiArray: inputIds)
        }
        return nil
    }
    
    init(inputIds: MLMultiArray) {
        self.inputIds = inputIds
        super.init()
    }
}

@available(iOS 17.0, *)
private class CoreMLTokenizer {
    private let vocabPath: String
    private var vocab: [String: Int] = [:]
    private var inverseVocab: [Int: String] = [:]
    
    init(vocabPath: String) throws {
        self.vocabPath = vocabPath
        try loadVocabulary()
    }
    
    private func loadVocabulary() throws {
        // In a real implementation, this would load from a tokenizer.json or vocab.txt file
        // For demonstration, create a simple vocabulary
        let commonTokens = [
            "<|endoftext|>": 0,
            "<|start|>": 1,
            " the": 2, " and": 3, " to": 4, " of": 5, " a": 6, " in": 7, " is": 8, " it": 9, " you": 10,
            " that": 11, " he": 12, " was": 13, " for": 14, " on": 15, " are": 16, " as": 17, " with": 18,
            " his": 19, " they": 20, " I": 21, " at": 22, " be": 23, " this": 24, " have": 25, " from": 26,
            " or": 27, " one": 28, " had": 29, " by": 30, " word": 31, " but": 32, " what": 33, " some": 34,
            " we": 35, " can": 36, " out": 37, " other": 38, " were": 39, " all": 40, " there": 41, " when": 42,
            " up": 43, " use": 44, " your": 45, " how": 46, " said": 47, " an": 48, " each": 49, " which": 50
        ]
        
        for (token, id) in commonTokens {
            vocab[token] = id
            inverseVocab[id] = token
        }
    }
    
    func encode(_ text: String) -> [Int32] {
        // Simple tokenization - in reality would use BPE or WordPiece
        var tokens: [Int32] = []
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        
        for word in words {
            let tokenKey = " " + word.lowercased()
            if let tokenId = vocab[tokenKey] {
                tokens.append(Int32(tokenId))
            } else {
                // Unknown token - use a hash of the word
                tokens.append(Int32(abs(word.hashValue) % 1000 + 100))
            }
        }
        
        return tokens.isEmpty ? [1] : tokens // Return start token if empty
    }
    
    func decode(_ tokens: [Int32]) -> String {
        tokens.compactMap { tokenId in
            inverseVocab[Int(tokenId)] ?? "unk"
        }.joined(separator: "")
    }
}

@available(iOS 17.0, *)
class CoreMLService: BaseLLMService {
    
    // MARK: - Core ML Specific Capabilities
    
    override var supportsStreaming: Bool { true }
    override var supportsQuantization: Bool { true }
    override var supportsBatching: Bool { true }
    override var supportsMultiModal: Bool { false } // Will be true with Vision models
    override var quantizationFormats: [QuantizationFormat] { [.fp16, .int8] }
    override var maxContextLength: Int { 2048 }
    override var supportsCustomOperators: Bool { true }
    override var hardwareAcceleration: [HardwareAcceleration] { [.neuralEngine, .gpu, .cpu] }
    override var supportedFormats: [ModelFormat] { [.coreML, .mlPackage] }
    
    override var frameworkInfo: FrameworkInfo {
        FrameworkInfo(
            name: "Core ML",
            version: "6.0",
            developer: "Apple Inc.",
            description: "Apple's framework for on-device machine learning with Neural Engine optimization",
            website: URL(string: "https://developer.apple.com/coreml/"),
            documentation: URL(string: "https://developer.apple.com/documentation/coreml"),
            minimumOSVersion: "17.0",
            requiredCapabilities: ["coreml"],
            optimizedFor: [.appleNeuralEngine, .metalPerformanceShaders, .lowLatency],
            features: [
                .onDeviceInference,
                .customModels,
                .quantization,
                .customOperators,
                .swiftPackageManager,
                .lowPowerMode,
                .offlineCapable
            ]
        )
    }
    
    override var name: String { "Core ML" }
    
    override var supportedModels: [ModelInfo] {
        get {
            [
        ModelInfo(
            id: "gpt2-coreml",
            name: "GPT2-CoreML.mlpackage",
            format: .coreML,
            size: "548MB",
            framework: .coreML,
            quantization: "Float16",
            contextLength: 1024,
            downloadURL: URL(
                string: "https://huggingface.co/coreml-community/gpt2-coreml/resolve/main/GPT2.mlpackage.zip"
            )!,
            description: "GPT-2 model converted to Core ML format with Neural Engine acceleration",
            minimumMemory: 1_000_000_000,
            recommendedMemory: 2_000_000_000
        ),
        ModelInfo(
            id: "distilgpt2-coreml",
            name: "DistilGPT2-CoreML.mlpackage",
            format: .coreML,
            size: "267MB",
            framework: .coreML,
            quantization: "Float16",
            contextLength: 1024,
            downloadURL: URL(
                string: "https://huggingface.co/coreml-community/distilgpt2-coreml/resolve/main/DistilGPT2.mlpackage.zip"
            )!,
            description: "Smaller DistilGPT2 model optimized for mobile devices",
            minimumMemory: 500_000_000,
            recommendedMemory: 1_000_000_000
        ),
        ModelInfo(
            id: "openelm-270m-coreml",
            name: "OpenELM-270M.mlpackage",
            format: .coreML,
            size: "312MB",
            framework: .coreML,
            quantization: "Float16",
            contextLength: 2048,
            downloadURL: URL(
                string: "https://huggingface.co/apple/OpenELM-270M-Instruct/resolve/main/OpenELM-270M-Instruct-coreml.zip"
            )!,
            description: "Apple's OpenELM 270M model optimized for on-device inference",
            minimumMemory: 400_000_000,
            recommendedMemory: 800_000_000
        )
            ]
        }
        set {}
    }
    
    private var model: MLModel?
    private var tokenizer: CoreMLTokenizer?
    private var currentModelInfo: ModelInfo?
    private let maxSequenceLength = 512
    
    override func initialize(modelPath: String) async throws {
        // Verify model file exists and is valid
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LLMError.modelNotFound
        }
        
        let modelURL = URL(fileURLWithPath: modelPath)
        
        // Verify it's a Core ML model package
        guard modelPath.hasSuffix(".mlpackage") || modelPath.hasSuffix(".mlmodel") else {
            throw LLMError.unsupportedFormat
        }
        
        await MainActor.run {
            currentModelInfo = supportedModels.first { modelInfo in
                modelPath.contains(modelInfo.name) || modelPath.contains(modelInfo.id)
            }
        }
        
        // Configure Core ML to use Neural Engine when available
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all // Use Neural Engine, GPU, and CPU
        
        do {
            // For .mlpackage, load directly
            if modelPath.hasSuffix(".mlpackage") {
                model = try MLModel(contentsOf: modelURL, configuration: configuration)
            } else {
                // For .mlmodel, compile first if needed
                let compiledURL = try await MLModel.compileModel(at: modelURL)
                model = try MLModel(contentsOf: compiledURL, configuration: configuration)
            }
            
            // Initialize tokenizer (in a real app, this would come from the model bundle)
            let tokenizerPath = modelURL.deletingLastPathComponent().appendingPathComponent("tokenizer.json").path
            tokenizer = try CoreMLTokenizer(vocabPath: tokenizerPath)
        } catch {
            // Fallback to basic tokenizer if no tokenizer file found
            tokenizer = try CoreMLTokenizer(vocabPath: "")
        }
        
        // Verify model has expected inputs/outputs
        guard let model = model else {
            throw LLMError.initializationFailed("Failed to load Core ML model")
        }
        
        let description = model.modelDescription
        print("Core ML Model loaded successfully:")
        print("- Input: \(description.inputDescriptionsByName.keys)")
        print("- Output: \(description.outputDescriptionsByName.keys)")
        
        isInitialized = true
    }
    
    override func generate(prompt: String, options: GenerationOptions) async throws -> String {
        guard isInitialized, let model = model, let tokenizer = tokenizer else {
            throw LLMError.notInitialized()
        }
        
        var result = ""
        try await streamGenerate(prompt: prompt, options: options) { token in
            result += token
        }
        
        return result
    }
    
    override func streamGenerate(
        prompt: String,
        options: GenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard isInitialized, let model = model, let tokenizer = tokenizer else {
            throw LLMError.notInitialized()
        }
        
        // Real Core ML implementation would:
        // 1. Tokenize prompt: let inputTokens = tokenizer.encode(prompt)
        // 2. Create MLMultiArray: let inputArray = try createInputArray(from: inputTokens)
        // 3. Run prediction: let output = try model.prediction(from: TextGenerationInput(inputIds: inputArray))
        // 4. Sample from logits and decode tokens iteratively
        
        // For demonstration, simulate Core ML inference behavior:
        let inputTokens = tokenizer.encode(prompt)
        print("Core ML: Processing \(inputTokens.count) input tokens")
        
        // Simulate variable-length intelligent responses based on Core ML patterns
        let responseTemplate = generateCoreMLResponse(for: prompt, modelInfo: currentModelInfo)
        let responseWords = responseTemplate.components(separatedBy: .whitespacesAndNewlines)
        
        for (index, word) in responseWords.enumerated() {
            // Core ML inference is typically faster than CPU-only solutions
            let delay = word.count > 8 ? 60_000_000 : 40_000_000 // 60ms or 40ms
            try await Task.sleep(nanoseconds: UInt64(delay))
            
            // Apply generation options
            let processedWord = applyCoreMLSampling(word, options: options)
            onToken(processedWord + " ")
            
            // Stop at max tokens
            if index >= options.maxTokens - 1 {
                break
            }
            
            // Simulate Neural Engine processing batches
            if index > 0 && index % 8 == 0 {
                try await Task.sleep(nanoseconds: 20_000_000) // 20ms batch processing pause
            }
        }
    }
    
    // MARK: - Private Core ML Helper Methods
    
    private func generateCoreMLResponse(for prompt: String, modelInfo: ModelInfo?) -> String {
        let modelName = modelInfo?.name ?? "Core ML model"
        
        // Core ML responses tend to be more structured and hardware-optimized
        if prompt.lowercased().contains("performance") || prompt.lowercased().contains("speed") {
            return "Core ML with \(modelName) leverages Apple's Neural Engine for accelerated inference. The model runs efficiently on-device with optimized memory usage and low latency, perfect for real-time applications."
        } else if prompt.lowercased().contains("privacy") || prompt.lowercased().contains("secure") {
            return "Running \(modelName) with Core ML ensures complete privacy - all inference happens locally on your device with no data sent to external servers. Apple's secure enclave and Neural Engine provide hardware-level security."
        } else if prompt.lowercased().contains("apple") || prompt.lowercased().contains("ios") {
            return "This \(modelName) is optimized for Apple devices using Core ML framework. It takes advantage of the Neural Engine, GPU, and CPU for maximum performance while maintaining energy efficiency."
        } else {
            return "Using \(modelName) via Core ML framework for hardware-accelerated inference. This approach provides excellent performance on Apple devices with automatic optimization for Neural Engine when available."
        }
    }
    
    private func applyCoreMLSampling(_ word: String, options: GenerationOptions) -> String {
        // Core ML typically has more deterministic outputs
        if options.temperature < 0.5 {
            return word.lowercased()
        } else if options.temperature > 0.7 {
            // Slightly more variation at higher temperatures
            return word.count > 3 ? word.capitalized : word
        }
        return word
    }
    
    private func createInputArray(from tokens: [Int32]) throws -> MLMultiArray {
        let inputShape = [1, min(tokens.count, maxSequenceLength)] as [NSNumber]
        let inputArray = try MLMultiArray(shape: inputShape, dataType: .int32)
        
        for (index, token) in tokens.prefix(maxSequenceLength).enumerated() {
            inputArray[index] = NSNumber(value: token)
        }
        
        return inputArray
    }
    
    override func getModelInfo() -> ModelInfo? {
        currentModelInfo
    }
    
    override func cleanup() {
        // Core ML models are automatically managed by the system
        // Just clear our references
        model = nil
        tokenizer = nil
        currentModelInfo = nil
        isInitialized = false
        
        // Force garbage collection to free model memory
        // This is particularly important for large models
        Task {
            await Task.yield()
        }
    }
    
    deinit {
        cleanup()
    }
}
