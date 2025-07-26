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
    private var tokenizer: Tokenizer?
    private let memoryQueue = DispatchQueue(label: "com.runanywhere.coreml.memory")
    private var currentMemoryUsage: Int64 = 0
    private var modelConfiguration: MLModelConfiguration?
    
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
        
        // Check memory availability
        try checkMemoryAvailability()
        
        // Configure model with memory-aware settings
        let config = MLModelConfiguration()
        modelConfiguration = config
        
        // Determine optimal compute units based on available memory
        let availableMemory = getAvailableMemory()
        if availableMemory > 8_000_000_000 { // > 8GB
            config.computeUnits = .all // Use CPU, GPU, and Neural Engine
        } else if availableMemory > 4_000_000_000 { // > 4GB
            config.computeUnits = .cpuAndGPU // Skip Neural Engine to save memory
        } else {
            config.computeUnits = .cpuOnly // Most memory-efficient
        }
        
        // Load model
        do {
            model = try await Task {
                try MLModel(contentsOf: url, configuration: config)
            }.value
            
            // Initialize tokenizer
            tokenizer = TokenizerFactory.createForFramework(.coreML, modelPath: modelPath)
            
            // Track memory usage
            currentMemoryUsage = estimateMemoryUsage()
            
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
        let inputTokens = tokenizer.encode(prompt).map { Int32($0) }
        
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
            let text = tokenizer.decode([Int(nextToken)])
            onToken(text)
            
            // Check for end token
            if nextToken == Int32(tokenizer.eosToken) {
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
        memoryQueue.sync {
            // Clear model and configuration
            model = nil
            modelConfiguration = nil
            tokenizer = nil
            
            // Force memory cleanup
            autoreleasepool {
                // This helps ensure Core ML releases all resources
                MLModel.compileModel(at: URL(fileURLWithPath: "/dev/null")) { _ in }
            }
            
            currentMemoryUsage = 0
            isInitialized = false
        }
    }
    
    deinit {
        cleanup()
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
        let url = URL(fileURLWithPath: modelPath)
        
        if url.pathExtension == "mlpackage" {
            // Calculate total size of mlpackage directory
            var totalSize: Int64 = 0
            
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += Int64(fileSize)
                    }
                }
            }
            
            return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        } else {
            // Single file
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = attributes[.size] as? Int64 {
                    return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                }
            } catch {
                print("Error getting model size: \(error)")
            }
        }
        
        return "Unknown"
    }
}

// MARK: - Memory Management

@available(iOS 17.0, *)
extension CoreMLService {
    private func checkMemoryAvailability() throws {
        let availableMemory = getAvailableMemory()
        
        // Core ML models typically need 2-4GB minimum
        let requiredMemory: Int64 = 2_000_000_000
        
        if availableMemory < requiredMemory {
            throw LLMError.insufficientMemory
        }
    }
    
    private func getAvailableMemory() -> Int64 {
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = getUsedMemory()
        return availableMemory - usedMemory
    }
    
    private func getUsedMemory() -> Int64 {
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
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
    
    private func estimateMemoryUsage() -> Int64 {
        // Core ML models can use 2-3x their file size in memory
        let url = URL(fileURLWithPath: modelPath)
        var fileSize: Int64 = 0
        
        if url.pathExtension == "mlpackage" {
            // Calculate total size of mlpackage
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        fileSize += Int64(size)
                    }
                }
            }
        } else {
            // Single file
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? Int64 {
                fileSize = size
            }
        }
        
        // Core ML typically uses 2-3x file size when loaded
        return Int64(Double(fileSize) * 2.5)
    }
    
    func getMemoryUsage() -> (current: Int64, peak: Int64) {
        return memoryQueue.sync {
            (current: currentMemoryUsage, peak: currentMemoryUsage)
        }
    }
    
    // Dynamic compute unit adjustment based on memory pressure
    func adjustComputeUnits() {
        guard let config = modelConfiguration else { return }
        
        let availableMemory = getAvailableMemory()
        
        if availableMemory < 1_000_000_000 { // < 1GB
            // Switch to CPU only to reduce memory pressure
            config.computeUnits = .cpuOnly
        } else if availableMemory < 2_000_000_000 { // < 2GB
            // Use CPU and GPU, avoid Neural Engine
            config.computeUnits = .cpuAndGPU
        } else {
            // Plenty of memory, use all units
            config.computeUnits = .all
        }
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

