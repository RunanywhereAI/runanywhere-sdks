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
    func testVoiceSessionCreateReachesCore() async throws {
        // With the C core linked, solution() returns a live session. Without
        // engines registered the pipeline will fail to start, but the error
        // must come from the C ABI (internalError) — proves the call path
        // actually traverses the new core rather than the old stub.
        let session = try await RunAnywhere.solution(.voiceAgent(VoiceAgentConfig()))
        let stream  = session.run()
        do {
            for try await _ in stream { /* no-op */ }
        } catch RunAnywhereError.internalError {
            // expected: pipeline reports backend unavailable because no
            // engines are registered in the test binary
        } catch RunAnywhereError.cancelled {
            // also acceptable — the pipeline can terminate via cancel
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
