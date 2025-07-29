//
//  SwiftTransformersService.swift
//  RunAnywhereAI
//

import Foundation
import CoreML
import Models
import Generation
import Tokenizers
import Hub

@available(iOS 16.0, *)
class SwiftTransformersService: BaseLLMService {
    // MARK: - Properties
    
    private var languageModel: LanguageModel?
    private var modelPath: String = ""
    private var currentModelInfo: ModelInfo?
    
    // MARK: - Framework Info
    
    override var frameworkInfo: FrameworkInfo {
        FrameworkInfo(
            name: "Swift Transformers",
            version: "0.1.22",
            developer: "Hugging Face",
            description: "Native Swift implementation of transformer models with Core ML backend",
            website: URL(string: "https://github.com/huggingface/swift-transformers"),
            documentation: URL(string: "https://huggingface.co/docs/swift-transformers"),
            minimumOSVersion: "16.0",
            requiredCapabilities: ["coreml"],
            optimizedFor: [.appleNeuralEngine, .metalPerformanceShaders, .lowLatency],
            features: [
                .onDeviceInference,
                .customModels,
                .swiftPackageManager,
                .openSource,
                .offlineCapable
            ]
        )
    }

    override var name: String { "Swift Transformers" }
    
    // MARK: - Capabilities
    
    override var supportsStreaming: Bool { true }
    override var supportsQuantization: Bool { true }
    override var supportsBatching: Bool { true }
    override var supportsMultiModal: Bool { false }
    override var quantizationFormats: [QuantizationFormat] { [.fp16, .int8] }
    override var maxContextLength: Int { 2048 }
    override var hardwareAcceleration: [HardwareAcceleration] { [.neuralEngine, .gpu, .cpu] }
    override var supportedFormats: [ModelFormat] { [.coreML, .mlPackage] }

    override var supportedModels: [ModelInfo] {
        get {
            // Get models from the registry - no longer using bundled models
            let models = ModelURLRegistry.shared.getAllModels(for: .swiftTransformers)
            
            // Note: Bundled models are no longer used. All models should be downloaded dynamically.
            // This ensures proper model management and reduces app size.
            
            print("📱 Swift Transformers: Available models: \(models.map { $0.name })")
            
            return models
        }
        set {
            // Models are managed centrally in ModelURLRegistry
        }
    }

    // MARK: - Initialization

    override func initialize(modelPath: String) async throws {
        // Verify model exists
        guard FileManager.default.fileExists(atPath: modelPath) else {
            print("❌ Swift Transformers: Model not found at path: \(modelPath)")
            throw LLMError.modelNotFound
        }
        
        print("✅ Swift Transformers: Found model at path: \(modelPath)")

        // Swift Transformers uses Core ML models - verify using format manager
        let modelURL = URL(fileURLWithPath: modelPath)
        let format = ModelFormat.from(extension: modelURL.pathExtension)
        let formatManager = ModelFormatManager.shared
        
        // Use Swift Transformers specific handler if available
        let handler: ModelFormatHandler
        if let swiftTransformersHandler = formatManager.getHandler(for: modelURL, format: format) as? SwiftTransformersModelHandler {
            handler = swiftTransformersHandler
        } else {
            handler = formatManager.getHandler(for: modelURL, format: format)
        }
        
        guard handler.canHandle(url: modelURL, format: format) && 
              format.isSwiftTransformersSupported else {
            throw LLMError.unsupportedFormat
        }

        self.modelPath = modelPath
        
        // Find model info
        await MainActor.run {
            currentModelInfo = supportedModels.first { modelInfo in
                modelPath.contains(modelInfo.name) || modelPath.contains(modelInfo.id)
            }
        }

        do {
            print("🔍 STARTING Swift Transformers model loading: \(modelPath)")
            
            // Compile model if needed (similar to CoreMLService)
            let compiledURL: URL
            
            // Use handler to determine if model is directory-based
            if handler.isDirectoryBasedModel(url: modelURL) {
                print("🔍 Model is directory-based - checking for compiled version in app bundle")
                
                // For bundled models, check if there's a compiled version in the app bundle
                let modelNameWithoutExtension = modelURL.deletingPathExtension().lastPathComponent
                if let compiledInBundle = Bundle.main.url(forResource: modelNameWithoutExtension, withExtension: "mlmodelc") {
                    print("✅ Found compiled model in app bundle: \(compiledInBundle.path)")
                    compiledURL = compiledInBundle
                } else {
                    print("🔍 No compiled version in bundle, using directory model as is")
                    compiledURL = modelURL
                }
            } else if modelURL.pathExtension == "mlmodelc" {
                print("🔍 Model is already compiled (.mlmodelc)")
                compiledURL = modelURL
            } else if modelURL.pathExtension == "mlmodel" {
                print("🔍 Model is .mlmodel, checking for compiled version...")
                // Check if already compiled
                let compiledModelName = modelURL.lastPathComponent + "c"
                let compiledModelPath = modelURL.deletingLastPathComponent().appendingPathComponent(compiledModelName)
                
                if FileManager.default.fileExists(atPath: compiledModelPath.path) {
                    print("✅ Found existing compiled model at: \(compiledModelPath.path)")
                    compiledURL = compiledModelPath
                } else {
                    print("⏳ Compiling model for first time...")
                    compiledURL = try await MLModel.compileModel(at: modelURL)
                    print("✅ Model compiled successfully to: \(compiledURL.path)")
                }
            } else {
                print("🔍 Unknown model extension, using as is")
                compiledURL = modelURL
            }
            
            // Simple validation - let Swift Transformers handle internal validation
            print("🔍 Final compiled model path: \(compiledURL.path)")
            print("🔍 File exists check: \(FileManager.default.fileExists(atPath: compiledURL.path))")
            
            guard FileManager.default.fileExists(atPath: compiledURL.path) else {
                print("❌ Compiled model file does not exist!")
                throw LLMError.modelNotFound
            }
            
            // Configure compute units
            let computeUnits: MLComputeUnits = await isNeuralEngineAvailable() ? .all : .cpuAndGPU
            print("🔍 Compute units configured: \(computeUnits)")
            
            // Check if this is a proper Swift Transformers model
            print("🔍 Checking model compatibility...")
            
            // Swift Transformers requires models with specific metadata
            // Let's check if this model has the required structure
            do {
                let mlModel = try MLModel(contentsOf: compiledURL)
                let metadata = mlModel.modelDescription.metadata
                
                // Check for Swift Transformers required metadata
                let hasHubIdentifier = metadata.keys.contains { key in
                    String(describing: key).lowercased().contains("hub")
                }
                
                // Check input/output structure
                let inputs = mlModel.modelDescription.inputDescriptionsByName
                let outputs = mlModel.modelDescription.outputDescriptionsByName
                
                print("🔍 Model metadata keys: \(metadata.keys.map { String(describing: $0) })")
                print("🔍 Model inputs: \(Array(inputs.keys))")
                print("🔍 Model outputs: \(Array(outputs.keys))")
                
                // Swift Transformers expects specific input names
                let hasInputIds = inputs.keys.contains("input_ids")
                let hasLogits = outputs.keys.contains { $0.contains("logits") }
                
                if !hasInputIds {
                    print("❌ Model missing 'input_ids' input required by Swift Transformers")
                    throw LLMError.initializationFailed("""
                        This model is not compatible with Swift Transformers.
                        
                        The model is missing the 'input_ids' input that Swift Transformers requires.
                        This model appears to be a generic Core ML model rather than one specifically
                        converted for Swift Transformers.
                        
                        To use Swift Transformers, you need models that were converted using:
                        - The transformers-to-coreml Space on Hugging Face
                        - The exporters Python package with Swift Transformers support
                        - Models from apple/ or pcuenq/ on Hugging Face
                        
                        Recommendation: Use the Core ML service instead for this model.
                        """)
                }
                
            } catch let error as LLMError {
                throw error
            } catch {
                print("❌ Failed to validate model structure: \(error)")
            }
            
            // CRITICAL: This is where the crash happens
            print("🔍 ABOUT TO CALL LanguageModel.loadCompiled")
            print("🔍 URL: \(compiledURL)")
            print("🔍 Compute Units: \(computeUnits)")
            
            // Load using Swift Transformers
            do {
                print("🔍 Calling LanguageModel.loadCompiled...")
                languageModel = try LanguageModel.loadCompiled(url: compiledURL, computeUnits: computeUnits)
                print("✅ LanguageModel.loadCompiled succeeded!")
            } catch {
                print("❌ LanguageModel.loadCompiled threw error: \(error)")
                print("❌ Error type: \(type(of: error))")
                
                // Check if it's an array bounds exception
                let errorString = String(describing: error)
                if errorString.contains("NSRangeException") || errorString.contains("bounds") {
                    throw LLMError.initializationFailed("""
                        Model incompatible with Swift Transformers.
                        
                        This error typically occurs when the model lacks the required metadata
                        and structure for Swift Transformers. The model needs:
                        
                        1. Proper Hub identifier metadata
                        2. Tokenizer configuration embedded in the model
                        3. Specific input/output tensor names (input_ids, attention_mask, logits)
                        4. Conversion using Swift Transformers-aware tools
                        
                        Compatible models include:
                        - Models from huggingface.co/apple/
                        - Models from huggingface.co/pcuenq/
                        - Models converted with transformers-to-coreml Space
                        
                        Recommendation: Use the Core ML service for this model instead.
                        """)
                }
                
                throw LLMError.initializationFailed("Swift Transformers loading failed: \(error.localizedDescription)")
            }
            
            if let model = languageModel {
                print("✅ Swift Transformers model loaded successfully")
                print("- Model name: \(model.modelName)")
                print("- Description: \(model.description)")
                print("- Context length: \(model.minContextLength)-\(model.maxContextLength)")
            }
            
            isInitialized = true
        } catch {
            print("❌ Swift Transformers model loading failed: \(error)")
            throw LLMError.initializationFailed(error.localizedDescription)
        }
    }

    // MARK: - Generation

    override func generate(prompt: String, options: GenerationOptions) async throws -> String {
        guard isInitialized, let model = languageModel else {
            throw LLMError.notInitialized()
        }

        // Create generation config matching swift-chat pattern
        var config = model.defaultGenerationConfig
        config.maxNewTokens = options.maxTokens
        config.temperature = Double(options.temperature)
        config.topP = Double(options.topP)
        config.doSample = options.temperature > 0
        
        do {
            // Generate text with simple callback pattern from swift-chat
            let output = try await model.generate(
                config: config,
                prompt: prompt
            ) { inProgressGeneration in
                // Simple progress tracking like swift-chat
                print("Generation progress: \(inProgressGeneration.count) tokens")
            }
            
            return output
        } catch {
            print("Swift Transformers generation error: \(error)")
            throw LLMError.inferenceError("Generation failed: \(error.localizedDescription)")
        }
    }

    override func streamGenerate(
        prompt: String,
        options: GenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard isInitialized, let model = languageModel else {
            throw LLMError.notInitialized()
        }

        // Create generation config
        var config = model.defaultGenerationConfig
        config.maxNewTokens = options.maxTokens
        config.temperature = Double(options.temperature)
        config.topP = Double(options.topP)
        config.doSample = options.temperature > 0
        
        // Track previous output to emit only new tokens - simplified approach
        var previousLength = prompt.count
        
        do {
            // Generate with streaming callback matching swift-chat pattern
            _ = try await model.generate(
                config: config,
                prompt: prompt
            ) { currentGeneration in
                // Simple token extraction
                if currentGeneration.count > previousLength {
                    let newPart = String(currentGeneration.suffix(currentGeneration.count - previousLength))
                    if !newPart.isEmpty {
                        onToken(newPart)
                        previousLength = currentGeneration.count
                    }
                }
            }
        } catch {
            print("Swift Transformers stream generation error: \(error)")
            throw LLMError.inferenceError("Stream generation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Model Info

    override func getModelInfo() -> ModelInfo? {
        guard isInitialized, let model = languageModel else { return nil }
        
        // Use existing model info or create a new one
        if let info = currentModelInfo {
            return info
        }
        
        return ModelInfo(
            id: "swift-transformers-\(model.modelName)",
            name: model.modelName,
            format: .coreML,
            size: getModelSize(),
            framework: .swiftTransformers,
            quantization: "FP16",
            contextLength: model.maxContextLength
        )
    }

    override func cleanup() {
        languageModel = nil
        currentModelInfo = nil
        isInitialized = false
    }

    // MARK: - Private Methods

    private func getModelSize() -> String {
        let url = URL(fileURLWithPath: modelPath)
        let format = ModelFormat.from(extension: url.pathExtension)
        let formatManager = ModelFormatManager.shared
        let handler = formatManager.getHandler(for: url, format: format)
        
        let totalSize = handler.calculateModelSize(at: url)
        
        if totalSize > 0 {
            return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        }
        
        return "Unknown"
    }
    
    private func isNeuralEngineAvailable() async -> Bool {
        // Check if device has Neural Engine (A11 and later)
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelName = String(bytes: Data(bytes: &systemInfo.machine, count: Int(_SYS_NAMELEN)), encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? ""
        
        let neuralEngineDevices = [
            "iPhone10", "iPhone11", "iPhone12", "iPhone13", "iPhone14", "iPhone15", "iPhone16",
            "iPad8", "iPad11", "iPad12", "iPad13", "iPad14", "iPad16",
            "arm64" // M-series Macs
        ]
        
        return neuralEngineDevices.contains { modelName.contains($0) }
    }
}

// MARK: - Swift Transformers Extensions

@available(iOS 16.0, *)
extension SwiftTransformersService {
    // Batch processing support
    func generateBatch(prompts: [String], options: GenerationOptions) async throws -> [String] {
        guard isInitialized, let _ = languageModel else {
            throw LLMError.notInitialized()
        }

        // For now, process sequentially
        // Swift Transformers may add batch support in the future
        var results: [String] = []
        for prompt in prompts {
            let result = try await generate(prompt: prompt, options: options)
            results.append(result)
        }
        return results
    }
}