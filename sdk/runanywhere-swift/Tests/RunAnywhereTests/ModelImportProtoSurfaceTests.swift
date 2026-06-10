//
//  ModelImportProtoSurfaceTests.swift
//  RunAnywhere SDK
//
//  Focused compile-time checks for generated model import and completion
//  persistence surface.
//

import XCTest

@testable import RunAnywhere

final class ModelImportProtoSurfaceTests: XCTestCase {
    func testModelImportSurfaceUsesGeneratedProtoTypes() {
        let importModel: (RAModelImportRequest) async throws -> RAModelImportResult =
            RunAnywhere.importModel

        _ = importModel
    }

    func testModelImportRequestCarriesCanonicalFields() {
        var model = RAModelInfo()
        model.id = "demo-model"
        model.name = "Demo Model"
        model.localPath = "/models/demo.gguf"
        model.format = .gguf
        model.framework = .llamaCpp
        model.isDownloaded = true

        var request = RAModelImportRequest()
        request.model = model
        request.sourcePath = "/models/demo.gguf"
        request.overwriteExisting = true
        request.validateBeforeRegister = true

        XCTAssertTrue(request.hasModel)
        XCTAssertEqual(request.model.id, "demo-model")
        XCTAssertEqual(request.sourcePath, "/models/demo.gguf")
        XCTAssertTrue(request.overwriteExisting)
        XCTAssertTrue(request.validateBeforeRegister)
    }
}
