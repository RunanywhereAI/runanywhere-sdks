//
//  RunAnywhere+Embeddings.swift
//  RunAnywhere SDK
//
//  Public Embeddings facade — namespaced under `RunAnywhere.embeddings.*`
//  per the canonical cross-SDK spec. Mirrors the Flutter
//  `RunAnywhereEmbeddings` API so embedding generation is reachable from
//  every SDK against the same commons embedding lifecycle.
//
//  Lifecycle (load / current / unload) delegates to the commons model
//  lifecycle service via `RunAnywhere.loadModel` /
//  `RunAnywhere.unloadModel`. Embedding calls dispatch through the
//  lifecycle-aware ABI symbol `rac_embeddings_embed_batch_lifecycle_proto`
//  (exposed via `CppBridge.EmbeddingsProto.embedBatchLifecycle`).
//

import Foundation

public extension RunAnywhere {

    /// Capability accessor for Embeddings.
    static var embeddings: Embeddings { Embeddings() }

    /// Stateless namespace exposing the canonical Embeddings surface.
    /// Backed by the commons C ABI through `CppBridge.EmbeddingsProto` and
    /// `CppBridge.ModelLifecycle`.
    struct Embeddings: Sendable {

        // MARK: - Lifecycle introspection

        /// True when commons lifecycle has a ready embeddings model.
        public var isLoaded: Bool {
            guard let snapshot = lifecycleSnapshot else { return false }
            return snapshot.state == .ready && !snapshot.modelID.isEmpty
        }

        /// Currently-loaded embeddings model id, or nil.
        public var currentModelID: String? {
            guard let snapshot = lifecycleSnapshot,
                  snapshot.state == .ready,
                  !snapshot.modelID.isEmpty else {
                return nil
            }
            return snapshot.modelID
        }

        // MARK: - Embed

        /// Generate an embedding vector for a single text.
        ///
        /// Loads the requested embedding model into the commons lifecycle if
        /// it is not already loaded, then issues a single-text embed call
        /// through the lifecycle-aware proto ABI.
        public func embed(
            _ text: String,
            modelID: String,
            options: RAEmbeddingsOptions? = nil
        ) async throws -> RAEmbeddingsResult {
            var request = RAEmbeddingsRequest()
            request.texts = [text]
            if let options {
                request.options = options
            }
            return try await embedBatch(request, modelID: modelID)
        }

        /// Generate embeddings for a batch of texts.
        ///
        /// The request's `modelID` is honoured when set; otherwise the
        /// supplied `modelID` argument is used.
        @discardableResult
        public func embedBatch(
            _ request: RAEmbeddingsRequest,
            modelID: String
        ) async throws -> RAEmbeddingsResult {
            guard RunAnywhere.isInitialized else {
                throw SDKException(
                    code: .notInitialized,
                    message: "SDK not initialized",
                    category: .internal
                )
            }
            try await ensureLoaded(modelID: modelID)

            var lifecycleRequest = request
            if !lifecycleRequest.modelID.isEmpty, lifecycleRequest.modelID != modelID {
                throw SDKException(
                    code: .invalidInput,
                    message: "EmbeddingsRequest.model_id does not match requested modelID",
                    category: .internal
                )
            }
            lifecycleRequest.modelID = modelID

            return try CppBridge.EmbeddingsProto.embedBatchLifecycle(lifecycleRequest)
        }

        // MARK: - Unload

        /// Unload the currently-loaded embeddings model. No-op if none.
        public func unload() async throws {
            guard RunAnywhere.isInitialized else {
                throw SDKException(
                    code: .notInitialized,
                    message: "SDK not initialized",
                    category: .internal
                )
            }

            let modelID: String
            if let cached = currentModelID {
                modelID = cached
            } else {
                var request = RACurrentModelRequest()
                request.category = .embedding
                let current = RunAnywhere.currentModel(request)
                modelID = current.modelID
            }
            guard !modelID.isEmpty else { return }

            var unloadRequest = RAModelUnloadRequest()
            unloadRequest.modelID = modelID
            unloadRequest.category = .embedding
            let result = await RunAnywhere.unloadModel(unloadRequest)
            if !result.success {
                let message = result.errorMessage.isEmpty
                    ? "Embeddings lifecycle unload failed"
                    : result.errorMessage
                throw SDKException(
                    code: .processingFailed,
                    message: message,
                    category: .internal
                )
            }
        }

        // MARK: - Private

        private func ensureLoaded(modelID: String) async throws {
            if currentModelID == modelID { return }

            var currentRequest = RACurrentModelRequest()
            currentRequest.category = .embedding
            let current = RunAnywhere.currentModel(currentRequest)
            if current.found, current.modelID == modelID { return }

            var loadRequest = RAModelLoadRequest()
            loadRequest.modelID = modelID
            loadRequest.category = .embedding
            loadRequest.forceReload = true
            loadRequest.validateAvailability = true
            let result = await RunAnywhere.loadModel(loadRequest)
            if !result.success {
                let message = result.errorMessage.isEmpty
                    ? "Embeddings lifecycle load failed"
                    : result.errorMessage
                throw SDKException(
                    code: .modelLoadFailed,
                    message: message,
                    category: .internal
                )
            }
        }

        private var lifecycleSnapshot: RAComponentLifecycleSnapshot? {
            RunAnywhere.componentLifecycleSnapshot(.embeddings)
        }
    }
}
