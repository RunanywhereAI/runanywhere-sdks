// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import XCTest
@testable import RunAnywhereCore

final class RunAnywhereCoreTests: XCTestCase {

    func testVoiceAgentConfigDefaults() {
        let cfg = VoiceAgentConfig()
        XCTAssertEqual(cfg.llm, "qwen3-4b")
        XCTAssertEqual(cfg.stt, "whisper-base")
        XCTAssertEqual(cfg.tts, "kokoro")
        XCTAssertEqual(cfg.sampleRateHz, 16000)
        XCTAssertTrue(cfg.enableBargeIn)
    }

    func testRegistrationBuilderCollectsNames() {
        var builder = RegistrationBuilder()
        builder.register("llamacpp")
        builder.register("sherpa")
        XCTAssertEqual(builder.registeredEngines, ["llamacpp", "sherpa"])
    }

    @MainActor
    func testVoiceSessionCreateFailsWithoutCore() async throws {
        let session = try await RunAnywhere.solution(.voiceAgent(VoiceAgentConfig()))
        let stream  = session.run()
        do {
            for try await _ in stream { /* no-op */ }
            XCTFail("expected backendUnavailable error")
        } catch RunAnywhereError.backendUnavailable {
            // expected path while the C core is not linked in test builds
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
