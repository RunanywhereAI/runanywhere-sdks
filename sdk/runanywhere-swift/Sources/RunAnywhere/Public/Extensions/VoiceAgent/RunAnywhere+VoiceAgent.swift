//
//  RunAnywhere+VoiceAgent.swift
//  RunAnywhere SDK
//
//  Public API for Voice Agent operations (full voice pipeline).
//  Calls C++ directly via CppBridge for all operations.
//  Events are emitted by C++ layer - no Swift event emissions needed.
//
//  Architecture:
//  - Voice agent uses SHARED handles from individual components (STT/LLM/TTS/VAD)
//  - Models are loaded via the canonical lifecycle (`RAModelLoadRequest`)
//  - Voice agent is purely an orchestrator for the full voice pipeline
//  - All events (including state changes) are emitted from C++
//

import CRACommons
import Foundation

// MARK: - Voice Agent Operations

public extension RunAnywhere {

    /// Initialize the voice agent with configuration.
    static func initializeVoiceAgent(_ config: RAVoiceAgentComposeConfig) async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()
        _ = try await CppBridge.VoiceAgent.shared.initialize(config)
    }

    /// Process a complete voice turn through the proto C++ ABI.
    static func processVoiceTurn(_ audioData: Data) async throws -> RAVoiceAgentResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        guard await CppBridge.VoiceAgent.shared.isReady else {
            throw SDKException.voiceAgent(.notInitialized, "Voice agent not ready")
        }

        return try await CppBridge.VoiceAgent.shared.processVoiceTurnProto(audioData)
    }

    /// Open a stream of canonical `RAVoiceEvent` proto events for the active
    /// voice agent.
    ///
    /// Cancellation: breaking out of the consuming `for-await` loop (or
    /// cancelling the surrounding `Task`) tears down the C callback via
    /// `rac_voice_agent_set_proto_callback(handle, nullptr, nullptr)`.
    static func streamVoiceAgent() -> AsyncStream<RAVoiceEvent> {
        AsyncStream { continuation in
            let task = Task {
                guard isInitialized else {
                    continuation.finish()
                    return
                }

                let handle: rac_voice_agent_handle_t
                do {
                    handle = try await CppBridge.VoiceAgent.shared.getHandle()
                } catch {
                    continuation.finish()
                    return
                }

                let adapter = VoiceAgentStreamAdapter(handle: handle)
                for await event in adapter.stream() {
                    if Task.isCancelled { break }
                    continuation.yield(event)
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Cleanup voice agent resources.
    static func cleanupVoiceAgent() async {
        await CppBridge.VoiceAgent.shared.cleanup()
    }
}
