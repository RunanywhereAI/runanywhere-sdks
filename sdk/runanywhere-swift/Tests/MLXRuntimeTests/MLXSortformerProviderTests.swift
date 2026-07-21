import Foundation
@testable import MLXRuntime
import XCTest

final class MLXSortformerProviderTests: XCTestCase {
    func testPinnedBundleMetadata() {
        XCTAssertEqual(
            MLXSortformerCatalog.repository,
            "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
        )
        XCTAssertEqual(
            MLXSortformerCatalog.revision,
            "e23e6404bd9859e93edbf94a740eb1c7fc58f12e"
        )
        XCTAssertEqual(MLXSortformerCatalog.maximumSpeakerCount, 4)
        XCTAssertEqual(MLXSortformerCatalog.supportedSampleRate, 16_000)
        XCTAssertEqual(MLXSortformerCatalog.downloadSizeBytes, 236_109_834)
        XCTAssertEqual(
            MLXSortformerCatalog.files.map(\.filename),
            ["config.json", "model.safetensors"]
        )
        XCTAssertEqual(
            MLXSortformerCatalog.files.map(\.sha256),
            [
                "17c9f943bed07b0593f2b8dca01e0be6a418053becc6148b01ecabdff9cbd84d",
                "3b60b8df29e59a8abaf8061ceeeae6e9284a68fbcd2e762c68f5e058bfceebfa"
            ]
        )
        XCTAssertTrue(
            MLXSortformerCatalog.files.allSatisfy {
                $0.url.absoluteString.contains(MLXSortformerCatalog.revision)
            }
        )
    }

    func testBundleValidationReportsBothRequiredFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try MLXSortformerCatalog.validateModelDirectory(directory)) { error in
            XCTAssertEqual(
                error as? MLXSortformerProviderError,
                .missingBundleFiles(["config.json", "model.safetensors"])
            )
        }
    }

    func testOptionsRejectUnsupportedSampleRate() {
        var options = MLXSortformerOptions()
        options.sampleRate = 48_000

        XCTAssertThrowsError(try options.validate(sampleCount: 16_000)) { error in
            XCTAssertEqual(
                error as? MLXSortformerProviderError,
                .unsupportedSampleRate(48_000)
            )
        }
    }

    func testOptionsRejectInvalidStreamingCache() {
        var options = MLXSortformerOptions()
        options.speakerCacheFrames = 0

        XCTAssertThrowsError(try options.validate(sampleCount: 16_000)) { error in
            XCTAssertEqual(
                error as? MLXSortformerProviderError,
                .invalidStreamingCacheSize
            )
        }
    }
}
