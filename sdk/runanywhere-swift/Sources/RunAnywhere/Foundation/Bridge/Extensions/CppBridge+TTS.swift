//
//  CppBridge+TTS.swift
//  RunAnywhere SDK
//
//  TTS component bridge - manages C++ TTS component lifecycle
//

import CRACommons
import Foundation

// MARK: - TTS Component Bridge

extension CppBridge {

    /// TTS component manager
    /// Provides thread-safe access to the C++ TTS component
    public actor TTS {

        /// Shared TTS component instance
        public static let shared = TTS()

        private var handle: rac_handle_t?
        private var loadedVoiceId: String?
        private let logger = SDKLogger(category: "CppBridge.TTS")

        private init() {}

        // MARK: - Handle Management

        /// Get or create the TTS component handle
        public func getHandle() throws -> rac_handle_t {
            if let handle = handle {
                return handle
            }

            var newHandle: rac_handle_t?
            let result = rac_tts_component_create(&newHandle)
            guard result == RAC_SUCCESS, let handle = newHandle else {
                throw SDKError.tts(.notInitialized, "Failed to create TTS component: \(result)")
            }

            self.handle = handle
            logger.debug("TTS component created")
            return handle
        }

        // MARK: - State

        /// Check if a voice is loaded
        public var isLoaded: Bool {
            guard let handle = handle else { return false }
            return rac_tts_component_is_loaded(handle) == RAC_TRUE
        }

        /// Get the currently loaded voice ID
        public var currentVoiceId: String? { loadedVoiceId }

        // MARK: - Voice Lifecycle

        /// Load a TTS voice
        public func loadVoice(_ voicePath: String, voiceId: String) throws {
            let handle = try getHandle()
            let result = voicePath.withCString { pathPtr in
                rac_tts_component_load_voice(handle, pathPtr)
            }
            guard result == RAC_SUCCESS else {
                throw SDKError.tts(.modelLoadFailed, "Failed to load voice: \(result)")
            }
            loadedVoiceId = voiceId
            logger.info("TTS voice loaded: \(voiceId)")
        }

        /// Unload the current voice
        public func unload() {
            guard let handle = handle else { return }
            rac_tts_component_cleanup(handle)
            loadedVoiceId = nil
            logger.info("TTS voice unloaded")
        }

        /// Stop synthesis
        public func stop() {
            guard let handle = handle else { return }
            rac_tts_component_stop(handle)
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() {
            if let handle = handle {
                rac_tts_component_destroy(handle)
                self.handle = nil
                loadedVoiceId = nil
                logger.debug("TTS component destroyed")
            }
        }
    }
}
