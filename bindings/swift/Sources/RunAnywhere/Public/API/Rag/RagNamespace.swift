//
//  RagNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.rag` — one `open` call replaces the fifteen flat `rag*` verbs.
//

import Foundation

public extension RunAnywhere {

    /// Retrieval-augmented generation.
    static var rag: Rag { Rag() }

    /// Open a corpus you can ingest into and query.
    struct Rag: Sendable {

        /// Open a RAG session, loading the models it needs first.
        ///
        /// ```swift
        /// let session = try await RunAnywhere.rag.open(embeddingModel: "minilm", llmModel: "qwen")
        /// try await session.ingest(document: RagDocument(text: notes))
        /// ```
        ///
        /// - Parameter llmModel: `nil` opens a retrieval-only session.
        /// - Throws: `SDKException` when a model cannot be loaded or the native
        ///   index cannot be created.
        public func open(
            embeddingModel: ModelRef,
            llmModel: ModelRef? = nil,
            config: RagConfig? = nil
        ) async throws -> RagSession {
            guard RunAnywhere.isReady else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            try await RunAnywhere.ensureServicesReady()

            let embeddingId = try await RunAnywhere.ensureLoaded(
                modelId: embeddingModel.id,
                category: .embedding
            )
            var llmId = ""
            if let llmModel {
                llmId = try await RunAnywhere.ensureLoaded(
                    modelId: llmModel.id,
                    category: .language
                )
            }

            let effective = config ?? RagConfig()
            var proto = effective.toProto()
            proto.embeddingModelID = embeddingId
            proto.llmModelID = llmId

            let handle = try CppBridge.RAG.shared.createPipeline(proto)
            return RagSession(handle: handle, llmModelId: llmId, defaultTopK: effective.topK)
        }
    }
}
