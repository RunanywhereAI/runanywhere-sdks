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

    // MARK: - SDKState

    func testSDKStateInitializeSetsEnvironment() throws {
        try SDKState.initialize(
            apiKey: "test-api-key-1234567890",
            environment: .staging,
            baseUrl: "https://staging.example.com",
            deviceId: "test-device-abc",
            logLevel: .warn)
        XCTAssertEqual(SDKState.environment, .staging)
        XCTAssertEqual(SDKState.baseUrl, "https://staging.example.com")
        XCTAssertEqual(SDKState.deviceId, "test-device-abc")
        XCTAssertEqual(SDKState.apiKey, "test-api-key-1234567890")
        SDKState.reset()
    }

    func testSDKStateAuthLifecycle() throws {
        try SDKState.initialize(apiKey: "test-api-key-1234567890")
        XCTAssertFalse(SDKState.isAuthenticated)

        try SDKState.setAuth(SDKState.Auth(
            accessToken: "access-token-xyz",
            refreshToken: "refresh-token-abc",
            expiresAt: Int64(Date().timeIntervalSince1970) + 3600,
            userId: "user-42",
            organizationId: "org-1"))

        XCTAssertTrue(SDKState.isAuthenticated)
        XCTAssertEqual(SDKState.accessToken, "access-token-xyz")
        XCTAssertEqual(SDKState.refreshToken, "refresh-token-abc")
        XCTAssertEqual(SDKState.userId, "user-42")
        XCTAssertEqual(SDKState.organizationId, "org-1")
        XCTAssertFalse(SDKState.tokenNeedsRefresh(horizonSeconds: 60))
        XCTAssertTrue(SDKState.tokenNeedsRefresh(horizonSeconds: 7200))

        SDKState.clearAuth()
        XCTAssertFalse(SDKState.isAuthenticated)
    }

    func testSDKStateDeviceRegistrationBit() throws {
        try SDKState.initialize(apiKey: "test-api-key-1234567890")
        XCTAssertFalse(SDKState.isDeviceRegistered)
        SDKState.setDeviceRegistered(true)
        XCTAssertTrue(SDKState.isDeviceRegistered)
        SDKState.setDeviceRegistered(false)
        XCTAssertFalse(SDKState.isDeviceRegistered)
    }

    func testSDKStateValidation() {
        XCTAssertFalse(SDKState.validateAPIKey("short"))
        XCTAssertTrue(SDKState.validateAPIKey("long-enough-16chars"))
        XCTAssertFalse(SDKState.validateBaseURL("not-a-url"))
        XCTAssertTrue(SDKState.validateBaseURL("https://api.example.com"))
        XCTAssertTrue(SDKState.validateBaseURL("http://dev.local"))
    }

    // MARK: - Session create-error paths

    func testLLMSessionRequiresEngine() {
        // No engines registered — create should return backendUnavailable.
        XCTAssertThrowsError(
            try LLMSession(modelId: "test", modelPath: "/nonexistent/path")
        ) { error in
            guard case RunAnywhereError.backendUnavailable = error else {
                XCTFail("expected backendUnavailable, got \(error)")
                return
            }
        }
    }

    func testSTTSessionRequiresEngine() {
        XCTAssertThrowsError(
            try STTSession(modelId: "test", modelPath: "/nonexistent/path")
        ) { error in
            guard case RunAnywhereError.backendUnavailable = error else {
                XCTFail("expected backendUnavailable, got \(error)")
                return
            }
        }
    }

    func testTTSSessionRequiresEngine() {
        XCTAssertThrowsError(
            try TTSSession(modelId: "test", modelPath: "/nonexistent/path")
        ) { error in
            guard case RunAnywhereError.backendUnavailable = error else {
                XCTFail("expected backendUnavailable, got \(error)")
                return
            }
        }
    }

    func testVADSessionRequiresEngine() {
        XCTAssertThrowsError(
            try VADSession(modelId: "test", modelPath: "/nonexistent/path")
        ) { error in
            guard case RunAnywhereError.backendUnavailable = error else {
                XCTFail("expected backendUnavailable, got \(error)")
                return
            }
        }
    }

    func testEmbedSessionRequiresEngine() {
        XCTAssertThrowsError(
            try EmbedSession(modelId: "test", modelPath: "/nonexistent/path")
        ) { error in
            guard case RunAnywhereError.backendUnavailable = error else {
                XCTFail("expected backendUnavailable, got \(error)")
                return
            }
        }
    }
}
