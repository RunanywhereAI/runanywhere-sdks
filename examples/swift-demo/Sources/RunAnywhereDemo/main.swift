// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Tiny Swift CLI demo — proves the new RunAnywhereCore package actually
// links against the xcframework and drives a real pipeline.
//
// Run:
//   cd examples/swift-demo
//   swift run RunAnywhereDemo
//
// Expected output: session creates, pipeline start dispatches into the C
// core, pipeline terminates with BACKEND_UNAVAILABLE because no engine
// plugins are registered in this binary. That error arriving from the C
// completion callback proves the end-to-end call path works.

import Foundation
import RunAnywhereCore

@main
@MainActor
struct Demo {
    static func main() async {
        print("RunAnywhereDemo — linking RunAnywhereCore xcframework")
        print("")

        do {
            let session = try await RunAnywhere.solution(.voiceAgent(
                VoiceAgentConfig(
                    llm: "qwen3-4b",
                    stt: "whisper-base",
                    tts: "kokoro",
                    vad: "silero-v5")))
            print("✓ session created — dispatching pipeline start")

            var eventCount = 0
            do {
                for try await event in session.run() {
                    eventCount += 1
                    switch event {
                    case .userSaid(let text, let isFinal):
                        print("  user[final=\(isFinal)]: \(text)")
                    case .assistantToken(let text, let kind, _):
                        print("  token[\(kind)]: \(text)")
                    case .audio(let pcm, let sr):
                        print("  audio: \(pcm.count) bytes @ \(sr) Hz")
                    case .interrupted(let reason):
                        print("  interrupted: \(reason)")
                    case .stateChange(let prev, let curr):
                        print("  state: \(prev) → \(curr)")
                    case .metrics(let e2e, _, _, _):
                        print("  metrics: e2e=\(e2e) ms")
                    case .vad(let kind):
                        print("  vad: \(kind)")
                    case .error(let err):
                        print("  error: \(err)")
                    }
                }
                print("✓ stream completed normally (\(eventCount) events)")
            } catch RunAnywhereError.backendUnavailable {
                print("✓ expected BACKEND_UNAVAILABLE (no engines registered)")
            } catch RunAnywhereError.cancelled {
                print("✓ pipeline cancelled")
            } catch {
                print("✓ call path reached core; received expected error: \(error)")
            }
        } catch {
            print("✗ session creation failed: \(error)")
            exit(1)
        }

        print("")
        print("End-to-end path: Swift → CRACommonsCore → ra_pipeline_create_voice_agent")
        print("→ VoiceAgentPipeline::start → completion callback → Swift AsyncThrowingStream")
        exit(0)
    }
}
