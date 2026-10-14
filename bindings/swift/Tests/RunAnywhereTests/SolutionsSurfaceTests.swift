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

import Combine
import CRACommons
import Foundation
import LlamaCPPRuntime
import ONNXRuntime
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
        // `VoiceAgentConfig` carries no `typeKind` field of its own -- the
        // enclosing `SolutionConfig.config` oneof arm (already matched
        // above) is the sole type discriminator (idl/solutions.proto).
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

    /// Exercise the new native attachment boundary without requiring model
    /// fixtures: a non-null token that is not registered as a live RAG session
    /// must be rejected before it is stamped into the retrieve operator.
    func testSolutionAttachRejectsUnknownRagSessionHandle() throws {
        let yaml = """
        name: "rag-attach-validation"
        operators:
          - name: "query"
            type: "source"
          - name: "retrieve"
            type: "retrieve"
          - name: "sink"
            type: "sink"
        edges:
          - from: "query.out"
            to: "retrieve.in"
          - from: "retrieve.results"
            to: "sink.in"
        """

        var solution: rac_solution_handle_t?
        let createResult = yaml.withCString {
            rac_solution_create_from_yaml($0, &solution)
        }
        XCTAssertEqual(createResult, RAC_SUCCESS)
        guard let solution else {
            return XCTFail("solution creation should return a native handle")
        }
        defer { rac_solution_destroy(solution) }

        guard let unknownSession = UnsafeMutableRawPointer(bitPattern: 0xBAD) else {
            return XCTFail("failed to construct non-null test handle")
        }
        XCTAssertEqual(
            rac_solution_attach_rag_session(solution, unknownSession),
            RAC_ERROR_INVALID_HANDLE
        )
    }

    /// #914 acceptance path: a Swift Solutions RAG config reaches RetrieveNode
    /// with a real registry-backed session, without manually editing operator
    /// params. The real-model fixture matches core/tests/test_rag_e2e.cpp and
    /// skips when those optional local model files are not configured.
    @MainActor
    func testRagSolutionRunsAgainstLiveSessionWhenModelsAreAvailable() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let embeddingPath = environment["RAG_TEST_EMBED_MODEL"],
              let vocabularyPath = environment["RAG_TEST_EMBED_VOCAB"],
              let llmPath = environment["RAG_TEST_LLM_MODEL"],
              FileManager.default.fileExists(atPath: embeddingPath),
              FileManager.default.fileExists(atPath: vocabularyPath),
              FileManager.default.fileExists(atPath: llmPath) else {
            throw XCTSkip(
                "Set RAG_TEST_EMBED_MODEL, RAG_TEST_EMBED_VOCAB, and " +
                "RAG_TEST_LLM_MODEL to run the live RAG Solutions E2E test"
            )
        }

        // Keep this integration test fully local even when it is run outside
        // the normal release harness.
        setenv("RUNANYWHERE_SWIFT_LOCAL_ONLY", "1", 1)
        try RunAnywhere.initialize(environment: .development)
        LlamaCPP.register()
        ONNX.register()

        // Use per-run ids so this test does not collide with a catalog entry
        // seeded by another test in the same process.
        let suffix = UUID().uuidString.lowercased()
        let embeddingID = "rag-solution-e2e-embed-\(suffix)"
        let llmID = "rag-solution-e2e-llm-\(suffix)"

        let embeddingModel = RAModelInfo.make(
            id: embeddingID,
            name: "RAG Solution E2E MiniLM",
            category: .embedding,
            format: .onnx,
            framework: .onnx,
            localPath: URL(fileURLWithPath: embeddingPath),
            source: .local
        )
        let llmModel = RAModelInfo.make(
            id: llmID,
            name: "RAG Solution E2E LLM",
            category: .language,
            format: .gguf,
            framework: .llamaCpp,
            localPath: URL(fileURLWithPath: llmPath),
            source: .local
        )
        try await CppBridge.ModelRegistry.shared.save(embeddingModel)
        try await CppBridge.ModelRegistry.shared.save(llmModel)

        // MiniLM needs its vocabulary sidecar. Build the generated proto via
        // protobuf JSON so this test does not depend on hand-maintained Swift
        // spellings for snake_case IDL fields.
        let embeddingConfigData = try JSONSerialization.data(
            withJSONObject: ["vocab_path": vocabularyPath]
        )
        let embeddingConfig = String(decoding: embeddingConfigData, as: UTF8.self)
        let ragConfigData = try JSONSerialization.data(withJSONObject: [
            "embeddingModelId": embeddingID,
            "llmModelId": llmID,
            "embeddingConfigJson": embeddingConfig,
            "topK": 4,
            "chunkSize": 64,
            "chunkOverlap": 8,
            "maxContextTokens": 1024
        ])
        let ragConfig = try RARAGConfiguration(jsonUTF8Data: ragConfigData)

        let nativeSession = try await CppBridge.RAG.shared.createPipeline(ragConfig)
        let session = RagSession(handle: nativeSession, llmModelId: llmID, defaultTopK: 4)
        defer { CppBridge.RAG.shared.destroySession(handle: nativeSession) }

        let document = """
        The Zephyr Protocol avoids transmitting duplicate data by assigning a
        stable content hash to every payload. A payload whose hash is already
        present at the receiver is referenced by that hash instead of being
        transmitted again.
        """
        try await session.ingest(document: RagDocument(text: document))

        let question = "How does the Zephyr Protocol avoid transmitting the same data twice?"
        let directMatches = try await session.search(query: question, topK: 4)
        XCTAssertFalse(directMatches.isEmpty, "the live RAG session must retrieve its ingested document")

        // This is SolutionConfig YAML sugar, not a hand-written PipelineSpec:
        // the converter expands it to query -> retrieve -> context -> llm.
        let solutionYAML = """
        rag:
          embed_model_id: "\(embeddingID)"
          llm_model_id: "\(llmID)"
          retrieve_k: 4
        """
        let solution = try await RunAnywhere.solutions.run(yaml: solutionYAML)
        defer { solution.destroy() }

        // Observe the native RAG completion event. RetrieveNode calls
        // rac_rag_query_proto on the attached session; reaching this event with
        // operation_id == "rag.query" proves the worker traversed that live
        // session rather than merely accepting the handle at attach time.
        let queryCompleted = expectation(description: "RAG solution query completed")
        var completionSubscription: AnyCancellable?
        completionSubscription = RunAnywhere.events.ragEvents.sink { event in
            guard event.operationID == "rag.query",
                  event.hasCapability,
                  event.capability.kind.rawValue == 14 else { return }
            queryCompleted.fulfill()
        }
        defer { completionSubscription?.cancel() }

        try await solution.attachRagSession(session)
        try solution.start()
        try solution.feed(question)
        try solution.closeInput()

        await fulfillment(of: [queryCompleted], timeout: 120.0)
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
