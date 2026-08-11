//
//  ModelCompatibilityProtoSurfaceTests.swift
//  RunAnywhere SDK
//
//  Compile-time surface check for the commons model-compatibility bridge.
//

import XCTest

@testable import RunAnywhere

final class ModelCompatibilityProtoSurfaceTests: XCTestCase {
    func testModelsNamespaceExposesCompatibilityCheck() {
        let byID: (String) async throws -> RAModelCompatibilityResult =
            RunAnywhere.models.checkCompatibility(id:)
        let byRequest: (RAModelCompatibilityRequest) async throws -> RAModelCompatibilityResult =
            RunAnywhere.models.checkCompatibility

        _ = (byID, byRequest)
    }

    func testCompatibilityRequestCarriesProbeFields() {
        var request = RAModelCompatibilityRequest()
        request.modelID = "demo-model"
        request.availableRamBytes = 4_000_000_000
        request.availableStorageBytes = 20_000_000_000

        XCTAssertEqual(request.modelID, "demo-model")
        XCTAssertEqual(request.availableRamBytes, 4_000_000_000)
        XCTAssertEqual(request.availableStorageBytes, 20_000_000_000)
    }

    func testCompatibilityResultCarriesCommonsVerdictFields() {
        var result = RAModelCompatibilityResult()
        result.modelID = "demo-model"
        result.canRun = true
        result.canFit = true
        result.isCompatible = true
        result.requiredMemoryBytes = 1_000_000_000
        result.availableMemoryBytes = 4_000_000_000

        XCTAssertTrue(result.canRun)
        XCTAssertTrue(result.canFit)
        XCTAssertTrue(result.isCompatible)
        XCTAssertEqual(result.requiredMemoryBytes, 1_000_000_000)
    }
}
