import Foundation
import OSLog
import RunAnywhere

// Import FoundationModels with conditional compilation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service implementation for Apple's Foundation Models
@available(iOS 26.0, macOS 26.0, *)
public class FoundationModelsService: LLMService {
    private var _currentModel: String?
    private var _isReady = false
    private let logger = Logger(
        subsystem: "com.runanywhere.FoundationModels",
        category: "FoundationModelsService"
    )

    #if canImport(FoundationModels)
    // Type-erased wrapper for FoundationModels session
    private var session: LanguageSessionWrapper?
    #endif

    // MARK: - Framework Identification

    /// Apple Foundation Models inference framework
    public let inferenceFramework: InferenceFrameworkType = .foundationModels

    public var isReady: Bool { _isReady }
    public var currentModel: String? { _currentModel }

    /// Apple Foundation Models does not support true token-by-token streaming
    public var supportsStreaming: Bool { false }

    #if canImport(FoundationModels)
    /// Type-erased wrapper for LanguageModelSession
    private struct LanguageSessionWrapper {
        let session: LanguageModelSession
    }
    #endif

    public init() {
    }

    public func initialize(modelPath: String?) async throws {
        logger.info("Initializing Apple Foundation Models (iOS 26+/macOS 26+)")

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            logger.error("iOS 26.0+ or macOS 26.0+ not available")
            throw LLMError.notInitialized
        }

        logger.info("FoundationModels framework is available, proceeding with initialization")

        do {
            try await initializeFoundationModel()
            _currentModel = "foundation-models-native"
            _isReady = true
            logger.info("Foundation Models initialized successfully")
        } catch {
            logger.error("Failed to initialize Foundation Models: \(error)")
            throw LLMError.notInitialized
        }
        #else
        // Foundation Models framework not available
        logger.error("FoundationModels framework not available")
        throw LLMError.notInitialized
        #endif
    }

    #if canImport(FoundationModels)
    /// Initializes the Foundation Model and creates session
    private func initializeFoundationModel() async throws {
        logger.info("Getting SystemLanguageModel.default...")
        let model = SystemLanguageModel.default
        logger.info("SystemLanguageModel.default obtained successfully")

        try checkModelAvailability(model)

        logger.info("Creating LanguageModelSession with instructions...")
        let instructions = """
        You are a helpful AI assistant integrated into the RunAnywhere app. \
        Provide concise, accurate responses that are appropriate for mobile users. \
        Keep responses brief but informative.
        """
        session = LanguageSessionWrapper(session: LanguageModelSession(instructions: instructions))
        logger.info("LanguageModelSession created successfully")
    }

    /// Checks if the model is available and ready to use
    private func checkModelAvailability(_ model: SystemLanguageModel) throws {
        switch model.availability {
        case .available:
            logger.info("Foundation Models is available")
        case .unavailable(.deviceNotEligible):
            logger.error("Device not eligible for Apple Intelligence")
            throw LLMError.notInitialized
        case .unavailable(.appleIntelligenceNotEnabled):
            logger.error("Apple Intelligence not enabled. Please enable it in Settings.")
            throw LLMError.notInitialized
        case .unavailable(.modelNotReady):
            logger.error("Model not ready. It may be downloading or initializing.")
            throw LLMError.notInitialized
        case .unavailable(let other):
            logger.error("Foundation Models unavailable: \(String(describing: other))")
            throw LLMError.notInitialized
        @unknown default:
            logger.error("Unknown availability status")
            throw LLMError.notInitialized
        }
    }
    #endif

    public func generate(prompt: String, options: LLMGenerationOptions) async throws -> String {
        guard isReady else {
            throw LLMError.notInitialized
        }

        logger.debug("Generating response for prompt: \(prompt.prefix(100))...")

        #if canImport(FoundationModels)
        guard let sessionWrapper = session else {
            logger.error("Session not available - was initialization successful?")
            throw LLMError.notInitialized
        }

        let sessionObj = sessionWrapper.session

        // Check if session is responding to another request
        guard !sessionObj.isResponding else {
            logger.warning("Session is already responding to another request")
            let busyUserInfo = [NSLocalizedDescriptionKey: "Session is busy with another request"]
            throw LLMError.generationFailed(NSError(domain: "FoundationModels", code: -1, userInfo: busyUserInfo))
        }

        do {
            let response = try await performGeneration(
                with: sessionObj,
                prompt: prompt,
                temperature: Double(options.temperature)
            )
            logger.debug("Generated response successfully")
            return response
        } catch let error as LanguageModelSession.GenerationError {
            try handleGenerationError(error)
            throw LLMError.generationFailed(error)
        } catch {
            logger.error("Generation failed: \(error)")
            throw LLMError.generationFailed(error)
        }
        #else
        // Foundation Models framework not available
        logger.error("FoundationModels framework not available")
        throw LLMError.notInitialized
        #endif
    }

    public func streamGenerate(
        prompt: String,
        options: LLMGenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard isReady else {
            throw LLMError.notInitialized
        }

        logger.debug("Starting streaming generation for prompt: \(prompt.prefix(100))...")

        #if canImport(FoundationModels)
        guard let sessionWrapper = session else {
            logger.error("Session not available for streaming")
            throw LLMError.notInitialized
        }

        let sessionObj = sessionWrapper.session

        // Check if session is responding to another request
        guard !sessionObj.isResponding else {
            logger.warning("Session is already responding to another request")
            let streamBusyUserInfo = [NSLocalizedDescriptionKey: "Session is busy with another request"]
            throw LLMError.generationFailed(NSError(domain: "FoundationModels", code: -1, userInfo: streamBusyUserInfo))
        }

        do {
            try await performStreamGeneration(
                with: sessionObj,
                prompt: prompt,
                temperature: Double(options.temperature),
                onToken: onToken
            )
            logger.debug("Streaming generation completed successfully")
        } catch let error as LanguageModelSession.GenerationError {
            try handleGenerationError(error)
            throw LLMError.generationFailed(error)
        } catch {
            logger.error("Streaming generation failed: \(error)")
            throw LLMError.generationFailed(error)
        }
        #else
        // Foundation Models framework not available
        logger.error("FoundationModels framework not available for streaming")
        throw LLMError.notInitialized
        #endif
    }

    #if canImport(FoundationModels)
    /// Performs text generation with the given session
    private func performGeneration(
        with session: LanguageModelSession,
        prompt: String,
        temperature: Double
    ) async throws -> String {
        let foundationOptions = GenerationOptions(temperature: temperature)
        let response = try await session.respond(to: prompt, options: foundationOptions)
        return response.content
    }

    /// Performs streaming text generation
    private func performStreamGeneration(
        with session: LanguageModelSession,
        prompt: String,
        temperature: Double,
        onToken: @escaping (String) -> Void
    ) async throws {
        let foundationOptions = GenerationOptions(temperature: temperature)
        let responseStream = session.streamResponse(to: prompt, options: foundationOptions)

        var previousContent = ""
        for try await partialResponse in responseStream {
            let currentContent = partialResponse.content
            if currentContent.count > previousContent.count {
                let newTokens = String(currentContent.dropFirst(previousContent.count))
                onToken(newTokens)
                previousContent = currentContent
            }
        }
    }

    /// Handles generation errors from FoundationModels
    private func handleGenerationError(_ error: LanguageModelSession.GenerationError) throws {
        logger.error("Foundation Models generation error: \(error)")
        switch error {
        case .exceededContextWindowSize:
            logger.error("Exceeded context window size - please reduce prompt length")
            // Foundation Models has a 4096 token context window
            // Apple's API doesn't provide the actual requested length, so use -1 to indicate unknown
            throw LLMError.contextLengthExceeded(maxLength: 4096, requestedLength: -1)
        default:
            logger.error("Other generation error: \(error)")
            throw LLMError.generationFailed(error)
        }
    }
    #endif

    public func cleanup() async {
        logger.info("Cleaning up Foundation Models")

        #if canImport(FoundationModels)
        // Clean up the session
        session = nil
        #endif

        _isReady = false
        _currentModel = nil
    }
}
