//
//  EmbeddingsProto+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical Embeddings proto types.
//

import Foundation

// MARK: - RAEmbeddingsConfiguration

extension RAEmbeddingsConfiguration {
    public static func defaults(
        modelId: String,
        embeddingDimension: Int32 = 384,
        maxSequenceLength: Int32 = 512,
        normalize: Bool = true
    ) -> RAEmbeddingsConfiguration {
        var c = RAEmbeddingsConfiguration()
        c.modelID = modelId
        c.embeddingDimension = embeddingDimension
        c.maxSequenceLength = maxSequenceLength
        c.normalize = normalize
        return c
    }

    public func validate() throws {
        guard !modelID.isEmpty else {
            throw SDKException.validationFailed("Embeddings modelID is empty")
        }
        guard embeddingDimension > 0 else {
            throw SDKException.validationFailed(
                "Embedding dimension must be > 0 (got \(embeddingDimension))"
            )
        }
        guard maxSequenceLength > 0 else {
            throw SDKException.validationFailed(
                "Max sequence length must be > 0 (got \(maxSequenceLength))"
            )
        }
    }
}

// MARK: - RAEmbeddingsOptions

extension RAEmbeddingsOptions {
    public static func defaults(normalize: Bool = true) -> RAEmbeddingsOptions {
        var o = RAEmbeddingsOptions()
        o.normalize = normalize
        return o
    }
}

// MARK: - RAEmbeddingVector

extension RAEmbeddingVector {
    public func cosineSimilarity(with other: RAEmbeddingVector) -> Float {
        guard values.count == other.values.count, !values.isEmpty else { return 0 }
        var dot: Float = 0
        for i in 0..<values.count { dot += values[i] * other.values[i] }
        let aNorm = hasNorm ? norm : Self.l2(values)
        let bNorm = other.hasNorm ? other.norm : Self.l2(other.values)
        guard aNorm > 0 && bNorm > 0 else { return 0 }
        return dot / (aNorm * bNorm)
    }

    public func computeNorm() -> Float { Self.l2(values) }

    private static func l2(_ values: [Float]) -> Float {
        var sumSquares: Float = 0
        for v in values { sumSquares += v * v }
        return sumSquares.squareRoot()
    }
}

// MARK: - RAEmbeddingsResult

extension RAEmbeddingsResult {
    public var processingTime: TimeInterval { TimeInterval(processingTimeMs) / 1000.0 }
}
