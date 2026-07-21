//
//  ModelSelectionContextTests.swift
//  RunAnywhereAIUnitTests
//

import XCTest
@testable import RunAnywhereAI

final class ModelSelectionContextTests: XCTestCase {
    func testRAGEmbeddingAllowsPortableLlamaCppModels() throws {
        let frameworks = try XCTUnwrap(ModelSelectionContext.ragEmbedding.allowedFrameworks)

        XCTAssertEqual(frameworks, [.llamaCpp, .onnx, .mlx])
    }
}
