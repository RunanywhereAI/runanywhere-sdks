//
//  ExecuTorchService.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/30/25.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import ExecuTorch

// MARK: - ExecuTorch Model Wrapper

private class ExecuTorchModelWrapper {
    let modelPath: String
    let tokenizerPath: String?
    let module: Module?
    
    init(modelPath: String, tokenizerPath: String? = nil) throws {
        self.modelPath = modelPath
        self.tokenizerPath = tokenizerPath
        
        // Initialize Module for inference
        self.module = Module(filePath: modelPath)
    }
    
    func load() async throws {
        guard let module = module else {
            throw LLMError.modelNotFound
        }
        
        // Load the model
        try module.load("forward")
    }
    
    var isLoaded: Bool {
        return module != nil
    }
}

class ExecuTorchService: BaseLLMService {
    // MARK: - ExecuTorch Specific Capabilities
    
    override var supportsStreaming: Bool { true }
    override var supportsQuantization: Bool { true }
    override var supportsBatching: Bool { false }
    override var supportsMultiModal: Bool { false }
    override var quantizationFormats: [QuantizationFormat] { [.int4, .int8, .fp16] }
    override var maxContextLength: Int { 128000 } // Depends on model
    override var supportsCustomOperators: Bool { true }
    override var hardwareAcceleration: [HardwareAcceleration] { [.cpu, .gpu, .neuralEngine] }
    override var supportedFormats: [ModelFormat] { [.pte] }
    
    override var frameworkInfo: FrameworkInfo {
        FrameworkInfo(
            name: "ExecuTorch",
            version: "0.7.0",
            developer: "Meta (PyTorch Team)",
            description: "PyTorch's on-device AI stack for mobile and edge devices",
            website: URL(string: "https://pytorch.org/executorch"),
            documentation: URL(string: "https://pytorch.org/executorch/stable/index.html"),
            minimumOSVersion: "13.0",
            requiredCapabilities: [],
            optimizedFor: [.edgeDevice, .lowLatency, .memoryEfficient, .cpuOptimized],
            features: [
                .onDeviceInference,
                .customModels,
                .quantization,
                .openSource,
                .offlineCapable
            ]
        )
    }

    override var name: String { "ExecuTorch" }

    override var supportedModels: [ModelInfo] {
        get {
            // Get models from the single source of truth
            ModelURLRegistry.shared.getAllModels(for: .execuTorch)
        }
        set {
            // Models are managed centrally in ModelURLRegistry
            // This setter is here for protocol compliance but does nothing
        }
    }

    private var currentModelInfo: ModelInfo?
    private var modelWrapper: ExecuTorchModelWrapper?
    private var tokenizer: Tokenizer?

    override func initialize(modelPath: String) async throws {
        // First, try to identify the model from the path
        await MainActor.run {
            currentModelInfo = supportedModels.first { modelInfo in
                modelPath.contains(modelInfo.name) || modelPath.contains(modelInfo.id)
            }
        }
        
        // If modelPath is empty, try to find the model in the downloaded models
        var actualModelPath = modelPath
        if modelPath.isEmpty || !FileManager.default.fileExists(atPath: modelPath) {
            print("ExecuTorch: Model path empty or not found, searching for model...")
            
            // Look for the model in the Models directory
            let modelManager = await MainActor.run { ModelManager.shared }
            
            // Try to find based on the current selection or path hints
            var searchNames: [String] = []
            
            // Add names from currentModelInfo if available
            if let modelInfo = currentModelInfo {
                searchNames.append(modelInfo.name)
                searchNames.append(modelInfo.name.replacingOccurrences(of: ".pte", with: ""))
            }
            
            // Add names from the path
            let pathComponents = modelPath.components(separatedBy: "/")
            if let fileName = pathComponents.last {
                searchNames.append(fileName)
                searchNames.append(fileName.replacingOccurrences(of: ".pte", with: ""))
            }
            
            // Search for the model
            var foundPath: String? = nil
            for searchName in searchNames {
                let possiblePath = await modelManager.modelPath(for: searchName, framework: .execuTorch)
                if FileManager.default.fileExists(atPath: possiblePath.path) {
                    foundPath = possiblePath.path
                    print("ExecuTorch: Found model at \(foundPath!)")
                    break
                }
            }
            
            if let foundPath = foundPath {
                actualModelPath = foundPath
            } else {
                print("ExecuTorch: Could not find model. Searched names: \(searchNames)")
                throw LLMError.modelNotFound
            }
        }
        
        // Check if it's a PTE (PyTorch Edge) model
        guard actualModelPath.hasSuffix(".pte") else {
            throw LLMError.unsupportedFormat
        }
        
        // Check for associated tokenizer
        let modelDirectory = URL(fileURLWithPath: actualModelPath).deletingLastPathComponent().path
        let tokenizerPath = findTokenizer(in: modelDirectory)
        
        // Create model wrapper
        do {
            modelWrapper = try ExecuTorchModelWrapper(
                modelPath: actualModelPath,
                tokenizerPath: tokenizerPath
            )
            
            // Load the model
            try await modelWrapper?.load()
            
            // Initialize tokenizer
            if let tokenizerPath = tokenizerPath {
                // Try to load real tokenizer
                tokenizer = TokenizerFactory.createForFramework(.execuTorch, modelPath: modelDirectory)
                print("ExecuTorch: Loaded tokenizer from \(tokenizerPath)")
            } else {
                // Use base tokenizer as fallback
                tokenizer = BaseTokenizer()
                print("ExecuTorch: Using base tokenizer (no tokenizer.bin found)")
            }
            
            print("ExecuTorch Model initialized successfully:")
            print("- Model: \(actualModelPath)")
            print("- Tokenizer: \(tokenizerPath ?? "None")")
            print("- Backend: \(selectOptimalBackend())")
            
            isInitialized = true
        } catch {
            print("ExecuTorch initialization failed: \(error)")
            throw error
        }
    }

    override func generate(prompt: String, options: GenerationOptions) async throws -> String {
        guard isInitialized, let wrapper = modelWrapper else {
            throw LLMError.notInitialized()
        }
        
        // Use Module.forward for all models
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
        guard isInitialized, let wrapper = modelWrapper, let module = wrapper.module, let tokenizer = tokenizer else {
            throw LLMError.notInitialized()
        }
        
        // Manual token-by-token generation
        let inputIds = tokenizer.encode(prompt).map { Int32($0) }
        
        // Create input tensor - ExecuTorch uses ETensor instead of Tensor
        var generatedIds: [Int32] = []
        var allTokenIds = inputIds
        
        for _ in 0..<options.maxTokens {
            // Create input array for ExecuTorch
            let inputArray = allTokenIds.map { Float($0) }
            
            // Forward pass - create a single array input
            let outputs = try module.forward(inputArray)
            
            // Extract logits from output
            guard let outputArray = outputs as? [Float] else {
                throw LLMError.inferenceError("Invalid model output format")
            }
            
            // Get vocabulary size from output shape
            let vocabSize = outputArray.count / allTokenIds.count
            let lastTokenLogits = Array(outputArray.suffix(vocabSize))
            
            // Sample next token
            let nextToken = try sampleFromLogits(
                lastTokenLogits,
                temperature: options.temperature,
                topP: options.topP,
                topK: options.topK
            )
            
            generatedIds.append(Int32(nextToken))
            allTokenIds.append(Int32(nextToken))
            
            // Decode token
            let text = tokenizer.decode([Int(nextToken)])
            await MainActor.run {
                onToken(text)
            }
            
            // Small delay for smooth streaming
            try await Task.sleep(nanoseconds: 30_000_000) // 30ms per token
            
            // Check for end
            if nextToken == tokenizer.eosToken {
                break
            }
        }
    }

    override func getModelInfo() -> ModelInfo? {
        guard isInitialized else { return nil }
        
        // Return the actual model info if available
        if let modelInfo = currentModelInfo {
            return modelInfo
        }
        
        // Otherwise create a basic info
        return ModelInfo(
            id: "executorch-model",
            name: "ExecuTorch Model",
            format: .pte,
            size: getModelSize(),
            framework: .execuTorch,
            quantization: "FP16",
            contextLength: 2048
        )
    }

    override func cleanup() {
        modelWrapper = nil
        tokenizer = nil
        currentModelInfo = nil
        isInitialized = false
    }

    // MARK: - Private Methods
    
    private func findTokenizer(in directory: String) -> String? {
        let possiblePaths = [
            "\(directory)/tokenizer.bin",
            "\(directory)/tokenizer.model",
            "\(directory)/spiece.model"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }

    private func getModelSize() -> String {
        guard let modelPath = modelWrapper?.modelPath else { return "Unknown" }
        let url = URL(fileURLWithPath: modelPath)

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

    private func selectOptimalBackend() -> String {
        let memorySize = ProcessInfo.processInfo.physicalMemory

        #if canImport(UIKit)
        let device = UIDevice.current
        // Check device capabilities
        if device.userInterfaceIdiom == .pad && memorySize > 8_000_000_000 {
            return "coreml" // Best for latest chips
        }
        #endif

        if memorySize > 6_000_000_000 {
            return "metal" // Good GPU performance
        } else if memorySize > 4_000_000_000 {
            return "accelerate" // Optimized CPU
        } else {
            return "xnnpack" // Fallback
        }
    }
    
    private func sampleFromLogits(
        _ logits: [Float],
        temperature: Float,
        topP: Float?,
        topK: Int?
    ) throws -> Int {
        // Apply temperature
        var scaledLogits = logits
        if temperature > 0 {
            scaledLogits = scaledLogits.map { $0 / temperature }
        }
        
        // Convert to probabilities
        let maxLogit = scaledLogits.max() ?? 0
        let expLogits = scaledLogits.map { exp($0 - maxLogit) }
        let sumExp = expLogits.reduce(0, +)
        let probs = expLogits.map { $0 / sumExp }
        
        // Apply top-k filtering
        var validIndices = Array(0..<probs.count)
        if let topK = topK, topK > 0 {
            validIndices = probs.enumerated()
                .sorted { $0.element > $1.element }
                .prefix(topK)
                .map { $0.offset }
        }
        
        // Apply top-p (nucleus) filtering
        if let topP = topP, topP < 1.0 {
            let sortedProbs = validIndices
                .map { (index: $0, prob: probs[$0]) }
                .sorted { $0.prob > $1.prob }
            
            var cumulativeProb: Float = 0
            var nucleusIndices: [Int] = []
            
            for (index, prob) in sortedProbs {
                cumulativeProb += prob
                nucleusIndices.append(index)
                if cumulativeProb >= topP {
                    break
                }
            }
            
            validIndices = nucleusIndices
        }
        
        // Sample from the filtered distribution
        if validIndices.isEmpty {
            validIndices = [0] // Fallback to first token
        }
        
        // Simple sampling - in production, use proper random sampling
        let selectedIndex = validIndices.randomElement() ?? 0
        return selectedIndex
    }
}

// MARK: - ExecuTorch-Specific Extensions

extension ExecuTorchService {
    // Model export utilities
    static func exportModelGuide() -> String {
        """
        To export a PyTorch model for ExecuTorch:

        1. Install ExecuTorch:
           pip install executorch

        2. Export your model:
           ```python
           import torch
           from executorch.exir import to_edge

           # Load your model
           model = YourModel()
           model.eval()

           # Create example input
           example_input = torch.randn(1, 512)

           # Export to ExecuTorch
           edge_program = to_edge(model, (example_input,))

           # Save
           with open('model.pte', 'wb') as f:
               edge_program.write(f)
           ```
        """
    }

    // Profiling support
    func enableProfiling() {
        // In real implementation:
        // module?.executionConfig.enableProfiling = true
    }

    func getProfilingResults() -> [String: Any]? {
        // In real implementation would return profiling data
        nil
    }
}
