//
//  CppBridge+VoiceAgent.swift
//  RunAnywhere SDK
//
//  VoiceAgent component bridge - manages C++ VoiceAgent component lifecycle
//

import CRACommons

// MARK: - VoiceAgent Component Bridge

extension CppBridge {

    /// Voice-agent pointer owned by the shared actor. Commons synchronizes its
    /// internal pipeline; the wrapper prevents the raw pointer itself from
    /// crossing Swift concurrency boundaries.
    struct VoiceAgentHandle: @unchecked Sendable {
        let rawValue: rac_voice_agent_handle_t
    }

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
        func getHandle() async throws -> VoiceAgentHandle {
            if let handle = handle {
                return VoiceAgentHandle(rawValue: handle)
            }

            var newHandle: rac_voice_agent_handle_t?
            let result = rac_voice_agent_create_standalone(&newHandle)

            guard result == RAC_SUCCESS, let handle = newHandle else {
                throw SDKException(code: .initializationFailed, message: "Failed to create voice agent: \(result)", category: .component)
            }

            self.handle = handle
            logger.info("Voice agent created")
            return VoiceAgentHandle(rawValue: handle)
        }

        private func requireExistingHandle() throws -> rac_voice_agent_handle_t {
            guard let handle else {
                throw SDKException(code: .notInitialized, message: "Voice agent not initialized", category: .component)
            }
            return handle
        }

        func initialize(_ config: RAVoiceAgentComposeConfig) throws -> RAVoiceAgentComponentStates {
            try initialize(handle: requireExistingHandle(), config)
        }

        func componentStates() throws -> RAVoiceAgentComponentStates {
            try componentStatesProto(handle: requireExistingHandle())
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
