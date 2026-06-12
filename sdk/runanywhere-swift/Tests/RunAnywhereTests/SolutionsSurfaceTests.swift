//
//  SolutionsSurfaceTests.swift
//  RunAnywhere SDK
//
//  Focused tests for the generated RASolution* public surface and the
//  `RunAnywhere.solutions` capability shape (RunAnywhere+Solutions.swift).
//
//  Cross-SDK parity: mirrored by SolutionsGeneratedSurfaceTest.kt (Kotlin),
//  solutions_surface_test.dart (Flutter), and RunAnywhere+Solutions.test.ts
//  (RN / Web). The commons layer is covered by test_solution_runner.cpp; this
//  pins the SDK-layer proto decode + the public accessor signatures so a drift
//  in the generated types or the capability surface fails at unit-test time.
//

import Foundation
import SwiftProtobuf
import XCTest

@testable import RunAnywhere

final class SolutionsSurfaceTests: XCTestCase {

    /// The committed fixture decodes into a typed `RASolutionConfig`, exercising
    /// the same proto path that `RunAnywhere.solutions.run(config:)` serialises.
    func testMinimalFixtureDecodesIntoGeneratedSolutionConfig() throws {
        let data = try Self.loadFixture("minimal_solution_config")
        let config = try RASolutionConfig(jsonUTF8Data: data)

        guard case .voiceAgent(let voiceAgent)? = config.config else {
            return XCTFail("fixture should populate the voice_agent oneof arm")
        }

        XCTAssertEqual(voiceAgent.llmModelID, "qwen3-4b-q4_k_m")
        XCTAssertEqual(voiceAgent.sttModelID, "whisper-base")
        XCTAssertEqual(voiceAgent.ttsModelID, "kokoro")
        XCTAssertEqual(voiceAgent.vadModelID, "silero-v5")
        XCTAssertEqual(voiceAgent.sampleRateHz, 16000)
        XCTAssertEqual(voiceAgent.chunkMs, 20)
        XCTAssertEqual(voiceAgent.maxContextTokens, 4096)
        XCTAssertEqual(voiceAgent.typeKind, .voiceAgent)
    }

    /// A decoded config serialises losslessly — the bytes path is exactly what
    /// `run(configBytes:)` forwards into `rac_solution_create_from_proto`.
    func testGeneratedSolutionConfigRoundTripsThroughProtoBytes() throws {
        let data = try Self.loadFixture("minimal_solution_config")
        let config = try RASolutionConfig(jsonUTF8Data: data)

        let bytes = try config.serializedData()
        XCTAssertFalse(bytes.isEmpty)
        XCTAssertEqual(try RASolutionConfig(serializedBytes: bytes), config)
    }

    /// Pin the public `RunAnywhere.solutions` capability surface so the three
    /// `run` overloads keep their generated-proto / bytes / YAML signatures.
    func testSolutionsCapabilityExposesGeneratedRunOverloads() {
        let runConfig: (RASolutionConfig) async throws -> SolutionHandle = RunAnywhere.solutions.run
        let runBytes: (Data) async throws -> SolutionHandle = RunAnywhere.solutions.run
        let runYaml: (String) async throws -> SolutionHandle = RunAnywhere.solutions.run

        _ = (runConfig, runBytes, runYaml)
    }

    /// The generated handle descriptor carries its canonical fields.
    func testGeneratedSolutionHandleCarriesCanonicalFields() {
        var handle = RASolutionHandle()
        handle.handleID = "sol-1"
        handle.solutionType = "voice_agent"
        handle.createdAtMs = 1_774_000_000_000
        handle.state = "created"

        XCTAssertEqual(handle.handleID, "sol-1")
        XCTAssertEqual(handle.solutionType, "voice_agent")
        XCTAssertEqual(handle.createdAtMs, 1_774_000_000_000)
        XCTAssertTrue(handle.hasState)
        XCTAssertEqual(handle.state, "created")
    }

    // Resolve a fixture relative to this source file so the test does not depend
    // on the test target declaring `resources:` in Package.swift.
    private static func loadFixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).json")
        return try Data(contentsOf: url)
    }
}
