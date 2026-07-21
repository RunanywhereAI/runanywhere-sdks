import Foundation
@testable import RunAnywhere
import XCTest

final class VocoderPublicSurfaceTests: XCTestCase {
    func testPublicSurfaceUsesErgonomicFloat32Tensors() {
        let operation: (VocoderRequest) async throws -> VocoderResult = RunAnywhere.vocode
        let request = VocoderRequest(
            melSpectrogram: [0, 0.25, -0.5, 1],
            batchSize: 1,
            melBinCount: 2,
            frameCount: 2
        )

        XCTAssertEqual(request.melSpectrogram, [0, 0.25, -0.5, 1])
        XCTAssertEqual(RASDKComponent.vocoder.displayName, "Vocoder")
        withExtendedLifetime(operation) {}
    }

    func testFloat32WireEncodingIsExplicitlyLittleEndian() throws {
        let encoded = try VocoderWireCodec.encodeFloat32LittleEndian(
            [1, -2.5, Float.leastNonzeroMagnitude],
            fieldPath: "test"
        )

        XCTAssertEqual(
            [UInt8](encoded),
            [
                0x00, 0x00, 0x80, 0x3f,
                0x00, 0x00, 0x20, 0xc0,
                0x01, 0x00, 0x00, 0x00
            ]
        )
        XCTAssertEqual(
            try VocoderWireCodec.decodeFloat32LittleEndian(encoded, expectedCount: 3),
            [1, -2.5, Float.leastNonzeroMagnitude]
        )
    }

    func testWireRequestValidatesShapeOverflowAndFiniteValues() throws {
        let valid = VocoderRequest(
            melSpectrogram: [0, 1, 2, 3],
            batchSize: 1,
            melBinCount: 2,
            frameCount: 2
        )
        let wire = try VocoderWireCodec.makeWireRequest(valid)
        XCTAssertEqual(wire.batchSize, 1)
        XCTAssertEqual(wire.melBinCount, 2)
        XCTAssertEqual(wire.frameCount, 2)
        XCTAssertEqual(wire.melSpectrogramF32Le.count, 16)

        assertValidationFailure(
            VocoderRequest(
                melSpectrogram: [0],
                batchSize: 1,
                melBinCount: 2,
                frameCount: 2
            ),
            fieldPath: "VocoderRequest.melSpectrogram"
        )
        assertValidationFailure(
            VocoderRequest(
                melSpectrogram: [.infinity],
                batchSize: 1,
                melBinCount: 1,
                frameCount: 1
            ),
            fieldPath: "VocoderRequest.melSpectrogram[0]"
        )
        assertValidationFailure(
            VocoderRequest(
                melSpectrogram: [],
                batchSize: Int(UInt32.max),
                melBinCount: Int(UInt32.max),
                frameCount: Int(UInt32.max)
            ),
            fieldPath: "VocoderRequest.melSpectrogram"
        )
    }

    func testWireResultProducesTypedSamplesAndChecksLifecycleIdentity() throws {
        let request = VocoderRequest(
            melSpectrogram: [0, 0],
            batchSize: 1,
            melBinCount: 1,
            frameCount: 2
        )
        var wire = RAVocoderResult()
        wire.samplesF32Le = try VocoderWireCodec.encodeFloat32LittleEndian(
            [0.1, -0.2, 0.3, -0.4],
            fieldPath: "test"
        )
        wire.batchSize = 1
        wire.channelCount = 1
        wire.sampleCount = 4
        wire.sampleRateHz = 22_050
        wire.hopLength = 2
        wire.processingTimeMs = 7
        wire.modelID = "bigvgan"

        let result = try VocoderWireCodec.makePublicResult(
            wire,
            request: request,
            loadedModelID: "bigvgan"
        )
        XCTAssertEqual(result.samples, [0.1, -0.2, 0.3, -0.4])
        XCTAssertEqual(result.batchSize, 1)
        XCTAssertEqual(result.channelCount, 1)
        XCTAssertEqual(result.sampleCount, 4)
        XCTAssertEqual(result.sampleRateHz, 22_050)
        XCTAssertEqual(result.hopLength, 2)
        XCTAssertEqual(result.processingTimeMs, 7)
        XCTAssertEqual(result.modelID, "bigvgan")

        wire.modelID = "different-model"
        XCTAssertThrowsError(
            try VocoderWireCodec.makePublicResult(
                wire,
                request: request,
                loadedModelID: "bigvgan"
            )
        ) { error in
            assertProcessingFailure(error, containing: "modelID")
        }
    }

    func testWireResultRejectsMalformedBytes() throws {
        let request = makeRequest()
        var wire = try makeValidWireResult()
        wire.samplesF32Le = try VocoderWireCodec.encodeFloat32LittleEndian(
            [0, 0, 0],
            fieldPath: "test"
        )

        XCTAssertThrowsError(
            try VocoderWireCodec.makePublicResult(
                wire,
                request: request,
                loadedModelID: "bigvgan"
            )
        ) { error in
            assertProcessingFailure(error, containing: "samplesF32Le")
        }
    }

    func testWireResultRejectsNonfiniteSamples() throws {
        let request = makeRequest()
        var wire = try makeValidWireResult()
        wire.samplesF32Le = try VocoderWireCodec.encodeFloat32LittleEndian(
            [0, .nan, 0, 0],
            fieldPath: "test"
        )
        XCTAssertThrowsError(
            try VocoderWireCodec.makePublicResult(
                wire,
                request: request,
                loadedModelID: "bigvgan"
            )
        ) { error in
            assertProcessingFailure(error, containing: "non-finite")
        }
    }

    func testWireResultRejectsTemporalShapeMismatch() throws {
        let request = makeRequest()
        var wire = try makeValidWireResult()
        wire.samplesF32Le = try VocoderWireCodec.encodeFloat32LittleEndian(
            [0, 0, 0, 0, 0],
            fieldPath: "test"
        )
        wire.sampleCount = 5
        XCTAssertThrowsError(
            try VocoderWireCodec.makePublicResult(
                wire,
                request: request,
                loadedModelID: "bigvgan"
            )
        ) { error in
            assertProcessingFailure(error, containing: "frameCount * hopLength")
        }
    }

    func testWireResultRejectsNonMonoOutput() throws {
        let request = makeRequest()
        var wire = try makeValidWireResult()
        wire.samplesF32Le = try VocoderWireCodec.encodeFloat32LittleEndian(
            [0, 0, 0, 0, 0, 0, 0, 0],
            fieldPath: "test"
        )
        wire.channelCount = 2
        wire.sampleCount = 4
        XCTAssertThrowsError(
            try VocoderWireCodec.makePublicResult(
                wire,
                request: request,
                loadedModelID: "bigvgan"
            )
        ) { error in
            assertProcessingFailure(error, containing: "one audio channel")
        }
    }

    func testNoModelReadinessGateFailsBeforeNativeDispatch() {
        XCTAssertThrowsError(try RunAnywhere.requireVocoderModel(RACurrentModelResult())) { error in
            guard let sdkError = error as? SDKException else {
                return XCTFail("Expected SDKException, got \(error)")
            }
            XCTAssertEqual(sdkError.code, .modelNotLoaded)
            XCTAssertEqual(sdkError.category, .component)
            XCTAssertEqual(sdkError.message, "Vocoder model not loaded")
        }

        var loaded = RACurrentModelResult()
        loaded.found = true
        loaded.modelID = "bigvgan"
        XCTAssertEqual(try RunAnywhere.requireVocoderModel(loaded), "bigvgan")
    }

    private func makeRequest() -> VocoderRequest {
        VocoderRequest(
            melSpectrogram: [0, 0],
            batchSize: 1,
            melBinCount: 1,
            frameCount: 2
        )
    }

    private func makeValidWireResult() throws -> RAVocoderResult {
        var wire = RAVocoderResult()
        wire.samplesF32Le = try VocoderWireCodec.encodeFloat32LittleEndian(
            [0, 0, 0, 0],
            fieldPath: "test"
        )
        wire.batchSize = 1
        wire.channelCount = 1
        wire.sampleCount = 4
        wire.sampleRateHz = 22_050
        wire.hopLength = 2
        wire.modelID = "bigvgan"
        return wire
    }

    private func assertValidationFailure(
        _ request: VocoderRequest,
        fieldPath: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try VocoderWireCodec.makeWireRequest(request),
            file: file,
            line: line
        ) { error in
            guard let sdkError = error as? SDKException else {
                return XCTFail("Expected SDKException, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(sdkError.code, .invalidArgument, file: file, line: line)
            XCTAssertEqual(sdkError.category, .validation, file: file, line: line)
            XCTAssertEqual(sdkError.fieldPath, fieldPath, file: file, line: line)
        }
    }

    private func assertProcessingFailure(
        _ error: any Error,
        containing text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let sdkError = error as? SDKException else {
            return XCTFail("Expected SDKException, got \(error)", file: file, line: line)
        }
        XCTAssertEqual(sdkError.code, .processingFailed, file: file, line: line)
        XCTAssertEqual(sdkError.category, .internal, file: file, line: line)
        XCTAssertTrue(sdkError.message.contains(text), file: file, line: line)
    }
}
