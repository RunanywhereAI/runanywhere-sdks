//
//  CoreMLService.swift
//  RunAnywhereAI
//

import Foundation
import CoreML
import Accelerate

@available(iOS 17.0, *)
class CoreMLService: LLMProtocol {
    var name: String = "Core ML"
    var isInitialized: Bool = false
    
    private var model: MLModel?
    private var modelPath: String = ""
    private var tokenizer: SimpleTokenizer?
    
    func initialize(modelPath: String) async throws {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LLMError.modelNotFound
        }
        
        // Check if it's a Core ML model
        let url = URL(fileURLWithPath: modelPath)
        guard url.pathExtension == "mlpackage" || url.pathExtension == "mlmodel" else {
            throw LLMError.unsupportedFormat
        }
        
        self.modelPath = modelPath
        
        // Configure model
        let config = MLModelConfiguration()
        config.computeUnits = .all // Use CPU, GPU, and Neural Engine
        
        // Load model
        do {
            model = try MLModel(contentsOf: url, configuration: config)
            
            // Initialize tokenizer
            tokenizer = SimpleTokenizer()
            
            isInitialized = true
        } catch {
            throw LLMError.initializationFailed(error.localizedDescription)
        }
    }
    
    func generate(prompt: String, options: GenerationOptions) async throws -> String {
        guard isInitialized, let model = model else {
            throw LLMError.notInitialized
        }
        
        var result = ""
        try await streamGenerate(prompt: prompt, options: options) { token in
            result += token
        }
        
        return result
    }
    
    func streamGenerate(
        prompt: String,
        options: GenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard isInitialized, let model = model, let tokenizer = tokenizer else {
            throw LLMError.notInitialized
        }
        
        // Tokenize input
        let inputTokens = tokenizer.encode(prompt)
        
        // Prepare input for Core ML model
        // Note: Actual implementation depends on model's input format
        let inputArray = try MLMultiArray(shape: [1, inputTokens.count as NSNumber], dataType: .int32)
        for (index, token) in inputTokens.enumerated() {
            inputArray[index] = NSNumber(value: token)
        }
        
        // Create feature provider
        let input = CoreMLInput(tokens: inputArray)
        
        var generatedTokens: [Int32] = []
        var currentContext = inputTokens
        
        // Generate tokens one by one
        for _ in 0..<options.maxTokens {
            // Run inference
            let output = try model.prediction(from: input)
            
            // Extract logits from output
            guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
                throw LLMError.inferenceError("Failed to get logits from model output")
            }
            
            // Sample next token
            let nextToken = sampleToken(from: logits, temperature: options.temperature, topP: options.topP)
            generatedTokens.append(nextToken)
            
            // Decode token to text
            let text = tokenizer.decode([nextToken])
            onToken(text)
            
            // Check for end token
            if nextToken == tokenizer.endToken {
                break
            }
            
            // Update context for next iteration
            currentContext.append(nextToken)
            
            // Prepare next input
            let nextInputArray = try MLMultiArray(shape: [1, currentContext.count as NSNumber], dataType: .int32)
            for (index, token) in currentContext.enumerated() {
                nextInputArray[index] = NSNumber(value: token)
            }
            input.tokens = nextInputArray
        }
    }
    
    func getModelInfo() -> ModelInfo? {
        guard isInitialized else { return nil }
        
        return ModelInfo(
            id: "coreml-model",
            name: "Core ML Model",
            size: getModelSize(),
            format: .coreML,
            quantization: "FP16",
            contextLength: 2048,
            framework: .coreML
        )
    }
    
    func cleanup() {
        model = nil
        tokenizer = nil
        isInitialized = false
    }
    
    // MARK: - Private Methods
    
    private func sampleToken(from logits: MLMultiArray, temperature: Float, topP: Float) -> Int32 {
        let vocabSize = logits.shape[logits.shape.count - 1].intValue
        
        // Convert logits to probabilities
        var logitsArray = [Float](repeating: 0, count: vocabSize)
        for i in 0..<vocabSize {
            logitsArray[i] = logits[[0, i] as [NSNumber]].floatValue
        }
        
        // Apply temperature
        if temperature != 1.0 {
            vDSP_vsdiv(logitsArray, 1, [temperature], &logitsArray, 1, vDSP_Length(vocabSize))
        }
        
        // Softmax
        var probabilities = softmax(logitsArray)
        
        // Apply top-p (nucleus) sampling
        if topP < 1.0 {
            probabilities = applyTopP(probabilities, p: topP)
        }
        
        // Sample from distribution
        let random = Float.random(in: 0..<1)
        var cumulative: Float = 0
        
        for (index, prob) in probabilities.enumerated() {
            cumulative += prob
            if cumulative >= random {
                return Int32(index)
            }
        }
        
        return Int32(vocabSize - 1)
    }
    
    private func softmax(_ input: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: input.count)
        
        // Find max for numerical stability
        let maxVal = input.max() ?? 0
        
        // Compute exp(x - max)
        var expValues = input.map { exp($0 - maxVal) }
        
        // Sum of exp values
        let sum = expValues.reduce(0, +)
        
        // Normalize
        output = expValues.map { $0 / sum }
        
        return output
    }
    
    private func applyTopP(_ probabilities: [Float], p: Float) -> [Float] {
        // Sort indices by probability (descending)
        let sortedIndices = probabilities.indices.sorted { probabilities[$0] > probabilities[$1] }
        
        var cumulative: Float = 0
        var cutoffIndex = probabilities.count
        
        for (i, index) in sortedIndices.enumerated() {
            cumulative += probabilities[index]
            if cumulative >= p {
                cutoffIndex = i + 1
                break
            }
        }
        
        // Zero out probabilities below cutoff
        var filtered = [Float](repeating: 0, count: probabilities.count)
        for i in 0..<cutoffIndex {
            filtered[sortedIndices[i]] = probabilities[sortedIndices[i]]
        }
        
        // Renormalize
        let sum = filtered.reduce(0, +)
        return filtered.map { $0 / sum }
    }
    
    private func getModelSize() -> String {
        guard let url = URL(string: modelPath) else { return "Unknown" }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }
        } catch {
            print("Error getting model size: \(error)")
        }
        
        return "Unknown"
    }
}

// MARK: - Core ML Input/Output

private class CoreMLInput: NSObject, MLFeatureProvider {
    var tokens: MLMultiArray
    
    init(tokens: MLMultiArray) {
        self.tokens = tokens
        super.init()
    }
    
    var featureNames: Set<String> {
        return ["tokens"]
    }
    
    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "tokens":
            return MLFeatureValue(multiArray: tokens)
        default:
            return nil
        }
    }
}

// MARK: - Simple Tokenizer

private class SimpleTokenizer {
    private var vocabulary: [String: Int32] = [:]
    private var reverseVocabulary: [Int32: String] = [:]
    let endToken: Int32 = 2
    
    init() {
        // Build a simple vocabulary
        // In real implementation, this would load from tokenizer config
        buildVocabulary()
    }
    
    func encode(_ text: String) -> [Int32] {
        // Simple word-based tokenization
        let words = text.lowercased().split(separator: " ")
        return words.compactMap { vocabulary[String($0)] ?? vocabulary["<unk>"] }
    }
    
    func decode(_ tokens: [Int32]) -> String {
        return tokens.compactMap { reverseVocabulary[$0] }.joined(separator: " ")
    }
    
    private func buildVocabulary() {
        // Special tokens
        let specialTokens = ["<pad>", "<unk>", "<eos>", "<bos>"]
        for (index, token) in specialTokens.enumerated() {
            vocabulary[token] = Int32(index)
            reverseVocabulary[Int32(index)] = token
        }
        
        // Common words (simplified)
        let commonWords = [
            "i", "you", "the", "a", "is", "are", "am", "to", "of", "and",
            "in", "that", "have", "it", "for", "not", "on", "with", "he",
            "as", "do", "at", "this", "but", "his", "by", "from", "they",
            "we", "say", "her", "she", "or", "an", "will", "my", "one",
            "all", "would", "there", "their", "what", "so", "up", "out",
            "if", "about", "who", "get", "which", "go", "me", "when",
            "make", "can", "like", "time", "no", "just", "him", "know",
            "take", "people", "into", "year", "your", "good", "some",
            "could", "them", "see", "other", "than", "then", "now", "look",
            "only", "come", "its", "over", "think", "also", "back", "after",
            "use", "two", "how", "our", "work", "first", "well", "way",
            "even", "new", "want", "because", "any", "these", "give", "day",
            "most", "us", "hello", "world", "ai", "model", "running", "core",
            "ml", "apple", "silicon", "neural", "engine", "inference"
        ]
        
        var nextId = Int32(specialTokens.count)
        for word in commonWords {
            vocabulary[word] = nextId
            reverseVocabulary[nextId] = word
            nextId += 1
        }
    }
}