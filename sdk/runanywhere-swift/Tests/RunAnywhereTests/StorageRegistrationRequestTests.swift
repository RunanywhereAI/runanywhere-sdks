//
//  StorageRegistrationRequestTests.swift
//  RunAnywhere SDK
//
//  Focused checks for independent runtime-memory and download-size planning.
//

import XCTest

@testable import RunAnywhere

final class StorageRegistrationRequestTests: XCTestCase {
    func testMultiFileRegistrationPublicSurfaceAppendsDownloadSize() {
        let register:
            ([RAModelFileDescriptor], String, String, InferenceFramework, ModelCategory,
             Int64?, Int?, Bool, RAModelSource, Int64?) async throws -> RAModelInfo =
            RunAnywhere.registerModel

        _ = register
    }

    func testMultiFileRegistrationKeepsRuntimeAndDownloadSizesIndependent() {
        var request = RARegisterMultiFileModelRequest()

        RunAnywhere.applyMultiFileRegistrationSizes(
            memoryRequirement: 2_000_000_000,
            downloadSize: 1_110_024_519,
            to: &request
        )

        XCTAssertTrue(request.hasMemoryRequiredBytes)
        XCTAssertEqual(request.memoryRequiredBytes, 2_000_000_000)
        XCTAssertTrue(request.hasDownloadSizeBytes)
        XCTAssertEqual(request.downloadSizeBytes, 1_110_024_519)
    }

    func testMultiFileRegistrationDefaultsDownloadSizeToRuntimeMemory() {
        var request = RARegisterMultiFileModelRequest()

        RunAnywhere.applyMultiFileRegistrationSizes(
            memoryRequirement: 512_000_000,
            downloadSize: nil,
            to: &request
        )

        XCTAssertEqual(request.memoryRequiredBytes, 512_000_000)
        XCTAssertEqual(request.downloadSizeBytes, 512_000_000)
    }

    func testMultiFileRegistrationCanSetDownloadSizeWithoutRuntimeMemory() {
        var request = RARegisterMultiFileModelRequest()

        RunAnywhere.applyMultiFileRegistrationSizes(
            memoryRequirement: nil,
            downloadSize: 42_000_000,
            to: &request
        )

        XCTAssertFalse(request.hasMemoryRequiredBytes)
        XCTAssertTrue(request.hasDownloadSizeBytes)
        XCTAssertEqual(request.downloadSizeBytes, 42_000_000)
    }
}
