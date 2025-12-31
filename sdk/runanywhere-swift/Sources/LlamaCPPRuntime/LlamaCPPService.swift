//
//  LlamaCPPService.swift
//  LlamaCPPRuntime
//
//  LLM service implementation using runanywhere-commons LlamaCPP backend.
//  This is a thin Swift wrapper around the rac_llm_llamacpp_* C APIs.
//

import CRACommons
import Foundation
import LlamaCPPBackend
import os
import RunAnywhere

// MARK: - Memory Management Helper

/// Helper to free C memory allocated by RAC functions.
/// Uses standard free() since rac_free wraps it.
private func freeRACMemory(_ ptr: UnsafeMutableRawPointer?) {
    if let ptr = ptr {
        free(ptr)
    }
}

/// LlamaCPP-based LLM service for text generation using GGUF models.
///
/// This service wraps the runanywhere-commons C++ LlamaCPP backend,
/// providing Swift-friendly APIs for text generation with Metal acceleration.
///
/// ## Usage
///
/// ```swift
/// let service = LlamaCPPService()
/// try await service.initialize(modelPath: "/path/to/model.gguf")
///
/// // Synchronous generation
/// let result = try await service.generate(prompt: "Hello!", options: .init())
///
/// // Streaming generation
/// try await service.streamGenerate(prompt: "Tell me a story", options: .init()) { token in
///     print(token, terminator: "")
/// }
/// ```
public final class LlamaCPPService: LLMService, @unchecked Sendable {

    // MARK: - Properties

    /// Native handle to the C++ LlamaCPP service
    private var handle: rac_handle_t?

    /// Lock for thread-safe access to handle (async-safe)
    private let lock = OSAllocatedUnfairLock()

    /// Logger for this service
    private let logger = SDKLogger(category: "LlamaCPPService")

    /// Current model path
    private var _modelPath: String?

    /// Configuration used for initialization
    private var config: rac_llm_llamacpp_config_t = RAC_LLM_LLAMACPP_CONFIG_DEFAULT

    // MARK: - LLMService Protocol

    /// The inference framework (always llama.cpp)
    public var inferenceFramework: InferenceFramework { .llamaCpp }

    /// Whether the service is ready for generation
    public var isReady: Bool {
        lock.withLock {
            guard let handle = handle else { return false }
            return rac_llm_llamacpp_is_model_loaded(handle) == RAC_TRUE
        }
    }

    /// Current model identifier
    public var currentModel: String? {
        lock.withLock {
            return _modelPath
        }
    }

    /// Context length from the loaded model
    public var contextLength: Int? {
        lock.withLock {
            guard let handle = handle else { return nil }

            var jsonPtr: UnsafeMutablePointer<CChar>?
            let result = rac_llm_llamacpp_get_model_info(handle, &jsonPtr)

            guard result == RAC_SUCCESS, let json = jsonPtr else { return nil }
            defer { freeRACMemory(json) }

            // Parse JSON to extract context length
            if let data = String(cString: json).data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data),
               // swiftlint:disable:next avoid_any_type
               let dict = parsed as? [String: Any],
               let ctxLen = dict["context_length"] as? Int {
                return ctxLen
            }
            return nil
        }
    }

    /// LlamaCPP supports true streaming generation
    public var supportsStreaming: Bool { true }

    // MARK: - Initialization

    public init() {
        logger.debug("LlamaCPPService instance created")
    }

    deinit {
        lock.withLock {
            if let handle = handle {
                rac_llm_llamacpp_destroy(handle)
            }
        }
    }

    /// Initialize the service with an optional model path.
    ///
    /// - Parameter modelPath: Path to a GGUF model file. If nil, the service
    ///   is created but no model is loaded yet.
    public func initialize(modelPath: String?) async throws {
        logger.info("Initializing LlamaCPPService with model: \(modelPath ?? "none")")

        // Perform initialization under lock
        let initResult: Result<Void, Error> = lock.withLock {
            // Clean up existing handle if any
            if let existingHandle = handle {
                rac_llm_llamacpp_destroy(existingHandle)
                handle = nil
            }

            var newHandle: rac_handle_t?
            let result: rac_result_t

            if let path = modelPath {
                // Create service with model
                result = path.withCString { pathPtr in
                    rac_llm_llamacpp_create(pathPtr, &config, &newHandle)
                }
                _modelPath = path
            } else {
                // Create service without model
                result = rac_llm_llamacpp_create(nil, &config, &newHandle)
            }

            if result == RAC_SUCCESS {
                handle = newHandle
                return .success(())
            } else {
                return .failure(CommonsErrorMapping.mapCommonsError(result))
            }
        }

        // Handle result outside of lock
        switch initResult {
        case .success:
            logger.info("LlamaCPPService initialized successfully")
        case .failure(let error):
            logger.error("Failed to initialize LlamaCPPService: \(error)")
            throw error
        }
    }

    // MARK: - Generation

    /// Generate text from a prompt.
    ///
    /// - Parameters:
    ///   - prompt: The input prompt text
    ///   - options: Generation options (temperature, max tokens, etc.)
    /// - Returns: The generated text
    public func generate(prompt: String, options: LLMGenerationOptions) async throws -> String {
        logger.debug("Generate called with prompt length: \(prompt.count)")

        // Get handle under lock
        let lockedHandle = lock.withLock { handle }
        guard let handle = lockedHandle else {
            throw SDKError.llm(.serviceNotAvailable, "Service not initialized")
        }

        // Convert Swift options to C options
        var cOptions = createCOptions(from: options, prompt: prompt)

        var result = rac_llm_result_t()

        let generateResult = prompt.withCString { promptPtr in
            return rac_llm_llamacpp_generate(handle, promptPtr, &cOptions, &result)
        }

        if generateResult == RAC_SUCCESS {
            var generatedText = ""
            if let textPtr = result.text {
                generatedText = String(cString: textPtr)
                freeRACMemory(textPtr)
            }
            logger.debug("Generation complete: \(result.completion_tokens) tokens")
            return generatedText
        } else {
            let error = CommonsErrorMapping.mapCommonsError(generateResult)
            logger.error("Generation failed: \(error)")
            throw error
        }
    }

    /// Stream text generation token by token.
    ///
    /// - Parameters:
    ///   - prompt: The input prompt text
    ///   - options: Generation options
    ///   - onToken: Callback invoked for each generated token
    public func streamGenerate(
        prompt: String,
        options: LLMGenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        logger.debug("Stream generate called with prompt length: \(prompt.count)")

        // Get handle under lock
        let lockedHandle = lock.withLock { handle }
        guard let handle = lockedHandle else {
            throw SDKError.llm(.serviceNotAvailable, "Service not initialized")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Create context for callback
            let context = StreamContext(onToken: onToken, continuation: continuation)
            let contextPtr = Unmanaged.passRetained(context).toOpaque()

            // Convert Swift options to C options
            var cOptions = createCOptions(from: options, prompt: prompt)

            let streamResult = prompt.withCString { promptPtr in
                return rac_llm_llamacpp_generate_stream(
                    handle,
                    promptPtr,
                    &cOptions,
                    { token, isFinal, userData -> rac_bool_t in
                        guard let userData = userData else { return RAC_FALSE }
                        let ctx = Unmanaged<StreamContext>.fromOpaque(userData).takeUnretainedValue()

                        if let tokenPtr = token {
                            let tokenStr = String(cString: tokenPtr)
                            ctx.onToken(tokenStr)
                        }

                        if isFinal == RAC_TRUE {
                            // Release the context and resume continuation
                            _ = Unmanaged<StreamContext>.fromOpaque(userData).takeRetainedValue()
                            ctx.continuation.resume()
                        }

                        return RAC_TRUE
                    },
                    contextPtr
                )
            }

            if streamResult != RAC_SUCCESS {
                // Release context on error
                _ = Unmanaged<StreamContext>.fromOpaque(contextPtr).takeRetainedValue()
                let error = CommonsErrorMapping.mapCommonsError(streamResult)
                logger.error("Stream generation failed: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Lifecycle

    /// Cancel ongoing generation
    public func cancel() async {
        lock.withLock {
            if let handle = handle {
                rac_llm_llamacpp_cancel(handle)
                logger.debug("Generation cancelled")
            }
        }
    }

    /// Clean up resources
    public func cleanup() async {
        lock.withLock {
            if let handle = handle {
                rac_llm_llamacpp_destroy(handle)
                self.handle = nil
                logger.info("LlamaCPPService cleaned up")
            }
            _modelPath = nil
        }
    }

    // MARK: - Private Helpers

    /// Convert Swift LLMGenerationOptions to C rac_llm_options_t
    private func createCOptions(from options: LLMGenerationOptions, prompt: String) -> rac_llm_options_t {
        var cOptions = RAC_LLM_OPTIONS_DEFAULT

        cOptions.max_tokens = Int32(options.maxTokens)
        cOptions.temperature = options.temperature
        cOptions.top_p = options.topP
        cOptions.streaming_enabled = options.streamingEnabled ? RAC_TRUE : RAC_FALSE

        // Note: system_prompt and stop_sequences require pointer management
        // For now, these fields would need to be set separately with proper lifetime management
        // The pointers must remain valid for the duration of the API call

        return cOptions
    }
}

// MARK: - Stream Context

/// Context object for streaming callbacks
private final class StreamContext {
    let onToken: (String) -> Void
    let continuation: CheckedContinuation<Void, Error>

    init(onToken: @escaping (String) -> Void, continuation: CheckedContinuation<Void, Error>) {
        self.onToken = onToken
        self.continuation = continuation
    }
}
