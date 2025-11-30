import Foundation
import RunAnywhere
import CRunAnywhereCore  // C bridge for unified RunAnywhereCore xcframework

/// Error types for LlamaCPP operations
public enum LlamaCPPError: Error, LocalizedError {
    case initializationFailed
    case modelLoadFailed(String)
    case generationFailed(String)
    case invalidHandle
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize LlamaCPP backend"
        case .modelLoadFailed(let path):
            return "Failed to load model: \(path)"
        case .generationFailed(let message):
            return "Text generation failed: \(message)"
        case .invalidHandle:
            return "Invalid backend handle"
        case .cancelled:
            return "Operation was cancelled"
        }
    }

    static func from(code: Int32) -> LlamaCPPError {
        switch ra_result_code(rawValue: code) {
        case RA_ERROR_INIT_FAILED:
            return .initializationFailed
        case RA_ERROR_MODEL_LOAD_FAILED:
            return .modelLoadFailed("Unknown")
        case RA_ERROR_INFERENCE_FAILED:
            return .generationFailed("Inference failed")
        case RA_ERROR_INVALID_HANDLE:
            return .invalidHandle
        case RA_ERROR_CANCELLED:
            return .cancelled
        default:
            return .generationFailed("Unknown error: \(code)")
        }
    }
}

/// Text generation configuration
public struct LlamaCPPGenerationConfig {
    public var maxTokens: Int
    public var temperature: Float
    public var systemPrompt: String?

    public init(
        maxTokens: Int = 256,
        temperature: Float = 0.8,  // Match LLM.swift default
        systemPrompt: String? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.systemPrompt = systemPrompt
    }
}

/// LlamaCPP implementation for text generation using GGUF models
public class LlamaCPPService {
    private let logger = SDKLogger(category: "LlamaCPPService")

    private var backendHandle: ra_backend_handle?
    private var _isReady: Bool = false
    private var _currentModel: String?

    // MARK: - Properties

    public var isReady: Bool {
        return _isReady && backendHandle != nil
    }

    public var currentModel: String? {
        return _currentModel
    }

    /// Whether a model is currently loaded
    public var isModelLoaded: Bool {
        guard let backend = backendHandle else { return false }
        return ra_text_is_model_loaded(backend)
    }

    // MARK: - Lifecycle

    public init() {
        logger.info("LlamaCPPService initialized")
    }

    deinit {
        if let backend = backendHandle {
            ra_destroy(backend)
        }
        logger.info("LlamaCPPService deallocated")
    }

    /// Initialize the LlamaCPP backend
    /// - Parameter modelPath: Optional path to a GGUF model file
    public func initialize(modelPath: String? = nil) async throws {
        logger.info("Initializing LlamaCPP Runtime with model: \(modelPath ?? "none")")

        // Create LlamaCPP backend
        backendHandle = ra_create_backend("llamacpp")
        guard backendHandle != nil else {
            logger.error("Failed to create LlamaCPP backend")
            throw LlamaCPPError.initializationFailed
        }

        // Initialize backend
        let initStatus = ra_initialize(backendHandle, nil)
        guard initStatus == RA_SUCCESS else {
            logger.error("Failed to initialize LlamaCPP backend: \(initStatus.rawValue)")
            ra_destroy(backendHandle)
            backendHandle = nil
            throw LlamaCPPError.from(code: Int32(initStatus.rawValue))
        }

        // Load model if path provided
        if let modelPath = modelPath {
            try await loadModel(path: modelPath)
        }

        _isReady = true
        logger.info("LlamaCPP Runtime initialized successfully")
    }

    /// Load a GGUF model
    /// - Parameter path: Path to the GGUF model file
    /// - Parameter config: Optional JSON configuration
    public func loadModel(path: String, config: String? = nil) async throws {
        guard let backend = backendHandle else {
            throw LlamaCPPError.invalidHandle
        }

        logger.info("Loading model: \(path)")

        let status = ra_text_load_model(backend, path, config)
        guard status == RA_SUCCESS else {
            logger.error("Failed to load model: \(status.rawValue)")
            throw LlamaCPPError.modelLoadFailed(path)
        }

        _currentModel = path
        logger.info("Model loaded successfully")
    }

    /// Unload the current model
    public func unloadModel() async throws {
        guard let backend = backendHandle else {
            throw LlamaCPPError.invalidHandle
        }

        logger.info("Unloading model")
        _ = ra_text_unload_model(backend)
        _currentModel = nil
    }

    // MARK: - Text Generation

    /// Generate text completion
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - config: Generation configuration
    /// - Returns: Generated text
    public func generate(
        prompt: String,
        config: LlamaCPPGenerationConfig = LlamaCPPGenerationConfig()
    ) async throws -> String {
        guard isReady, let backend = backendHandle else {
            throw LlamaCPPError.invalidHandle
        }

        guard isModelLoaded else {
            throw LlamaCPPError.generationFailed("No model loaded")
        }

        logger.info("Generating text for prompt: \(prompt.prefix(50))...")

        var resultPtr: UnsafeMutablePointer<CChar>?

        let status = ra_text_generate(
            backend,
            prompt,
            config.systemPrompt,
            Int32(config.maxTokens),
            config.temperature,
            &resultPtr
        )

        guard status == RA_SUCCESS, let resultPtr = resultPtr else {
            let errorMsg = String(cString: ra_get_last_error())
            logger.error("Generation failed: \(errorMsg)")
            throw LlamaCPPError.generationFailed(errorMsg)
        }

        let result = String(cString: resultPtr)
        ra_free_string(resultPtr)

        logger.info("Generated \(result.count) characters")
        return result
    }

    /// Generate text with streaming output
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - config: Generation configuration
    /// - Returns: AsyncStream of generated tokens
    public func generateStream(
        prompt: String,
        config: LlamaCPPGenerationConfig = LlamaCPPGenerationConfig()
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard self.isReady, let backend = self.backendHandle else {
                    continuation.finish(throwing: LlamaCPPError.invalidHandle)
                    return
                }

                guard self.isModelLoaded else {
                    continuation.finish(throwing: LlamaCPPError.generationFailed("No model loaded"))
                    return
                }

                self.logger.info("Starting streaming generation for prompt: \(prompt.prefix(50))...")

                // Create a wrapper class to pass to the C callback
                class CallbackContext {
                    let continuation: AsyncThrowingStream<String, Error>.Continuation
                    var isCancelled = false

                    init(continuation: AsyncThrowingStream<String, Error>.Continuation) {
                        self.continuation = continuation
                    }
                }

                let context = CallbackContext(continuation: continuation)
                let contextPtr = Unmanaged.passRetained(context).toOpaque()

                let callback: ra_text_stream_callback = { tokenCStr, userData in
                    guard let userData = userData else { return false }
                    let context = Unmanaged<CallbackContext>.fromOpaque(userData).takeUnretainedValue()

                    if context.isCancelled {
                        return false
                    }

                    if let tokenCStr = tokenCStr {
                        let token = String(cString: tokenCStr)
                        context.continuation.yield(token)
                    }
                    return true
                }

                let status = ra_text_generate_stream(
                    backend,
                    prompt,
                    config.systemPrompt,
                    Int32(config.maxTokens),
                    config.temperature,
                    callback,
                    contextPtr
                )

                // Release the context
                Unmanaged<CallbackContext>.fromOpaque(contextPtr).release()

                if status == RA_SUCCESS || status == RA_ERROR_CANCELLED {
                    continuation.finish()
                } else {
                    let errorMsg = String(cString: ra_get_last_error())
                    continuation.finish(throwing: LlamaCPPError.generationFailed(errorMsg))
                }
            }
        }
    }

    /// Cancel ongoing generation
    public func cancel() {
        guard let backend = backendHandle else { return }
        ra_text_cancel(backend)
        logger.info("Generation cancelled")
    }

    // MARK: - Model Info

    /// Get information about the loaded model
    /// - Returns: JSON string with model information
    public func getModelInfo() -> String? {
        guard let backend = backendHandle else { return nil }
        guard let infoPtr = ra_get_backend_info(backend) else { return nil }
        let info = String(cString: infoPtr)
        ra_free_string(infoPtr)
        return info
    }
}
