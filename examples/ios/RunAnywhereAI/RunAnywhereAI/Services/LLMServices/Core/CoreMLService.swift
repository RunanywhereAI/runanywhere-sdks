//
//  CoreMLService.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation
import CoreML

// MARK: - Core ML Text Generation Service

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
            version: "8.0", // Updated for iOS 17+ in 2025
            developer: "Apple Inc.",
            description: "Apple's enhanced machine learning framework with stateful models, advanced quantization, and optimized Neural Engine performance (2025)",
            website: URL(string: "https://developer.apple.com/coreml/"),
            documentation: URL(string: "https://developer.apple.com/documentation/coreml"),
            minimumOSVersion: "17.0", // iOS 17+ for latest stateful model features
            requiredCapabilities: ["coreml", "neural-engine"],
            optimizedFor: [.appleNeuralEngine, .metalPerformanceShaders, .lowLatency, .memoryEfficient],
            features: [
                .onDeviceInference,
                .customModels,
                .quantization,
                .customOperators,
                .multiModal,     // NEW 2025 - Vision + Language models
                .swiftPackageManager,
                .lowPowerMode,
                .offlineCapable
            ]
        )
    }

    override var name: String { "Core ML" }

    override var supportedModels: [ModelInfo] {
        get {
            // Get models from the single source of truth
            ModelURLRegistry.shared.getAllModels(for: .coreML)
        }
        set {
            // Models are managed centrally in ModelURLRegistry
            // This setter is here for protocol compliance but does nothing
        }
    }

    private var model: MLModel?
    private var tokenizerAdapter: TokenizerAdapter?  // Model-agnostic tokenizer adapter
    private var currentModelInfo: ModelInfo?
    private var modelAdapter: CoreMLModelAdapter?  // Model-specific adapter

    override func initialize(modelPath: String) async throws {
        // Verify model file exists and is valid
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LLMError.modelNotFound
        }

        let modelURL = URL(fileURLWithPath: modelPath)

        // Verify it's a Core ML model using format manager
        let format = ModelFormat.from(extension: modelURL.pathExtension)
        let formatManager = ModelFormatManager.shared
        let handler = formatManager.getHandler(for: modelURL, format: format)

        guard handler.canHandle(url: modelURL, format: format) &&
              (format == .coreML || format == .mlPackage) else {
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
            print("Loading Core ML model: \(modelPath)")

            // Check device capabilities for optimal configuration
            if await isNeuralEngineAvailable() {
                configuration.computeUnits = .all // Neural Engine + GPU + CPU
                print("Neural Engine detected - using accelerated inference")
            } else {
                configuration.computeUnits = .cpuAndGPU // Fallback to CPU + GPU
                print("Using CPU + GPU inference")
            }

            // REAL Core ML model loading
            if handler.isDirectoryBasedModel(url: modelURL) {
                // Load directory-based model (e.g., .mlpackage)
                print("Loading directory-based model from: \(modelURL.path)")
                model = try MLModel(contentsOf: modelURL, configuration: configuration)
                print("✅ Loaded directory-based model successfully")
            } else {
                // Compile single file model (e.g., .mlmodel)
                print("Processing single file model...")
                print("Model path: \(modelURL.path)")

                // Check if already compiled
                let compiledModelName = modelURL.lastPathComponent + "c"
                let compiledModelPath = modelURL.deletingLastPathComponent().appendingPathComponent(compiledModelName)

                let compiledURL: URL
                if FileManager.default.fileExists(atPath: compiledModelPath.path) {
                    print("✅ Found existing compiled model at: \(compiledModelPath.path)")
                    compiledURL = compiledModelPath
                } else {
                    print("⏳ Compiling .mlmodel for first time... This may take a few minutes for large models.")
                    print("Note: Future loads will be much faster.")

                    do {
                        let compiledPath = try await MLModel.compileModel(at: modelURL)
                        compiledURL = compiledPath
                        print("✅ Model compiled successfully at: \(compiledURL.path)")
                    } catch {
                        print("❌ Model compilation failed: \(error)")
                        throw LLMError.modelLoadFailed(reason: "Failed to compile Core ML model: \(error.localizedDescription)", framework: "Core ML")
                    }
                }

                print("Loading compiled model...")
                model = try MLModel(contentsOf: compiledURL, configuration: configuration)
                print("✅ Loaded compiled .mlmodel successfully")
            }

            // Create model-specific adapter
            guard let currentModelInfo = currentModelInfo else {
                throw LLMError.initializationFailed("Model info not found")
            }

            guard let loadedModel = model else {
                throw LLMError.initializationFailed("Model loading failed")
            }

            modelAdapter = CoreMLAdapterFactory.createAdapter(for: currentModelInfo, model: loadedModel)

            guard let adapter = modelAdapter else {
                throw LLMError.initializationFailed("No compatible adapter found for model: \(currentModelInfo.name)")
            }

            print("✅ Using adapter: \(type(of: adapter)) for model: \(currentModelInfo.name)")

            // Try to load tokenizer adapter
            let modelDirectory = modelURL.deletingLastPathComponent().path
            tokenizerAdapter = TokenizerAdapterFactory.createAdapter(for: modelDirectory, framework: .coreML)

            if let adapter = tokenizerAdapter {
                print("✅ Loaded tokenizer adapter: \(type(of: adapter)) with \(adapter.vocabularySize) tokens")
            } else {
                print("⚠️ No tokenizer adapter found, using basic tokenizer")
                // Create a basic adapter as fallback
                tokenizerAdapter = BaseTokenizerAdapter(tokenizer: BaseTokenizer(), modelType: "unknown")
            }
        } catch {
            print("❌ Core ML model loading failed: \(error)")
            throw LLMError.modelLoadFailed(reason: "Failed to load Core ML model: \(error.localizedDescription)", framework: "Core ML")
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
        guard isInitialized, model != nil, tokenizerAdapter != nil else {
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
        guard isInitialized, model != nil, let adapter = modelAdapter, let tokenizerAdapter = tokenizerAdapter else {
            throw LLMError.notInitialized()
        }

        // Use tokenizer adapter for encoding
        let intTokens = tokenizerAdapter.encode(prompt)
        let inputTokens = intTokens.map { Int32($0) }
        print("Core ML: Processing \(inputTokens.count) input tokens using \(type(of: tokenizerAdapter))")

        // Track generated tokens for autoregressive generation
        var allTokens = inputTokens
        var generatedTokens: [Int32] = []

        do {
            // Get model and adapter info
            guard let model = model else {
                throw LLMError.notInitialized()
            }

            let inputNames = Array(model.modelDescription.inputDescriptionsByName.keys)
            let outputNames = Array(model.modelDescription.outputDescriptionsByName.keys)

            print("Core ML Model Info:")
            print("- Input names: \(inputNames)")
            print("- Output names: \(outputNames)")
            print("- Using adapter: \(type(of: adapter))")
            print("- Max sequence length: \(adapter.maxSequenceLength)")

            // Autoregressive generation loop using adapter
            for _ in 0..<options.maxTokens {
                // Use sliding window approach for long sequences
                let contextTokens: [Int32]
                if allTokens.count > adapter.maxSequenceLength {
                    contextTokens = Array(allTokens.suffix(adapter.maxSequenceLength))
                } else {
                    contextTokens = allTokens
                }

                // Create input arrays using the adapter
                let inputArrays = try adapter.createInputArrays(from: contextTokens)

                // Create feature provider from adapter's input arrays
                let inputFeatures = try MLDictionaryFeatureProvider(dictionary: inputArrays.mapValues { MLFeatureValue(multiArray: $0) })

                // Run Core ML prediction
                let prediction = try await model.prediction(from: inputFeatures)

                // Use adapter to sample next token from prediction
                let lastTokenPosition = min(contextTokens.count - 1, adapter.maxSequenceLength - 1)
                let nextToken = try adapter.sampleNextToken(from: prediction, lastTokenPosition: lastTokenPosition, temperature: Double(options.temperature))

                // Check for end of sequence
                if nextToken == 0 || nextToken == 1 { // Common EOS tokens
                    break
                }

                // Add to sequence
                allTokens.append(nextToken)
                generatedTokens.append(nextToken)

                // Decode and emit token using tokenizer adapter
                let decodedText = tokenizerAdapter.decodeToken(Int(nextToken))
                print("Tokenizer adapter decoded token \(nextToken) -> '\(decodedText)'")

                // Ensure we emit non-empty text
                if !decodedText.isEmpty {
                    onToken(decodedText)
                } else {
                    // Fallback for empty decode - emit space to show progress
                    onToken(" ")
                    print("Warning: Empty decode for token \(nextToken), emitting space")
                }

                // Core ML inference timing (Neural Engine is quite fast)
                try await Task.sleep(nanoseconds: 30_000_000) // 30ms per token

                // Context length is now handled in the generation loop with sliding window
            }

            print("Core ML generated \(generatedTokens.count) tokens successfully")
        } catch {
            print("Core ML inference failed: \(error)")
            throw error
        }
    }

    // MARK: - Private Core ML Helper Methods (Generic)

    override func getModelInfo() -> ModelInfo? {
        currentModelInfo
    }

    override func cleanup() {
        // Core ML models are automatically managed by the system
        // Just clear our references
        model = nil
        tokenizerAdapter = nil
        currentModelInfo = nil
        modelAdapter = nil
        isInitialized = false

        // Force garbage collection to free model memory
        // This is particularly important for large models
        Task {
            await Task.yield()
        }
    }

    private func isNeuralEngineAvailable() async -> Bool {
        // Check if device has Neural Engine (A11 and later)
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelName = String(bytes: Data(bytes: &systemInfo.machine, count: Int(_SYS_NAMELEN)), encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? ""

        // Neural Engine available on A11+ (iPhone X+) and all M-series chips
        let neuralEngineDevices = [
            "iPhone10", "iPhone11", "iPhone12", "iPhone13", "iPhone14", "iPhone15", "iPhone16", "iPhone17", // iPhone X+
            "iPad8", "iPad11", "iPad12", "iPad13", "iPad14", "iPad16", // iPad Pro with A12X+
            "arm64" // M-series Macs
        ]

        let hasNeuralEngine = neuralEngineDevices.contains { modelName.contains($0) }

        if hasNeuralEngine {
            print("🧠 Neural Engine available on device: \(modelName)")
        } else {
            print("⚠️ Neural Engine not available on device: \(modelName)")
        }

        return hasNeuralEngine
    }

    deinit {
        cleanup()
    }
}
