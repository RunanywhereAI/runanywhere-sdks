import XCTest

@testable import RunAnywhere

final class ModelLoadOptionsTests: XCTestCase {
    func testRequestPreservesContextAndOrderedPreferencesOnTheWire() throws {
        let request = try makeRequest(options: LoadOptions(
            backendPreferences: [
                BackendPreference(backend: .onnx),
                BackendPreference(backend: .llamaCpp)
            ],
            contextLength: 4096
        ))
        let decoded = try RAModelLoadRequest(serializedBytes: request.serializedData())

        XCTAssertEqual(decoded.contextLength, 4096)
        XCTAssertEqual(decoded.framework, .onnx)
        XCTAssertEqual(decoded.backendPreferences, [.onnx, .llamaCpp])
    }

    func testOmittedAndZeroContextRemainDistinct() throws {
        XCTAssertFalse(try makeRequest(options: nil).hasContextLength)
        let request = try makeRequest(options: LoadOptions(contextLength: 0))
        XCTAssertTrue(request.hasContextLength)
        XCTAssertEqual(request.contextLength, 0)
    }

    func testContextBoundaries() throws {
        XCTAssertEqual(
            try makeRequest(options: LoadOptions(contextLength: Int(Int32.max))).contextLength,
            Int32.max
        )
        for invalid in [-1, Int(Int32.max) + 1] {
            XCTAssertThrowsError(try makeRequest(options: LoadOptions(contextLength: invalid)))
        }
    }

    func testRequiredPreferenceIsRejectedEvenAfterTheFirstEntry() {
        let options = LoadOptions(backendPreferences: [
            BackendPreference(backend: .onnx),
            BackendPreference(backend: .llamaCpp, required: true)
        ])
        XCTAssertThrowsError(try makeRequest(options: options))
        XCTAssertTrue(RunAnywhere.capabilities().unavailable.contains {
            $0.name == "loadOptions.backendPreferences.required"
        })
    }

    func testLoadResolvedRejectsRequiredPreferenceBeforeCallingNativeCode() async {
        var model = ModelInfo()
        model.id = "demo-model"
        do {
            _ = try await RunAnywhere.loadResolved(
                model: model,
                category: .language,
                options: LoadOptions(backendPreferences: [
                    BackendPreference(backend: .llamaCpp, required: true)
                ])
            )
            XCTFail("A required preference must fail preflight")
        } catch {
            XCTAssertTrue(error is SDKException)
        }
    }

    func testLoneUnspecifiedPreferenceKeepsCatalogRouting() throws {
        let request = try makeRequest(options: LoadOptions(backendPreferences: [
            BackendPreference(backend: .unspecified)
        ]))
        XCTAssertEqual(request.framework, .llamaCpp)
        XCTAssertEqual(request.backendPreferences, [.unspecified])
    }

    func testUnspecifiedFirstEntryDoesNotPinCatalogAheadOfLaterPreferences() throws {
        let request = try makeRequest(options: LoadOptions(backendPreferences: [
            BackendPreference(backend: .unspecified),
            BackendPreference(backend: .onnx)
        ]))
        XCTAssertTrue(request.hasFramework)
        XCTAssertEqual(request.framework, .unspecified)
        XCTAssertEqual(request.backendPreferences, [.unspecified, .onnx])
    }

    private func makeRequest(options: LoadOptions?) throws -> RAModelLoadRequest {
        var model = ModelInfo()
        model.id = "demo-model"
        model.framework = .llamaCpp
        return try RunAnywhere.modelLoadRequest(model: model, category: .language, options: options)
    }
}
