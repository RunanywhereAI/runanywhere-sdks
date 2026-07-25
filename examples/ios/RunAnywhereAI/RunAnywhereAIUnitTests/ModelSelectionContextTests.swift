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

    func testDiarizationContextFiltersSpeakerDiarization() {
        XCTAssertEqual(ModelSelectionContext.diarization.title, "Choose Diarization Model")
        XCTAssertEqual(ModelSelectionContext.diarization.relevantCategories, [.speakerDiarization])
        XCTAssertFalse(ModelSelectionContext.diarization.supportsFolderImport)
        XCTAssertNil(ModelSelectionContext.diarization.allowedFrameworks)
    }

    func testSegmentationContextFiltersSemanticSegmentation() {
        XCTAssertEqual(ModelSelectionContext.segmentation.title, "Choose Segmentation Model")
        XCTAssertEqual(ModelSelectionContext.segmentation.relevantCategories, [.semanticSegmentation])
        XCTAssertFalse(ModelSelectionContext.segmentation.supportsFolderImport)
        XCTAssertNil(ModelSelectionContext.segmentation.allowedFrameworks)
    }

    func testCatalogContextsDoNotSupportFolderImport() {
        XCTAssertFalse(ModelSelectionContext.llm.supportsFolderImport)
        XCTAssertFalse(ModelSelectionContext.stt.supportsFolderImport)
        XCTAssertFalse(ModelSelectionContext.diarization.supportsFolderImport)
        XCTAssertFalse(ModelSelectionContext.segmentation.supportsFolderImport)
    }
}
