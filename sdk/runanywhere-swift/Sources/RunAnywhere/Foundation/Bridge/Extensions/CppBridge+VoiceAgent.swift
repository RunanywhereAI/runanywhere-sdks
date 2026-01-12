//
//  CppBridge+VoiceAgent.swift
//  RunAnywhere SDK
//
//  VoiceAgent component bridge - manages C++ VoiceAgent component lifecycle
//

import CRACommons
import Foundation

// MARK: - VoiceAgent Component Bridge

extension CppBridge {

    /// VoiceAgent component manager
    /// Provides thread-safe access to the C++ VoiceAgent component
    public actor VoiceAgent {

        /// Shared VoiceAgent component instance
        public static let shared = VoiceAgent()

        private var handle: rac_voice_agent_handle_t?
        private let logger = SDKLogger(category: "CppBridge.VoiceAgent")

        private init() {}

        // MARK: - Handle Management

        /// Get or create the VoiceAgent handle
        /// Requires LLM, STT, TTS, and VAD components to be available
        public func getHandle() async throws -> rac_voice_agent_handle_t {
            if let handle = handle {
                return handle
            }

            // Get handles from all required components
            let llm = try await CppBridge.LLM.shared.getHandle()
            let stt = try await CppBridge.STT.shared.getHandle()
            let tts = try await CppBridge.TTS.shared.getHandle()
            let vad = try await CppBridge.VAD.shared.getHandle()

            var newHandle: rac_voice_agent_handle_t?
            let result = rac_voice_agent_create(llm, stt, tts, vad, &newHandle)

            guard result == RAC_SUCCESS, let handle = newHandle else {
                throw SDKError.voiceAgent(.initializationFailed, "Failed to create voice agent: \(result)")
            }

            self.handle = handle
            logger.info("Voice agent created")
            return handle
        }

        // MARK: - State

        /// Check if voice agent is ready
        public var isReady: Bool {
            guard let handle = handle else { return false }
            var ready: rac_bool_t = RAC_FALSE
            let result = rac_voice_agent_is_ready(handle, &ready)
            return result == RAC_SUCCESS && ready == RAC_TRUE
        }

        // MARK: - Cleanup

        /// Cleanup the voice agent
        public func cleanup() {
            guard let handle = handle else { return }
            rac_voice_agent_cleanup(handle)
            logger.info("Voice agent cleaned up")
        }

        /// Destroy the component
        public func destroy() {
            if let handle = handle {
                rac_voice_agent_cleanup(handle)
                rac_voice_agent_destroy(handle)
                self.handle = nil
                logger.debug("Voice agent destroyed")
            }
        }
    }
}
