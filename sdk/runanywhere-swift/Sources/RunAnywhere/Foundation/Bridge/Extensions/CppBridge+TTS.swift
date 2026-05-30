//
//  CppBridge+TTS.swift
//  RunAnywhere SDK
//
//  TTS component bridge - manages C++ TTS component lifecycle.
//
//  Generic scaffolding (handle creation, unload, destroy) lives in
//  `CppBridge.ComponentActor`. TTS-specific surfaces kept here:
//  the `loadVoice` voice-terminology wrapper and `stop()` to interrupt
//  synthesis.
//  The public `isLoaded` accessor was removed — call sites now query
//  `RunAnywhere.currentModel(category: .speechSynthesis)` on the
//  lifecycle as the single source of truth.
//

import CRACommons

// MARK: - TTS Component Bridge

extension CppBridge {

    /// TTS component manager
    /// Provides thread-safe access to the C++ TTS component
    public actor TTS {

        /// Shared TTS component instance
        public static let shared = TTS()

        /// Generic scaffold (handle / isLoaded / loadModel / unload / destroy).
        /// TTS's vtable.loadModel forwards to `rac_tts_component_load_voice`.
        private let inner = ComponentActor(vtable: .tts)

        private init() {}

        // MARK: - Handle Management

        /// Get or create the TTS component handle
        public func getHandle() async throws -> rac_handle_t {
            try await inner.getHandle()
        }

        // MARK: - State

        /// Get the currently loaded voice ID
        public var currentVoiceId: String? {
            get async { await inner.currentAssetId }
        }

        // MARK: - Voice Lifecycle

        /// Load a TTS voice
        public func loadVoice(_ voicePath: String, voiceId: String, voiceName: String) async throws {
            try await inner.loadModel(path: voicePath, id: voiceId, name: voiceName)
        }

        /// Unload the current voice
        public func unload() async {
            await inner.unload()
        }

        /// Stop synthesis
        public func stop() async {
            guard let handle = await inner.existingHandle() else { return }
            rac_tts_component_stop(handle)
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() async {
            await inner.destroy()
        }
    }
}
