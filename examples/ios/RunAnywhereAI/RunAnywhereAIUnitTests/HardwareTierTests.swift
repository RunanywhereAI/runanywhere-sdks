//
//  HardwareTierTests.swift
//  RunAnywhereAIUnitTests
//
//  Ensures the example app does not invent RAM/ANE tier or memory-budget policy.
//

import XCTest
@testable import RunAnywhereAI
import RunAnywhere

final class HardwareTierTests: XCTestCase {
    func testResolverSurfacesUnknownWithoutLocalThresholds() {
        let resolver = HardwareTierResolver()
        let withMemory = SystemDeviceInfo(
            modelName: "iPhone",
            chipName: "A18",
            totalMemory: 8_000_000_000,
            availableMemory: 4_000_000_000,
            neuralEngineAvailable: true,
            osVersion: "18.0",
            appVersion: "1.0"
        )
        let empty = SystemDeviceInfo(
            modelName: "Unknown",
            chipName: "Unknown",
            totalMemory: 0,
            availableMemory: 0,
            neuralEngineAvailable: false,
            osVersion: "18.0",
            appVersion: "1.0"
        )

        XCTAssertEqual(resolver.resolve(from: withMemory), .unknown)
        XCTAssertEqual(resolver.resolve(from: empty), .unknown)
        XCTAssertEqual(resolver.resolve(from: nil), .unknown)
    }

    func testRecommendationDoesNotUseLocalByteBudget() {
        var small = RAModelInfo()
        small.id = "mlx-lfm2-350m"
        small.name = "LFM2 350M"
        small.category = .language
        small.downloadSizeBytes = 9_000_000_000

        let engine = ModelRecommendationEngine()
        let allowed = engine.recommend(
            tier: .unknown,
            appleFoundationAvailable: false,
            from: [small],
            canRunByModelID: ["mlx-lfm2-350m": true]
        )
        let refused = engine.recommend(
            tier: .unknown,
            appleFoundationAvailable: false,
            from: [small],
            canRunByModelID: ["mlx-lfm2-350m": false]
        )

        XCTAssertEqual(allowed.recommendedLLMs.map(\.id), ["mlx-lfm2-350m"])
        XCTAssertTrue(refused.recommendedLLMs.isEmpty)
    }
}
