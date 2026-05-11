//
//  CppBridge+TTS.swift
//  RunAnywhere SDK
//
//  TTS component bridge - manages C++ TTS component lifecycle.
//
//  Generic scaffolding (handle creation, unload, destroy) lives in
//  `CppBridge.ComponentActor`. TTS-specific surfaces kept here:
//  the `loadVoice` voice-terminology wrapper, the `loadVoice(from:)`
//  lifecycle adapter, and `stop()` to interrupt synthesis.
//  The public `isLoaded` accessor was removed in Wave 6C (T13) — call
//  sites now query `RunAnywhere.currentModel(category: .speechSynthesis)`
//  on the lifecycle as the single source of truth.
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

        /// Generic scaffold (handle / isLoaded / loadModel / unload / destroy).
        /// TTS's vtable.loadModel forwards to `rac_tts_component_load_voice`.
        private let inner = ComponentActor(vtable: .tts)

        private let logger = SDKLogger(category: "CppBridge.TTS")

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

        /// Load a TTS voice from a `RAModelLoadResult` returned by the proto-backed
        /// lifecycle API. Mirrors `CppBridge.VLM.loadModel(from:)` so the Swift
        /// component actor's `isLoaded` flag tracks the lifecycle service's state
        /// after `RunAnywhere.loadModel(...)` returns `success=true`.
        func loadVoice(from result: RAModelLoadResult, voiceName: String? = nil) async throws {
            if await inner.currentAssetId == result.modelID {
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
            try await loadVoice(
                result.modelID,
                voiceId: result.modelID,
                voiceName: voiceName ?? result.modelID
            )
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
