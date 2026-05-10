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
                throw SDKException(code: .notInitialized, message: "Failed to create TTS component: \(result)", category: .component)
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
        public func loadVoice(_ voicePath: String, voiceId: String, voiceName: String) throws {
            let handle = try getHandle()
            let result = voicePath.withCString { pathPtr in
                voiceId.withCString { idPtr in
                    voiceName.withCString { namePtr in
                        rac_tts_component_load_voice(handle, pathPtr, idPtr, namePtr)
                    }
                }
            }
            guard result == RAC_SUCCESS else {
                throw SDKException(code: .modelLoadFailed, message: "Failed to load voice: \(result)", category: .component)
            }
            loadedVoiceId = voiceId
            logger.info("TTS voice loaded: \(voiceId)")
        }

        /// Load a TTS voice from a `RAModelLoadResult` returned by the proto-backed
        /// lifecycle API. Mirrors `CppBridge.VLM.loadModel(from:)` so the Swift
        /// component actor's `isLoaded` flag tracks the lifecycle service's state
        /// after `RunAnywhere.loadModel(...)` returns `success=true`.
        func loadVoice(from result: RAModelLoadResult, voiceName: String? = nil) throws {
            if loadedVoiceId == result.modelID {
                return
            }
            guard result.success else {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: result.errorMessage.isEmpty ? "TTS lifecycle load failed" : result.errorMessage,
                    category: .component
                )
            }

            // Pass model id (not resolved path) so `rac_tts_create` registry
            // lookup resolves the canonical local path. Same pattern as the
            // STT loadModel(from:) method — the lifecycle load (commons)
            // has already populated the registry entry's local_path.
            try loadVoice(
                result.modelID,
                voiceId: result.modelID,
                voiceName: voiceName ?? result.modelID
            )
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
