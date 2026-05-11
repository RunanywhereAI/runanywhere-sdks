//
//  ComponentActor.swift
//  RunAnywhere SDK
//
//  Generic actor scaffold for a single C++ component (LLM / STT / TTS /
//  VAD / VLM). The variable parts are supplied via `ComponentVTable`;
//  this type owns the rest:
//
//   - lazy handle creation (one C handle per component instance)
//   - `isLoaded` proxy across the C ABI
//   - `loadModel(...)` taking 3 Swift strings, bridged via `withCString`
//   - `unload()` (cleanup) and `destroy()`
//   - actor isolation guarantees concurrency safety without locks
//   - structured logging keyed by the proto component name
//
//  VoiceAgent does NOT use this scaffold — its handle type differs
//  (`rac_voice_agent_handle_t`) and its create-op is async + composite.
//

import CRACommons
import Foundation

extension CppBridge {

    /// Generic component actor: holds one opaque C++ handle and routes
    /// all calls through a `ComponentVTable`.
    ///
    /// Each modality wraps this in a typealias / facade actor that
    /// exposes the modality-specific extras (cancel/stop/streaming
    /// flags, lifecycle-result loaders, etc.) on top of the shared
    /// scaffold.
    public actor ComponentActor {

        // MARK: - Identity

        /// The vtable describing the wrapped C++ component.
        public let vtable: ComponentVTable

        // MARK: - State

        /// Opaque C handle — nil until first `getHandle()` succeeds, and
        /// nil again after `destroy()`.
        private var handle: rac_handle_t?

        /// Currently-loaded model/voice id (the "loaded asset id" — TTS
        /// calls it a voice id, others call it a model id; the actor is
        /// agnostic). Cleared on `unload()` and `destroy()`.
        private var loadedAssetId: String?

        /// Once true, the actor has been destroyed and is no longer
        /// usable; further `getHandle()` calls throw.
        private var isClosed = false

        private let logger: SDKLogger

        // MARK: - Init

        public init(vtable: ComponentVTable) {
            self.vtable = vtable
            self.logger = SDKLogger(category: "CppBridge.\(vtable.component.label)")
        }

        // MARK: - Handle Management

        /// Get or lazily create the underlying C handle.
        public func getHandle() throws -> rac_handle_t {
            if let handle = handle {
                return handle
            }
            if isClosed {
                throw SDKException(
                    code: .notInitialized,
                    message: "\(vtable.component.label) component is shut down",
                    category: .component
                )
            }

            var newHandle: rac_handle_t?
            let status = vtable.create(&newHandle)
            guard status == RAC_SUCCESS, let h = newHandle else {
                throw SDKException(
                    code: .notInitialized,
                    message: "Failed to create \(vtable.component.label) component: \(status)",
                    category: .component
                )
            }
            self.handle = h
            logger.debug("\(vtable.component.label) component created")
            return h
        }

        // MARK: - State queries

        /// Whether the component currently has a model/voice loaded.
        public var isLoaded: Bool {
            guard let handle = handle else { return false }
            return vtable.isLoaded(handle) == RAC_TRUE
        }

        /// Currently-loaded asset id (model id, voice id, …). `nil` if
        /// no asset is loaded.
        public var currentAssetId: String? { loadedAssetId }

        /// Whether `destroy()` has already been called. Used by callers
        /// that want to skip re-init after shutdown.
        public var isShutDown: Bool { isClosed }

        /// Read-only access to the raw handle without triggering creation.
        /// Returns `nil` if the handle has not been created yet.
        public func existingHandle() -> rac_handle_t? { handle }

        // MARK: - Lifecycle

        /// Load a model/voice given `(path, id, name)`. Throws if the
        /// vtable has no `loadModel` slot (e.g. modalities with
        /// non-standard load signatures).
        public func loadModel(
            path: String,
            id: String,
            name: String
        ) throws {
            guard let load = vtable.loadModel else {
                throw SDKException(
                    code: .notImplemented,
                    message: "\(vtable.component.label) does not support generic loadModel",
                    category: .component
                )
            }
            let handle = try getHandle()
            let status = path.withCString { pathPtr in
                id.withCString { idPtr in
                    name.withCString { namePtr in
                        load(handle, pathPtr, idPtr, namePtr)
                    }
                }
            }
            guard status == RAC_SUCCESS else {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: "Failed to load \(vtable.component.label) model: \(status)",
                    category: .component
                )
            }
            loadedAssetId = id
            logger.info("\(vtable.component.label) model loaded: \(id)")
        }

        /// Update the locally-tracked loaded asset id without touching
        /// the C side. Used by modality-specific load paths that bypass
        /// this scaffold's `loadModel` (e.g. modalities with non-standard
        /// load signatures). Currently only VAD calls this to clear the
        /// asset id on unload.
        public func markAssetLoaded(_ id: String?) {
            loadedAssetId = id
        }

        /// Unload the currently-loaded model/voice. Safe to call when
        /// nothing is loaded or the handle hasn't been created.
        public func unload() {
            guard let handle = handle else { return }
            vtable.cleanup(handle)
            loadedAssetId = nil
            logger.info("\(vtable.component.label) model unloaded")
        }

        /// Destroy the component, releasing C resources and marking the
        /// actor closed. Subsequent `getHandle()` throws.
        public func destroy() {
            if let handle = handle {
                vtable.destroy(handle)
                logger.debug("\(vtable.component.label) component destroyed")
            }
            handle = nil
            loadedAssetId = nil
            isClosed = true
        }
    }
}

// MARK: - Label helper

private extension RASDKComponent {
    /// Short human-friendly label used in log categories and error
    /// messages. Avoids depending on `description` which has its own
    /// proto-generated formatting.
    var label: String {
        switch self {
        case .llm:                return "LLM"
        case .stt:                return "STT"
        case .tts:                return "TTS"
        case .vad:                return "VAD"
        case .vlm:                return "VLM"
        case .voiceAgent:         return "VoiceAgent"
        case .diffusion:          return "Diffusion"
        case .rag:                return "RAG"
        case .embeddings:         return "Embeddings"
        case .wakeword:           return "Wakeword"
        case .speakerDiarization: return "SpeakerDiarization"
        case .unspecified, .UNRECOGNIZED:
            return "UnknownComponent"
        }
    }
}
