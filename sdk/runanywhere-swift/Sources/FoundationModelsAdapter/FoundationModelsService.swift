import Foundation
import RunAnywhere
import OSLog

// Import FoundationModels with conditional compilation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service implementation for Apple's Foundation Models
@available(iOS 26.0, macOS 26.0, *)
public class FoundationModelsService: LLMService {
    private var hardwareConfig: HardwareConfiguration?
    private var _currentModel: String?
    private var _isReady = false
    private let logger = Logger(subsystem: "com.runanywhere.FoundationModels", category: "FoundationModelsService")

    #if canImport(FoundationModels)
    // The actual FoundationModels types
    private var languageModel: Any? // Will be cast to SystemLanguageModel when used
    private var session: Any? // Will be cast to LanguageModelSession when used
    #endif

    public var isReady: Bool { _isReady }
    public var currentModel: String? { _currentModel }

    public init(hardwareConfig: HardwareConfiguration?) {
        self.hardwareConfig = hardwareConfig
    }

    public func initialize(modelPath: String?) async throws {
        logger.info("Initializing Apple Foundation Models (iOS 26+/macOS 26+)")

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            logger.error("iOS 26.0+ or macOS 26.0+ not available")
            throw LLMServiceError.notInitialized
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
                throw LLMServiceError.notInitialized
            case .unavailable(.appleIntelligenceNotEnabled):
                logger.error("Apple Intelligence not enabled. Please enable it in Settings.")
                throw LLMServiceError.notInitialized
            case .unavailable(.modelNotReady):
                logger.error("Model not ready. It may be downloading or initializing.")
                throw LLMServiceError.notInitialized
            case .unavailable(let other):
                logger.error("Foundation Models unavailable: \(String(describing: other))")
                throw LLMServiceError.notInitialized
            @unknown default:
                logger.error("Unknown availability status")
                throw LLMServiceError.notInitialized
            }

            _currentModel = "foundation-models-native"
            _isReady = true
            logger.info("Foundation Models initialized successfully")
        } catch {
            logger.error("Failed to initialize Foundation Models: \(error)")
            throw LLMServiceError.notInitialized
        }
        #else
        // Foundation Models framework not available
        logger.error("FoundationModels framework not available")
        throw LLMServiceError.notInitialized
        #endif
    }

    public func generate(prompt: String, options: RunAnywhereGenerationOptions) async throws -> String {
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
                throw LLMServiceError.contextLengthExceeded
            default:
                logger.error("Other generation error: \(error)")
                throw LLMServiceError.generationFailed(error)
            }
        } catch {
            logger.error("Generation failed: \(error)")
            throw LLMServiceError.generationFailed(error)
        }
        #else
        // Foundation Models framework not available
        logger.error("FoundationModels framework not available")
        throw LLMServiceError.notInitialized
        #endif
    }

    public func streamGenerate(
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
                // partialResponse.content contains the aggregated response so far
                // We need to send only the new tokens
                let currentContent = partialResponse.content
                if currentContent.count > previousContent.count {
                    let newTokens = String(currentContent.dropFirst(previousContent.count))
                    onToken(newTokens)
                    previousContent = currentContent
                }
            }

            logger.debug("Streaming generation completed successfully")
        } catch let error as LanguageModelSession.GenerationError {
            logger.error("Foundation Models streaming error: \(error)")
            switch error {
            case .exceededContextWindowSize:
                logger.error("Exceeded context window size during streaming")
                throw LLMServiceError.contextLengthExceeded
            default:
                logger.error("Other streaming error: \(error)")
                throw LLMServiceError.generationFailed(error)
            }
        } catch {
            logger.error("Streaming generation failed: \(error)")
            throw LLMServiceError.generationFailed(error)
        }
        #else
        // Foundation Models framework not available
        logger.error("FoundationModels framework not available for streaming")
        throw LLMServiceError.notInitialized
        #endif
    }

    public func cleanup() async {
        logger.info("Cleaning up Foundation Models")

        #if canImport(FoundationModels)
        // Clean up the session
        session = nil
        languageModel = nil
        #endif

        _isReady = false
        _currentModel = nil
    }

    public func getModelMemoryUsage() async throws -> Int64 {
        return 500_000_000 // 500MB estimate for Foundation Models
    }
}
