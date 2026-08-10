//
//  EmbeddingsNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.embeddings.embed` — the v3 verb, layered on the existing
//  `RunAnywhere.Embeddings` namespace so the older model-pinned overloads keep
//  working for one release.
//

import Foundation

public extension RunAnywhere.Embeddings {

    /// Embed a batch of texts, returning vectors in input order.
    ///
    /// ```swift
    /// let vectors = try await RunAnywhere.embeddings.embed(["hello", "world"])
    /// print(vectors[0].vector.count)
    /// ```
    ///
    /// - Throws: `SDKException` when no embedding model is loaded or the batch fails.
    func embed(
        _ texts: [String],
        options: EmbedOptions? = nil
    ) async throws -> [Embedding] {
        guard !texts.isEmpty else { return [] }
        let model = try await RunAnywhere.ensureLoaded(modelId: nil, category: .embedding)

        var request = RAEmbeddingsRequest()
        request.texts = texts
        request.options = (options ?? EmbedOptions()).toProto()
        request.modelID = model

        // RAEmbeddingsResult carries no error field at all
        // (idl/embeddings_options.proto): a failed call already throws
        // inside embedBatchLifecycle via the native-ABI status check, so
        // there is nothing left to inspect on a successful return.
        let result = try CppBridge.EmbeddingsProto.embedBatchLifecycle(request)
        return result.vectors.enumerated().map { index, vector in
            Embedding(proto: vector, fallbackIndex: index)
        }
    }
}
