//
//  EmbeddingsProtoHelpersTests.swift
//  RunAnywhere SDK
//
//  Focused bridge tests for RAEmbeddingVector helpers. Math is owned by
//  commons (`rac_embeddings_norm` / `rac_embeddings_similarity`); these
//  assertions pin the Swift convenience surface to that contract.
//

import XCTest

@testable import RunAnywhere

final class EmbeddingsProtoHelpersTests: XCTestCase {
    func testComputeNormEmptyIsZero() {
        var vector = RAEmbeddingVector()
        vector.values = []
        XCTAssertEqual(vector.computeNorm(), 0)
    }

    func testComputeNormPythagoreanTriple() {
        var vector = RAEmbeddingVector()
        vector.values = [3, 4]
        XCTAssertEqual(vector.computeNorm(), 5, accuracy: 1e-5)
    }

    func testCosineSimilarityAlignedUnitVectors() {
        var lhs = RAEmbeddingVector()
        lhs.values = [1, 0, 0]
        var rhs = RAEmbeddingVector()
        rhs.values = [1, 0, 0]
        XCTAssertEqual(lhs.cosineSimilarity(with: rhs), 1, accuracy: 1e-5)
    }

    func testCosineSimilarityEmptyOrMismatchOrZeroNormIsZero() {
        var empty = RAEmbeddingVector()
        empty.values = []
        var nonzero = RAEmbeddingVector()
        nonzero.values = [1, 2, 3]
        var short = RAEmbeddingVector()
        short.values = [1, 2]
        var zero = RAEmbeddingVector()
        zero.values = [0, 0, 0]

        XCTAssertEqual(empty.cosineSimilarity(with: nonzero), 0)
        XCTAssertEqual(nonzero.cosineSimilarity(with: short), 0)
        XCTAssertEqual(nonzero.cosineSimilarity(with: zero), 0)
    }

    func testProcessingTimeConvertsMilliseconds() {
        var result = RAEmbeddingsResult()
        result.processingTimeMs = 1500
        XCTAssertEqual(result.processingTime, 1.5, accuracy: 1e-9)
    }
}
