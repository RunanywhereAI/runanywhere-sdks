// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation
import CRACommonsCore

/// Direct LLM text-generation session. Wraps ra_llm_* C ABI with an
/// AsyncThrowingStream<Token, Error>. For the full voice-agent pipeline
/// use `VoiceSession` instead.
///
///     let session = try LLMSession(modelId: "qwen3-4b", modelPath: path)
///     for try await token in session.generate(prompt: "Hello") {
///         print(token.text, terminator: "")
///     }
public final class LLMSession: @unchecked Sendable {

    public struct Token: Sendable {
        public let text: String
        public let kind: Kind
        public let isFinal: Bool

        public enum Kind: Sendable {
            case answer, thought, toolCall

            internal init(raw: Int32) {
                switch raw {
                case 2:  self = .thought
                case 3:  self = .toolCall
                default: self = .answer
                }
            }
        }
    }

    public struct Config: Sendable {
        public var contextSize: Int
        public var numGpuLayers: Int
        public var numThreads: Int
        public var useMmap: Bool
        public var useMlock: Bool

        public init(contextSize: Int = 0, numGpuLayers: Int = -1,
                    numThreads: Int = 0, useMmap: Bool = true,
                    useMlock: Bool = false) {
            self.contextSize = contextSize
            self.numGpuLayers = numGpuLayers
            self.numThreads = numThreads
            self.useMmap = useMmap
            self.useMlock = useMlock
        }
    }

    private var handle: OpaquePointer?
    private var continuation: AsyncThrowingStream<Token, Error>.Continuation?

    // Keep strings alive for the C call duration.
    /// Loaded model identifier. Exposed publicly so hosts can query
    /// `RunAnywhere.isModelLoaded` / `getCurrentModelId()`.
    public let modelId: String
    private let modelPath: String

    public init(modelId: String, modelPath: String, config: Config = .init()) throws {
        self.modelId = modelId
        self.modelPath = modelPath

        var out: OpaquePointer?
        let status: Int32 = modelId.withCString { idPtr in
            modelPath.withCString { pathPtr in
                var spec = ra_model_spec_t()
                spec.model_id = idPtr
                spec.model_path = pathPtr
                spec.format = ra_model_format_t(RA_FORMAT_GGUF)
                spec.preferred_runtime = ra_runtime_id_t(RA_RUNTIME_SELF_CONTAINED)

                var cfg = ra_session_config_t()
                cfg.context_size = Int32(config.contextSize)
                cfg.n_gpu_layers = Int32(config.numGpuLayers)
                cfg.n_threads = Int32(config.numThreads)
                cfg.use_mmap = config.useMmap ? 1 : 0
                cfg.use_mlock = config.useMlock ? 1 : 0

                return ra_llm_create(&spec, &cfg, &out)
            }
        }
        guard status == Int32(RA_OK), let h = out else {
            throw RunAnywhereError.mapStatus(status, message: "ra_llm_create failed")
        }
        self.handle = h
    }

    deinit {
        if let h = handle { ra_llm_destroy(h) }
    }

    /// Streams tokens for a stateless prompt. Cancel by dropping the iterator
    /// or calling `cancel()`.
    public func generate(prompt: String, conversationId: Int32 = -1)
        -> AsyncThrowingStream<Token, Error>
    {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in self?.cancel() }

            guard let handle = self.handle else {
                continuation.finish(throwing:
                    RunAnywhereError.internalError("session not initialized"))
                return
            }

            let ctx = Unmanaged.passUnretained(self).toOpaque()
            let status: Int32 = prompt.withCString { promptPtr in
                var p = ra_prompt_t()
                p.text = promptPtr
                p.conversation_id = conversationId
                return ra_llm_generate(handle, &p,
                    { tokenPtr, userData in
                        guard let userData, let tokenPtr else { return }
                        let s = Unmanaged<LLMSession>.fromOpaque(userData)
                            .takeUnretainedValue()
                        let t = tokenPtr.pointee
                        let text = t.text.map { String(cString: $0) } ?? ""
                        let isFinal = t.is_final != 0
                        s.continuation?.yield(Token(
                            text: text,
                            kind: Token.Kind(raw: t.token_kind),
                            isFinal: isFinal))
                        if isFinal { s.continuation?.finish() }
                    },
                    { code, message, userData in
                        guard let userData else { return }
                        let s = Unmanaged<LLMSession>.fromOpaque(userData)
                            .takeUnretainedValue()
                        let msg = message.map { String(cString: $0) } ?? ""
                        s.continuation?.finish(throwing:
                            RunAnywhereError.mapStatus(code, message: msg))
                    },
                    ctx)
            }

            if status != Int32(RA_OK) {
                continuation.finish(throwing:
                    RunAnywhereError.mapStatus(status, message: "ra_llm_generate"))
            }
        }
    }

    /// Cancel in-flight generation. The token callback will fire once more
    /// with is_final=true.
    public func cancel() {
        if let h = handle { _ = ra_llm_cancel(h) }
    }

    /// Clear KV cache — equivalent to starting a fresh conversation.
    public func reset() throws {
        guard let h = handle else { return }
        let status = ra_llm_reset(h)
        if status != Int32(RA_OK) {
            throw RunAnywhereError.mapStatus(status, message: "ra_llm_reset")
        }
    }

    // MARK: - Persistent-context API (optional; engine-dependent)

    /// Inject a persistent system prompt into the KV cache. Avoids
    /// re-prefilling on every generate call. Returns RA_ERR_CAPABILITY_UNSUPPORTED
    /// if the engine does not implement this capability.
    public func injectSystemPrompt(_ prompt: String) throws {
        guard let h = handle else { return }
        let status = prompt.withCString { ra_llm_inject_system_prompt(h, $0) }
        if status != Int32(RA_OK) {
            throw RunAnywhereError.mapStatus(status,
                message: "ra_llm_inject_system_prompt")
        }
    }

    /// Append tool output, retrieval hit, or any context to the KV cache
    /// without clearing prior state.
    public func appendContext(_ text: String) throws {
        guard let h = handle else { return }
        let status = text.withCString { ra_llm_append_context(h, $0) }
        if status != Int32(RA_OK) {
            throw RunAnywhereError.mapStatus(status,
                message: "ra_llm_append_context")
        }
    }

    /// Generate from accumulated KV-cache state. Use after injectSystemPrompt
    /// / appendContext — differs from `generate()` in that the cache is not
    /// cleared first.
    public func generateFromContext(query: String)
        -> AsyncThrowingStream<Token, Error>
    {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in self?.cancel() }

            guard let handle = self.handle else {
                continuation.finish(throwing:
                    RunAnywhereError.internalError("session not initialized"))
                return
            }

            let ctx = Unmanaged.passUnretained(self).toOpaque()
            let status = query.withCString { queryPtr in
                ra_llm_generate_from_context(handle, queryPtr,
                    { tokenPtr, userData in
                        guard let userData, let tokenPtr else { return }
                        let s = Unmanaged<LLMSession>.fromOpaque(userData)
                            .takeUnretainedValue()
                        let t = tokenPtr.pointee
                        let text = t.text.map { String(cString: $0) } ?? ""
                        let isFinal = t.is_final != 0
                        s.continuation?.yield(Token(
                            text: text,
                            kind: Token.Kind(raw: t.token_kind),
                            isFinal: isFinal))
                        if isFinal { s.continuation?.finish() }
                    },
                    { code, message, userData in
                        guard let userData else { return }
                        let s = Unmanaged<LLMSession>.fromOpaque(userData)
                            .takeUnretainedValue()
                        let msg = message.map { String(cString: $0) } ?? ""
                        s.continuation?.finish(throwing:
                            RunAnywhereError.mapStatus(code, message: msg))
                    },
                    ctx)
            }
            if status != Int32(RA_OK) {
                continuation.finish(throwing:
                    RunAnywhereError.mapStatus(status,
                        message: "ra_llm_generate_from_context"))
            }
        }
    }

    public func clearContext() throws {
        guard let h = handle else { return }
        let status = ra_llm_clear_context(h)
        if status != Int32(RA_OK) {
            throw RunAnywhereError.mapStatus(status,
                message: "ra_llm_clear_context")
        }
    }
}

extension RunAnywhereError {
    internal static func mapStatus(_ status: Int32, message: String) -> RunAnywhereError {
        switch status {
        case Int32(RA_ERR_BACKEND_UNAVAILABLE):
            return .backendUnavailable(message)
        case Int32(RA_ERR_MODEL_NOT_FOUND), Int32(RA_ERR_MODEL_LOAD_FAILED):
            return .modelNotFound(message)
        case Int32(RA_ERR_CANCELLED):
            return .cancelled
        case Int32(RA_ERR_ABI_MISMATCH):
            return .abiMismatch(expected: 0, got: 0)
        default:
            return .internalError("\(message) (status \(status))")
        }
    }
}
