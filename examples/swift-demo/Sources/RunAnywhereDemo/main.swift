// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Swift CLI demo — exercises the full new RunAnywhereCore public API:
//   - SDKState init + auth + device registration
//   - PlatformAdapter install
//   - LLM / STT / TTS / VAD / Embed session create (errors expected,
//     proves dispatch path)
//   - VoiceSession event stream (expected error path)
//
// Run:
//   cd examples/swift-demo
//   swift run RunAnywhereDemo
//
// Expected output: each section prints ✓ for the code path reached,
// with the expected engine-unavailable errors proving the full dispatch
// chain is wired up.

import Foundation
import RunAnywhereCore

@main
@MainActor
struct Demo {
    static func main() async {
        print("RunAnywhereDemo — linking RunAnywhereCore xcframework")
        print("")

        await testSDKState()
        await testSessions()
        await testVoicePipeline()

        print("")
        print("All demos exercised the Swift → CRACommonsCore dispatch path.")
        exit(0)
    }

    static func testSDKState() async {
        print("--- SDKState ---")
        do {
            try SDKState.initialize(
                apiKey: "demo-api-key-1234567890",
                environment: .development,
                baseUrl: "https://dev.runanywhere.ai",
                deviceId: "demo-device-001",
                logLevel: .info)
            print("  ✓ initialize: env=\(SDKState.environment), base=\(SDKState.baseUrl)")

            try SDKState.setAuth(SDKState.Auth(
                accessToken: "demo-access",
                refreshToken: "demo-refresh",
                expiresAt: Int64(Date().timeIntervalSince1970) + 3600,
                userId: "demo-user"))
            print("  ✓ setAuth: authenticated=\(SDKState.isAuthenticated), user=\(SDKState.userId)")

            SDKState.setDeviceRegistered(true)
            print("  ✓ deviceRegistered=\(SDKState.isDeviceRegistered)")

            SDKState.clearAuth()
            SDKState.reset()
        } catch {
            print("  ✗ SDKState failed: \(error)")
        }
    }

    static func testSessions() async {
        print("--- Sessions (expect backendUnavailable — no engines registered) ---")
        do {
            _ = try LLMSession(modelId: "test", modelPath: "/nonexistent")
            print("  ✗ LLMSession unexpectedly succeeded")
        } catch RunAnywhereError.backendUnavailable {
            print("  ✓ LLMSession → backendUnavailable (dispatch reached)")
        } catch {
            print("  ~ LLMSession: \(error)")
        }

        do {
            _ = try STTSession(modelId: "test", modelPath: "/nonexistent")
            print("  ✗ STTSession unexpectedly succeeded")
        } catch RunAnywhereError.backendUnavailable {
            print("  ✓ STTSession → backendUnavailable")
        } catch {
            print("  ~ STTSession: \(error)")
        }

        do {
            _ = try TTSSession(modelId: "test", modelPath: "/nonexistent")
            print("  ✗ TTSSession unexpectedly succeeded")
        } catch RunAnywhereError.backendUnavailable {
            print("  ✓ TTSSession → backendUnavailable")
        } catch {
            print("  ~ TTSSession: \(error)")
        }

        do {
            _ = try VADSession(modelId: "test", modelPath: "/nonexistent")
            print("  ✗ VADSession unexpectedly succeeded")
        } catch RunAnywhereError.backendUnavailable {
            print("  ✓ VADSession → backendUnavailable")
        } catch {
            print("  ~ VADSession: \(error)")
        }

        do {
            _ = try EmbedSession(modelId: "test", modelPath: "/nonexistent")
            print("  ✗ EmbedSession unexpectedly succeeded")
        } catch RunAnywhereError.backendUnavailable {
            print("  ✓ EmbedSession → backendUnavailable")
        } catch {
            print("  ~ EmbedSession: \(error)")
        }
    }

    static func testVoicePipeline() async {
        print("--- VoiceSession event stream ---")
        do {
            let session = try await RunAnywhere.solution(.voiceAgent(
                VoiceAgentConfig(
                    llm: "qwen3-4b",
                    stt: "whisper-base",
                    tts: "kokoro",
                    vad: "silero-v5")))
            print("  ✓ session created — dispatching pipeline start")

            var eventCount = 0
            do {
                for try await event in session.run() {
                    eventCount += 1
                    switch event {
                    case .userSaid(let text, let isFinal):
                        print("    user[final=\(isFinal)]: \(text)")
                    case .assistantToken(let text, let kind, _):
                        print("    token[\(kind)]: \(text)")
                    case .audio(let pcm, let sr):
                        print("    audio: \(pcm.count) bytes @ \(sr) Hz")
                    case .interrupted(let reason):
                        print("    interrupted: \(reason)")
                    case .stateChange(let prev, let curr):
                        print("    state: \(prev) → \(curr)")
                    case .metrics(let e2e, _, _, _):
                        print("    metrics: e2e=\(e2e) ms")
                    case .vad(let kind):
                        print("    vad: \(kind)")
                    case .error(let err):
                        print("    error: \(err)")
                    }
                }
                print("  ✓ stream completed normally (\(eventCount) events)")
            } catch RunAnywhereError.backendUnavailable {
                print("  ✓ expected BACKEND_UNAVAILABLE (no engines registered)")
            } catch RunAnywhereError.cancelled {
                print("  ✓ pipeline cancelled")
            } catch {
                print("  ✓ call path reached core; expected error: \(error)")
            }
        } catch {
            print("  ✗ session creation failed: \(error)")
        }
    }
}
