import Foundation
@testable import RunAnywhere
import SwiftProtobuf
import XCTest

final class DiarizationPublicSurfaceTests: XCTestCase {
    func testGeneratedRequestRoundTripPreservesStandaloneOptions() throws {
        var options = RADiarizationOptions()
        options.sampleRateHz = 16_000
        options.channelCount = 1
        options.encoding = .pcmF32Le
        options.threshold = 0.55
        options.minimumDurationMs = 120
        options.mergeGapMs = 80

        var request = RADiarizationRequest()
        request.audioData = Data([0, 0, 0, 0])
        request.options = options
        let decoded = try RADiarizationRequest(serializedBytes: request.serializedData())

        XCTAssertEqual(decoded, request)
        XCTAssertTrue(decoded.hasOptions)
        XCTAssertEqual(decoded.options.encoding, .pcmF32Le)
    }

    func testRunAnywhereExposesOfflineAndPersistentStreamFacades() {
        let offline: (RADiarizationRequest) async throws -> RADiarizationResult =
            RunAnywhere.diarize
        let stream: (
            AsyncStream<Data>,
            RADiarizationOptions
        ) async throws -> AsyncThrowingStream<RADiarizationStreamEvent, Error> =
            RunAnywhere.diarizeStream

        withExtendedLifetime((offline, stream)) {}
    }

    func testCanonicalUnloadReconciliationUsesCapabilityAndExactModelIDSemantics() {
        var result = RAModelUnloadResult()
        result.success = true
        result.unloadedModelIds = ["sortformer-a"]

        var request = RAModelUnloadRequest()
        request.modelID = "sortformer-a"
        XCTAssertTrue(
            CppBridge.Diarization.shouldUnloadComponentCopy(
                loadedModelID: "sortformer-a",
                request: request,
                result: result
            )
        )
        XCTAssertFalse(
            CppBridge.Diarization.shouldUnloadComponentCopy(
                loadedModelID: "sortformer-b",
                request: request,
                result: result
            )
        )

        request = RAModelUnloadRequest()
        request.category = .speakerDiarization
        XCTAssertTrue(
            CppBridge.Diarization.shouldUnloadComponentCopy(
                loadedModelID: "stale-component-copy",
                request: request,
                result: result
            )
        )

        request.category = .language
        XCTAssertFalse(
            CppBridge.Diarization.shouldUnloadComponentCopy(
                loadedModelID: "unrelated-diarization-model",
                request: request,
                result: result
            )
        )
    }

    func testCanonicalUnloadReconciliationRequiresSuccessButHonorsUnloadAll() {
        var request = RAModelUnloadRequest()
        request.unloadAll = true
        var result = RAModelUnloadResult()
        result.success = true

        XCTAssertTrue(
            CppBridge.Diarization.shouldUnloadComponentCopy(
                loadedModelID: "sortformer-a",
                request: request,
                result: result
            )
        )

        result.success = false
        XCTAssertFalse(
            CppBridge.Diarization.shouldUnloadComponentCopy(
                loadedModelID: "sortformer-a",
                request: request,
                result: result
            )
        )
        XCTAssertFalse(
            CppBridge.Diarization.shouldUnloadComponentCopy(
                loadedModelID: nil,
                request: request,
                result: RAModelUnloadResult()
            )
        )
    }
}
