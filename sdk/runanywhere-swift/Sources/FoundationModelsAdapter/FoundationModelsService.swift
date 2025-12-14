import Foundation
import RunAnywhere
import OSLog

// Import FoundationModels with conditional compilation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service implementation for Apple's Foundation Models
@available(iOS 18.0, macOS 26.0, *)
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
        logger.info("🚀 Initializing Apple Foundation Models (iOS 18+/macOS 26+)")
        
        // Log system information for debugging
        #if os(iOS)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        logger.info("Running on iOS \(osVersion)")
        #elseif os(macOS)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        logger.info("Running on macOS \(osVersion)")
        #endif

        #if canImport(FoundationModels)
        guard #available(iOS 18.0, macOS 26.0, *) else {
            let errorMsg = "iOS 18.0+ or macOS 26.0+ required. Current: \(ProcessInfo.processInfo.operatingSystemVersionString)"
            logger.error("❌ \(errorMsg)")
            throw LLMServiceError.generationFailed(NSError(domain: "FoundationModels", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
        }

        logger.info("✅ FoundationModels framework is available, proceeding with initialization")

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
                let errorMsg = "Device not eligible for Apple Intelligence. This feature requires a compatible Apple device with Apple Silicon (M1 or later) or A17 Pro or later chip."
                logger.error("\(errorMsg)")
                throw LLMServiceError.generationFailed(NSError(domain: "FoundationModels", code: -2, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
            case .unavailable(.appleIntelligenceNotEnabled):
                #if os(iOS)
                let errorMsg = """
                Apple Intelligence not enabled. Please enable it in:
                Settings > Apple Intelligence & Siri
                
                Requirements:
                • Device must be eligible (A17 Pro or later, or M1 or later)
                • System Language must be set to a supported language (English, etc.)
                • Region must be set to a supported region
                • You must be signed in with an Apple ID
                """
                #elseif os(macOS)
                let errorMsg = """
                Apple Intelligence not enabled. Please enable it in:
                System Settings > Apple Intelligence & Siri
                
                Requirements:
                • Device must be eligible (M1 or later)
                • System Language must be set to a supported language (English, etc.)
                • Region must be set to a supported region
                • You must be signed in with an Apple ID
                • Apple Intelligence must be enabled in System Settings
                
                To enable:
                1. Open System Settings
                2. Go to Apple Intelligence & Siri
                3. Enable "Apple Intelligence"
                4. Follow the setup prompts if any
                """
                #else
                let errorMsg = "Apple Intelligence not enabled. Please enable it in Settings > Apple Intelligence & Siri."
                #endif
                logger.error("❌ \(errorMsg)")
                
                // Log diagnostic information
                #if os(macOS)
                let locale = Locale.current
                logger.info("System Language: \(locale.languageCode ?? "unknown")")
                logger.info("System Region: \(locale.regionCode ?? "unknown")")
                logger.info("Locale Identifier: \(locale.identifier)")
                #endif
                
                throw LLMServiceError.generationFailed(NSError(domain: "FoundationModels", code: -3, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
            case .unavailable(.modelNotReady):
                #if os(iOS)
                let errorMsg = """
                Apple Intelligence is not enabled. Please enable it to use this model.
                
                To enable:
                1. Open Settings
                2. Go to Apple Intelligence & Siri
                3. Enable "Apple Intelligence"
                4. Follow the setup prompts if any
                
                Requirements:
                • Device must be eligible (A17 Pro or later, or M1 or later)
                • System Language must be set to a supported language (English, etc.)
                • Region must be set to a supported region
                • You must be signed in with an Apple ID
                """
                #elseif os(macOS)
                let errorMsg = """
                Apple Intelligence is not enabled. Please enable it to use this model.
                
                To enable:
                1. Open System Settings
                2. Go to Apple Intelligence & Siri
                3. Enable "Apple Intelligence"
                4. Follow the setup prompts if any
                
                Requirements:
                • Device must be eligible (M1 or later)
                • System Language must be set to a supported language (English, etc.)
                • Region must be set to a supported region
                • You must be signed in with an Apple ID
                """
                #else
                let errorMsg = "Apple Intelligence is not enabled. Please enable it in Settings > Apple Intelligence & Siri to use this model."
                #endif
                logger.error("❌ \(errorMsg)")
                throw LLMServiceError.generationFailed(NSError(domain: "FoundationModels", code: -4, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
            case .unavailable(let other):
                let errorMsg = "Foundation Models unavailable: \(String(describing: other))"
                logger.error("\(errorMsg)")
                throw LLMServiceError.generationFailed(NSError(domain: "FoundationModels", code: -5, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
            @unknown default:
                let errorMsg = "Unknown availability status"
                logger.error("\(errorMsg)")
                throw LLMServiceError.generationFailed(NSError(domain: "FoundationModels", code: -6, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
            }

            _currentModel = "foundation-models-native"
            _isReady = true
            logger.info("Foundation Models initialized successfully")
        } catch let error as LLMServiceError {
            // Re-throw LLMServiceError as-is
            logger.error("Failed to initialize Foundation Models: \(error.localizedDescription)")
            throw error
        } catch {
            let errorMsg = "Failed to initialize Foundation Models: \(error.localizedDescription)"
            logger.error("\(errorMsg)")
            throw LLMServiceError.generationFailed(NSError(domain: "FoundationModels", code: -7, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
        }
        #else
        // Foundation Models framework not available
        let errorMsg = "FoundationModels framework not available. This may be because:\n1. You're running on an unsupported OS version\n2. The framework is not linked in your project\n3. You're using a simulator that doesn't support Apple Intelligence"
        logger.error("\(errorMsg)")
        throw LLMServiceError.generationFailed(NSError(domain: "FoundationModels", code: -8, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
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
