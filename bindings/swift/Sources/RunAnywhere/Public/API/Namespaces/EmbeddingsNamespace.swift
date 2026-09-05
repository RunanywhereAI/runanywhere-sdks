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

public extension RunAnywhere.Embeddings {

    /// Embed one image into a dense vector, for image/image or image/text retrieval.
    ///
    /// ```swift
    /// let vector = try await RunAnywhere.embeddings.embedImage(.cgImage(photo))
    /// ```
    ///
    /// A separate verb from `embed(_:)` rather than an overload: this reaches
    /// `RAC_PRIMITIVE_EMBED_IMAGE`, a different vtable slot served by a different model. A text
    /// embedder cannot answer it and a vision tower cannot answer `embed(_:)`, so the two are not
    /// interchangeable at run time and should not look interchangeable in the API.
    ///
    /// - Parameter image: any `ImageInput`; file and encoded sources are decoded to packed RGB.
    /// - Throws: `SDKException` when no image-embedding model is loaded, the image cannot be
    ///           decoded, or the linked RACommons predates the ABI-v10 export set.
    func embedImage(
        _ image: ImageInput
    ) async throws -> [Float] {
        let model = try await RunAnywhere.ensureLoaded(modelId: nil, category: .embedding)
        let pixels = try image.rawPixels()
        return try CppBridge.ImageEmbedding.embed(
            modelPath: model,
            pixels: pixels.data,
            width: pixels.width,
            height: pixels.height
        )
    }
}
