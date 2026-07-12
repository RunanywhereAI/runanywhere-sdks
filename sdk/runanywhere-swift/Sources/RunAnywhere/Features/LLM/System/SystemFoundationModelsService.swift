//
//  SystemFoundationModelsService.swift
//  RunAnywhere SDK
//
//  Service implementation for Apple's Foundation Models (Apple Intelligence).
//  Requires iOS 26+ / macOS 26+.
//


// Import FoundationModels with conditional compilation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service implementation for Apple's Foundation Models (Apple Intelligence).
///
/// This service provides LLM text generation using Apple's built-in Foundation Models.
/// It requires iOS 26+ / macOS 26+ and an Apple Intelligence capable device.
@available(iOS 26.0, macOS 26.0, *)
public actor SystemFoundationModelsService {
    private let logger = SDKLogger(category: "SystemFoundationModels")

    #if canImport(FoundationModels)
    // Type-erased wrapper for FoundationModels session. Presence of a non-nil
    // `session` is the canonical "ready" signal — the C++ lifecycle manager
    // (`rac_lifecycle_t` / `LifecycleManager`) is the single source of truth
    // for overall component readiness, so the Swift service no longer tracks
    // a duplicate `_isReady` / `_currentModel` mirror.
    private var session: LanguageSessionWrapper?

    /// Type-erased wrapper for LanguageModelSession
    private struct LanguageSessionWrapper {
        let session: LanguageModelSession
    }
    #endif

    public init() {
    }

    public func initialize(modelPath _: String?) async throws {
        logger.info("Initializing Apple Foundation Models (iOS 26+/macOS 26+)")

        if let reason = SystemFoundationModels.unavailableReason {
            logger.error("Foundation Models unavailable: \(reason)")
            throw SDKException(code: .serviceNotAvailable, message: reason, category: .component)
        }

        #if canImport(FoundationModels)
        // The enclosing @available(iOS 26.0, macOS 26.0, *) annotation on this class
        // already guarantees the platform minimum; no runtime recheck needed.
        logger.info("FoundationModels framework is available, proceeding with initialization")

        do {
            try await initializeFoundationModel()
            logger.info("Foundation Models initialized successfully")
        } catch {
            logger.error("Failed to initialize Foundation Models: \(error)")
            throw SDKException(
                code: .initializationFailed,
                message: "Failed to initialize Foundation Models",
                category: .component,
                underlying: error
            )
        }
        #else
        // Foundation Models framework not available
        logger.error("FoundationModels framework not available")
        throw SDKException(code: .frameworkNotAvailable, message: "FoundationModels framework not available", category: .component)
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
            throw SDKException(code: .hardwareUnsupported, message: "Device not eligible for Apple Intelligence", category: .component)
        case .unavailable(.appleIntelligenceNotEnabled):
            logger.error("Apple Intelligence not enabled. Please enable it in Settings.")
            throw SDKException(code: .notInitialized, message: "Apple Intelligence not enabled. Please enable it in Settings.", category: .component)
        case .unavailable(.modelNotReady):
            logger.error("Model not ready. It may be downloading or initializing.")
            throw SDKException(code: .componentNotReady, message: "Model not ready. It may be downloading or initializing.", category: .component)
        case .unavailable(let other):
            logger.error("Foundation Models unavailable: \(String(describing: other))")
            throw SDKException(
                code: .serviceNotAvailable,
                message: "Foundation Models unavailable: \(String(describing: other))",
                category: .component
            )
        @unknown default:
            logger.error("Unknown availability status")
            throw SDKException(code: .unknown, message: "Unknown Foundation Models availability status", category: .component)
        }
    }
    #endif

    public func generate(prompt: String, options: RALLMGenerationOptions) async throws -> String {
        logger.debug("Generating response for prompt: \(prompt.prefix(100))...")

        #if canImport(FoundationModels)
        guard let sessionWrapper = session else {
            logger.error("Session not available - was initialization successful?")
            throw SDKException(code: .notInitialized, message: "Session not available - was initialization successful?", category: .component)
        }

        let sessionObj = sessionWrapper.session

        // Check if session is responding to another request
        guard !sessionObj.isResponding else {
            logger.warning("Session is already responding to another request")
            throw SDKException(code: .serviceBusy, message: "Session is busy with another request", category: .component)
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
            throw SDKException(code: .generationFailed, message: "Generation failed", category: .component, underlying: error)
        } catch {
            logger.error("Generation failed: \(error)")
            throw SDKException(code: .generationFailed, message: "Generation failed", category: .component, underlying: error)
        }
        #else
        // Foundation Models framework not available
        logger.error("FoundationModels framework not available")
        throw SDKException(code: .frameworkNotAvailable, message: "FoundationModels framework not available", category: .component)
        #endif
    }

    public func streamGenerate(
        prompt: String,
        options: RALLMGenerationOptions,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        logger.debug("Starting streaming generation for prompt: \(prompt.prefix(100))...")

        #if canImport(FoundationModels)
        guard let sessionWrapper = session else {
            logger.error("Session not available for streaming")
            throw SDKException(code: .notInitialized, message: "Session not available for streaming", category: .component)
        }

        let sessionObj = sessionWrapper.session

        // Check if session is responding to another request
        guard !sessionObj.isResponding else {
            logger.warning("Session is already responding to another request")
            throw SDKException(code: .serviceBusy, message: "Session is busy with another request", category: .component)
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
            throw SDKException(code: .generationFailed, message: "Streaming generation failed", category: .component, underlying: error)
        } catch {
            logger.error("Streaming generation failed: \(error)")
            throw SDKException(code: .generationFailed, message: "Streaming generation failed", category: .component, underlying: error)
        }
        #else
        // Foundation Models framework not available
        logger.error("FoundationModels framework not available for streaming")
        throw SDKException(code: .frameworkNotAvailable, message: "FoundationModels framework not available for streaming", category: .component)
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
        onToken: @escaping @Sendable (String) -> Void
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
            throw SDKException(
                code: .contextTooLong,
                message: "Exceeded context window size (max 4096 tokens) - please reduce prompt length",
                category: .component
            )
        default:
            logger.error("Other generation error: \(error)")
            throw SDKException(code: .generationFailed, message: "Foundation Models generation error", category: .component, underlying: error)
        }
    }
    #endif

    public func cleanup() async {
        logger.info("Cleaning up Foundation Models")

        #if canImport(FoundationModels)
        // Clean up the session
        session = nil
        #endif
    }
}
