import Foundation
import RunAnywhereSDK
import OSLog

// Import FoundationModels with conditional compilation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Adapter for Apple's native Foundation Models framework (iOS 26.0+)
/// Uses Apple's built-in language models without requiring external model files
@available(iOS 26.0, macOS 26.0, *)
public class FoundationModelsAdapter: UnifiedFrameworkAdapter {
    public var framework: LLMFramework { .foundationModels }
    public let supportedModalities: Set<FrameworkModality> = [.textToText]
    public var supportedFormats: [ModelFormat] {
        // Foundation Models doesn't use file formats - it's built-in
        [.mlmodel, .mlpackage]
    }

    private var hardwareConfig: HardwareConfiguration?
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "FoundationModels")

    public init() {}

    public func canHandle(model: ModelInfo) -> Bool {
        // Foundation Models doesn't need external model files
        // It can handle any request as it uses Apple's built-in models
        guard #available(iOS 26.0, macOS 26.0, *) else { return false }

        // Check if the model name indicates it's for Foundation Models
        return model.name.lowercased().contains("foundation") ||
               model.name.lowercased().contains("apple") ||
               model.id == "foundation-models-default"
    }

    public func createService() -> LLMService {
        return FoundationModelsService(hardwareConfig: hardwareConfig)
    }

    public func createService(for modality: FrameworkModality) -> Any? {
        guard modality == .textToText else { return nil }
        return FoundationModelsService(hardwareConfig: hardwareConfig)
    }

    public func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any {
        guard modality == .textToText else {
            throw LLMServiceError.modelNotLoaded
        }
        // Foundation Models doesn't need to load external models
        // It uses Apple's built-in models
        let service = FoundationModelsService(hardwareConfig: hardwareConfig)
        try await service.initialize(modelPath: "built-in")
        return service
    }

    public func loadModel(_ model: ModelInfo) async throws -> LLMService {
        // Foundation Models doesn't need to load external models
        // It uses Apple's built-in models
        let service = FoundationModelsService(hardwareConfig: hardwareConfig)
        try await service.initialize(modelPath: "built-in")
        return service
    }

    public func configure(with hardware: HardwareConfiguration) async {
        self.hardwareConfig = hardware
    }

    public func estimateMemoryUsage(for model: ModelInfo) -> Int64 {
        // Foundation Models memory is managed by the system
        // Estimate based on typical usage
        return 500_000_000 // 500MB typical for system models
    }

    public func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration {
        return HardwareConfiguration(
            primaryAccelerator: .neuralEngine,
            fallbackAccelerator: .gpu,
            memoryMode: .balanced,
            threadCount: 2,
            useQuantization: true,
            quantizationBits: 8
        )
    }
}

/// Service implementation for Apple's Foundation Models
@available(iOS 26.0, macOS 26.0, *)
class FoundationModelsService: LLMService {
    private var hardwareConfig: HardwareConfiguration?
    private var _modelInfo: LoadedModelInfo?
    private var _isReady = false
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "FoundationModels")

    #if canImport(FoundationModels)
    // The actual FoundationModels types
    private var languageModel: Any? // Will be cast to SystemLanguageModel when used
    private var session: Any? // Will be cast to LanguageModelSession when used
    #endif

    var isReady: Bool { _isReady }
    var modelInfo: LoadedModelInfo? { _modelInfo }

    init(hardwareConfig: HardwareConfiguration?) {
        self.hardwareConfig = hardwareConfig
    }

    func initialize(modelPath: String) async throws {
        logger.info("Initializing Apple Foundation Models (iOS 26+/macOS 26+)")

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            logger.error("iOS 26.0+ or macOS 26.0+ not available")
            throw LLMServiceError.modelNotLoaded
        }

        logger.info("FoundationModels framework is available, proceeding with initialization")

        do {
            // Create the system language model using the default property
            logger.info("Getting SystemLanguageModel.default...")
            let model = SystemLanguageModel.default
            languageModel = model
            logger.info("SystemLanguageModel.default obtained successfully")

            // Check availability status
            switch model.availability {
            case .available:
                logger.info("Foundation Models is available")

                // Create session with instructions as per Apple documentation
                logger.info("Creating LanguageModelSession with instructions...")
                let instructions = """
                You are a helpful AI assistant integrated into the RunAnywhere app. \
                Provide concise, accurate responses that are appropriate for mobile users. \
                Keep responses brief but informative.
                """
                session = LanguageModelSession(instructions: instructions)
                logger.info("LanguageModelSession created successfully")

            case .unavailable(.deviceNotEligible):
                logger.error("Device not eligible for Apple Intelligence")
                throw LLMServiceError.modelNotLoaded
            case .unavailable(.appleIntelligenceNotEnabled):
                logger.error("Apple Intelligence not enabled. Please enable it in Settings.")
                throw LLMServiceError.modelNotLoaded
            case .unavailable(.modelNotReady):
                logger.error("Model not ready. It may be downloading or initializing.")
                throw LLMServiceError.modelNotLoaded
            case .unavailable(let other):
                logger.error("Foundation Models unavailable: \(String(describing: other))")
                throw LLMServiceError.modelNotLoaded
            @unknown default:
                logger.error("Unknown availability status")
                throw LLMServiceError.modelNotLoaded
            }

            _modelInfo = LoadedModelInfo(
                id: "foundation-models-native",
                name: "Apple Foundation Model",
                framework: .foundationModels,
                format: .mlmodel,
                memoryUsage: 500_000_000, // 500MB estimate
                contextLength: 4096, // 4096 tokens as per documentation
                configuration: hardwareConfig ?? HardwareConfiguration()
            )
            _isReady = true
            logger.info("Foundation Models initialized successfully")
        } catch {
            logger.error("Failed to initialize Foundation Models: \(error)")
            throw LLMServiceError.modelNotLoaded
        }
        #else
        // Foundation Models framework not available
        logger.error("FoundationModels framework not available")
        throw LLMServiceError.modelNotLoaded
        #endif
    }

    func generate(prompt: String, options: RunAnywhereGenerationOptions) async throws -> String {
        guard isReady else {
            throw LLMServiceError.notInitialized
        }

        logger.debug("Generating response for prompt: \(prompt.prefix(100))...")

        #if canImport(FoundationModels)
        guard let sessionObj = session as? LanguageModelSession else {
            logger.error("Session not available - was initialization successful?")
            throw LLMServiceError.notInitialized
        }

        do {
            // Check if session is responding to another request
            if sessionObj.isResponding {
                logger.warning("Session is already responding to another request")
                throw LLMServiceError.notInitialized
            }

            // Create GenerationOptions for Foundation Models
            let foundationOptions = GenerationOptions(temperature: Double(options.temperature))

            // Use respond(to:options:) method as per documentation
            let response = try await sessionObj.respond(to: prompt, options: foundationOptions)

            logger.debug("Generated response successfully")
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            logger.error("Foundation Models generation error: \(error)")
            switch error {
            case .exceededContextWindowSize:
                logger.error("Exceeded context window size - please reduce prompt length")
                throw LLMServiceError.notInitialized
            default:
                logger.error("Other generation error: \(error)")
                throw LLMServiceError.notInitialized
            }
        } catch {
            logger.error("Generation failed: \(error)")
            throw LLMServiceError.notInitialized
        }
        #else
        // Foundation Models framework not available
        logger.error("FoundationModels framework not available")
        throw LLMServiceError.notInitialized
        #endif
    }

    func streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard isReady else {
            throw LLMServiceError.notInitialized
        }

        logger.debug("Starting streaming generation for prompt: \(prompt.prefix(100))...")

        #if canImport(FoundationModels)
        guard let sessionObj = session as? LanguageModelSession else {
            logger.error("Session not available for streaming")
            throw LLMServiceError.notInitialized
        }

        do {
            // Check if session is responding to another request
            if sessionObj.isResponding {
                logger.warning("Session is already responding to another request")
                throw LLMServiceError.notInitialized
            }

            // Create GenerationOptions for Foundation Models
            let foundationOptions = GenerationOptions(temperature: Double(options.temperature))

            // Use native streaming with streamResponse(to:options:)
            let responseStream = sessionObj.streamResponse(to: prompt, options: foundationOptions)

            // Stream tokens as they arrive
            var previousContent = ""
            for try await partialResponse in responseStream {
                // partialResponse contains the aggregated response so far
                // We need to send only the new tokens
                if partialResponse.count > previousContent.count {
                    let newTokens = String(partialResponse.dropFirst(previousContent.count))
                    onToken(newTokens)
                    previousContent = partialResponse
                }
            }

            logger.debug("Streaming generation completed successfully")
        } catch let error as LanguageModelSession.GenerationError {
            logger.error("Foundation Models streaming error: \(error)")
            switch error {
            case .exceededContextWindowSize:
                logger.error("Exceeded context window size during streaming")
                throw LLMServiceError.notInitialized
            default:
                logger.error("Other streaming error: \(error)")
                throw LLMServiceError.notInitialized
            }
        } catch {
            logger.error("Streaming generation failed: \(error)")
            throw LLMServiceError.notInitialized
        }
        #else
        // Foundation Models framework not available
        logger.error("FoundationModels framework not available for streaming")
        throw LLMServiceError.notInitialized
        #endif
    }

    func cleanup() async {
        logger.info("Cleaning up Foundation Models")

        #if canImport(FoundationModels)
        // Clean up the session
        session = nil
        languageModel = nil
        #endif

        _isReady = false
        _modelInfo = nil
    }

    func getModelMemoryUsage() async throws -> Int64 {
        return _modelInfo?.memoryUsage ?? 0
    }
}
