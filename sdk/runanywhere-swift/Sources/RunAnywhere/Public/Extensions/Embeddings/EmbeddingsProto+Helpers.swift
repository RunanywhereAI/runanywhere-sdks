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
//  Vector math (L2 norm / cosine similarity) is owned by commons
//  (`rac_embeddings_norm` / `rac_embeddings_similarity`) via CRACommons.
//

import CRACommons
import Foundation

// MARK: - RAEmbeddingVector

extension RAEmbeddingVector {
    /// Cosine similarity via `rac_embeddings_similarity`.
    ///
    /// Commons returns 0 for empty vectors, mismatched dimensions, or when
    /// either vector has zero L2 norm. There is no cached `norm` field on the
    /// proto — the C ABI always computes fresh.
    public func cosineSimilarity(with other: RAEmbeddingVector) -> Float {
        values.withUnsafeBufferPointer { lhs in
            other.values.withUnsafeBufferPointer { rhs in
                var similarity: Float = 0
                let rc = rac_embeddings_similarity(
                    lhs.baseAddress,
                    lhs.count,
                    rhs.baseAddress,
                    rhs.count,
                    &similarity
                )
                return rc == RAC_SUCCESS ? similarity : 0
            }
        }
    }

    /// L2 norm via `rac_embeddings_norm`. Empty vectors have norm 0.
    public func computeNorm() -> Float {
        values.withUnsafeBufferPointer { buffer in
            var norm: Float = 0
            let rc = rac_embeddings_norm(buffer.baseAddress, buffer.count, &norm)
            return rc == RAC_SUCCESS ? norm : 0
        }
    }
}

// MARK: - RAEmbeddingsResult

extension RAEmbeddingsResult {
    public var processingTime: TimeInterval { TimeInterval(processingTimeMs) / 1000.0 }
}
