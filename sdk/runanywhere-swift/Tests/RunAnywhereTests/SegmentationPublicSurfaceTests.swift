import Foundation
@testable import RunAnywhere
import SwiftProtobuf
import XCTest

final class SegmentationPublicSurfaceTests: XCTestCase {
    func testGeneratedRequestRoundTripPreservesPackedImageAndOptions() throws {
        var image = RASegmentationImage()
        image.data = Data([255, 0, 0, 0, 255, 0])
        image.width = 2
        image.height = 1
        image.pixelFormat = .rgb8

        var options = RASegmentationOptions()
        options.includeDiagnosticRgba = true

        var request = RASegmentationRequest()
        request.image = image
        request.options = options

        let decoded = try RASegmentationRequest(serializedBytes: request.serializedData())

        XCTAssertEqual(decoded, request)
        XCTAssertTrue(decoded.hasImage)
        XCTAssertTrue(decoded.hasOptions)
        XCTAssertEqual(decoded.image.pixelFormat, .rgb8)
        XCTAssertTrue(decoded.options.includeDiagnosticRgba)
    }

    func testGeneratedResultRoundTripPreservesSourceDimensionMasksAndSummaries() throws {
        var summary = RASegmentationClassSummary()
        summary.classID = 12
        summary.pixelCount = 2
        summary.fraction = 1
        summary.label = "person"

        var result = RASegmentationResult()
        result.width = 2
        result.height = 1
        result.classMaskU16Le = Data([12, 0, 12, 0])
        result.diagnosticRgba = Data([255, 0, 0, 255, 255, 0, 0, 255])
        result.classSummaries = [summary]
        result.processingTimeMs = 9
        result.modelID = "segformer-b0"

        let decoded = try RASegmentationResult(serializedBytes: result.serializedData())

        XCTAssertEqual(decoded, result)
        XCTAssertTrue(decoded.hasDiagnosticRgba)
        XCTAssertEqual(decoded.classMaskU16Le.count, Int(decoded.width * decoded.height) * 2)
        XCTAssertEqual(decoded.diagnosticRgba.count, Int(decoded.width * decoded.height) * 4)
    }

    func testRunAnywhereExposesCanonicalRequestFacade() {
        let segment: (RASegmentationRequest) async throws -> RASegmentationResult =
            RunAnywhere.segment

        withExtendedLifetime(segment) {}
    }

    func testNoModelReadinessGateFailsBeforeNativeDispatch() {
        XCTAssertThrowsError(
            try RunAnywhere.requireSemanticSegmentationModel(RACurrentModelResult())
        ) { error in
            guard let sdkError = error as? SDKException else {
                return XCTFail("Expected SDKException, got \(error)")
            }
            XCTAssertEqual(sdkError.code, .modelNotLoaded)
            XCTAssertEqual(sdkError.category, .component)
            XCTAssertEqual(sdkError.message, "Semantic-segmentation model not loaded")
        }

        var loaded = RACurrentModelResult()
        loaded.found = true
        XCTAssertNoThrow(try RunAnywhere.requireSemanticSegmentationModel(loaded))
    }
}
