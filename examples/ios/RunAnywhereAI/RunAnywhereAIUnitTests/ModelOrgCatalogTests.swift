//
//  ModelOrgCatalogTests.swift
//  RunAnywhereAIUnitTests
//
//  Locks the organisation taxonomy to the same publisher rules as Android.
//

import XCTest
@testable import RunAnywhereAI
import RunAnywhere

final class ModelOrgCatalogTests: XCTestCase {

    func testNemotronResolvesToNvidiaNotMeta() {
        let nemotron = makeModel(id: "nemotron_nano_8b", name: "Llama 3.1 Nemotron Nano 8B (HNPU)")
        let nano4b = makeModel(id: "llama-3.1-nemotron-nano-4b-v1.1-q4_k_m", name: "NVIDIA Llama 3.1 Nemotron Nano 4B")
        let llama = makeModel(id: "llama3_2_1b", name: "Llama 3.2 1B")

        XCTAssertEqual(ModelOrgCatalog.org(for: nemotron), .nvidia)
        XCTAssertEqual(ModelOrgCatalog.org(for: nano4b), .nvidia)
        XCTAssertEqual(ModelOrgCatalog.org(for: llama), .meta)
    }

    func testNvidiaSpeechModelsGroupTogether() {
        let models = [
            makeModel(id: "parakeet_ctc_1_1b", name: "Parakeet CTC 1.1B (HNPU)", category: .speechRecognition),
            makeModel(id: "sherpa-nemo-canary-180m-flash-int8", name: "NVIDIA Canary 180M Flash", category: .speechRecognition),
            makeModel(id: "whisper_base", name: "Whisper Base", category: .speechRecognition),
        ]

        let groups = ModelOrgCatalog.groups(from: models)
        XCTAssertEqual(groups.map(\.org), [.nvidia, .openAI])
        XCTAssertEqual(groups.first { $0.org == .nvidia }?.optionCount, 2)
    }

    func testGroupsOrderFollowsOrgDeclaration() {
        let models = [
            makeModel(id: "all-minilm-l6-v2", name: "MiniLM"),
            makeModel(id: "qwen3-4b", name: "Qwen3 4B"),
            makeModel(id: "nemotron-mini-4b", name: "Nemotron Mini 4B"),
        ]

        let groups = ModelOrgCatalog.groups(from: models)
        XCTAssertEqual(groups.map(\.org), [.nvidia, .alibaba, .openSource])
    }

    private func makeModel(
        id: String,
        name: String,
        category: RAModelCategory = .language
    ) -> RAModelInfo {
        var model = RAModelInfo()
        model.id = id
        model.name = name
        model.category = category
        model.framework = .llamaCpp
        return model
    }
}
