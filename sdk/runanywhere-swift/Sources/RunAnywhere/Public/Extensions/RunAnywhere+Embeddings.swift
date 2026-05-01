//
//  RunAnywhere+Embeddings.swift
//  RunAnywhere SDK
//
//  Public API for embedding generation (B10).
//
//  Calls the `rac_embeddings_*` C ABI directly via CRACommons. The
//  embeddings service uses its own handle (distinct from LLM/STT/etc.)
//  obtained via `rac_embeddings_create` — this file maintains a single
//  lazily-initialized shared handle per-process, keyed on model id.
//
//  The public `embed(text:options:)` method per the B10 task contract
//  does NOT take a model id. The id must be configured first via
//  `loadEmbeddingsModel(modelId:)` (mirrors how LLM/STT work on iOS).
//

import CRACommons
import Foundation

// MARK: - Shared Embeddings Handle

private actor EmbeddingsHandleStore {
    static let shared = EmbeddingsHandleStore()

    private var handle: rac_handle_t?
    private var modelId: String?

    /// Whether a model is currently loaded.
    var isLoaded: Bool { handle != nil }

    /// Currently-loaded model id, or nil.
    var currentModelId: String? { modelId }

    /// Load (or swap) the embeddings model. Destroys any existing handle.
    func load(modelId: String) throws {
        if self.modelId == modelId, handle != nil { return }
        if let existing = handle {
            rac_embeddings_destroy(existing)
            self.handle = nil
            self.modelId = nil
        }
        var newHandle: rac_handle_t?
        let rc = modelId.withCString { modelIdPtr in
            rac_embeddings_create(modelIdPtr, &newHandle)
        }
        guard rc == RAC_SUCCESS, let h = newHandle else {
            throw SDKException.make(
                code: .notInitialized,
                message: "rac_embeddings_create failed rc=\(rc) for model=\(modelId)",
                category: .component
            )
        }
        self.handle = h
        self.modelId = modelId
    }

    /// Get the currently-loaded handle, throwing if none is loaded.
    func requireHandle() throws -> rac_handle_t {
        guard let h = handle else {
            throw SDKException.make(
                code: .notInitialized,
                message: "Embeddings model not loaded; call loadEmbeddingsModel(_:) first",
                category: .component
            )
        }
        return h
    }

    /// Unload and destroy the embeddings handle.
    func unload() {
        if let existing = handle {
            rac_embeddings_destroy(existing)
        }
        handle = nil
        modelId = nil
    }
}

// MARK: - Public API

public extension RunAnywhere {

    /// Load (or swap) the embeddings model used by `embed(text:options:)`.
    ///
    /// Embeddings run through their own `rac_embeddings_*` service and
    /// must be given a model id up front — this call creates the
    /// underlying handle via `rac_embeddings_create`.
    ///
    /// - Parameter modelId: Registry id or local path of the embeddings model.
    /// - Throws: `SDKException` if the SDK is not initialized or the handle
    ///   could not be created.
    static func loadEmbeddingsModel(_ modelId: String) async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await EmbeddingsHandleStore.shared.load(modelId: modelId)
    }

    /// Unload the currently-loaded embeddings model and destroy its handle.
    static func unloadEmbeddingsModel() async {
        await EmbeddingsHandleStore.shared.unload()
    }

    /// Generate an embedding vector for a single text.
    ///
    /// Delegates to the `rac_embeddings_embed` C ABI and returns the canonical
    /// `RAEmbeddingVector` proto type. Options default to L2-normalized via
    /// `RAEmbeddingsOptions.defaults()`.
    ///
    /// A model must be loaded first via `loadEmbeddingsModel(_:)`.
    ///
    /// - Parameters:
    ///   - text: The input text to embed.
    ///   - options: Optional per-call overrides.
    /// - Returns: A single `RAEmbeddingVector`.
    /// - Throws: `SDKException` if the SDK is not initialized, no model is
    ///   loaded, or the embed call returns a non-success rc.
    static func embed(
        text: String,
        options: RAEmbeddingsOptions = .defaults()
    ) async throws -> RAEmbeddingVector {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await EmbeddingsHandleStore.shared.requireHandle()

        var cOptions = rac_embeddings_options_t(
            normalize: options.normalize ? 1 : 0,
            pooling: -1,
            n_threads: 0
        )

        var cResult = rac_embeddings_result_t(
            embeddings: nil,
            num_embeddings: 0,
            dimension: 0,
            processing_time_ms: 0,
            total_tokens: 0
        )

        let rc = text.withCString { textPtr -> rac_result_t in
            rac_embeddings_embed(handle, textPtr, &cOptions, &cResult)
        }
        guard rc == RAC_SUCCESS else {
            throw SDKException.make(
                code: .generationFailed,
                message: "rac_embeddings_embed failed rc=\(rc)",
                category: .component
            )
        }
        defer { rac_embeddings_result_free(&cResult) }

        guard cResult.num_embeddings > 0, let embeddingsPtr = cResult.embeddings else {
            throw SDKException.make(
                code: .generationFailed,
                message: "rac_embeddings_embed returned empty result",
                category: .component
            )
        }

        let first = embeddingsPtr.pointee
        var values: [Float] = []
        if let dataPtr = first.data, first.dimension > 0 {
            values = Array(UnsafeBufferPointer(start: dataPtr, count: Int(first.dimension)))
        }

        var vec = RAEmbeddingVector()
        vec.values = values
        vec.text = text
        return vec
    }
}
