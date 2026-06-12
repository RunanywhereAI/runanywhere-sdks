//
//  EmbeddingsProto+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical Embeddings proto types.
//
//  defaults() / validate() factories live in
//  Generated/RAConvenience.swift, emitted by
//  idl/codegen/generate_swift_convenience.py from the rac_default /
//  rac_required / rac_min annotations in idl/embeddings_options.proto.
//

import Foundation

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
        for value in values { sumSquares += value * value }
        return sumSquares.squareRoot()
    }
}

// MARK: - RAEmbeddingsResult

extension RAEmbeddingsResult {
    public var processingTime: TimeInterval { TimeInterval(processingTimeMs) / 1000.0 }
}
