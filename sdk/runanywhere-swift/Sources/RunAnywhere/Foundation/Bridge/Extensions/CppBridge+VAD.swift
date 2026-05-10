//
//  CppBridge+VAD.swift
//  RunAnywhere SDK
//
//  VAD component bridge - manages C++ VAD component lifecycle.
//
//  Generic scaffolding (handle creation, isLoaded, unload, destroy)
//  lives in `CppBridge.ComponentActor`. VAD-specific surfaces kept here:
//   - `isInitialized` (separate from isLoaded; queries the component, not
//     the model slot)
//   - `unloadModel()` calls `rac_vad_component_unload` (which reverts to
//     energy-based VAD), distinct from the generic component cleanup.
//   - lifecycle methods (`initialize`/`start`/`stop`/`reset`) forwarding
//     to the lifecycle proto surface in CppBridge+ModalityProtoABI.swift
//   - "clear loadedModelId on retry" same-model fast-path.
//

import CRACommons
import Foundation

// MARK: - VAD Component Bridge

extension CppBridge {

    /// VAD component manager
    /// Provides thread-safe access to the C++ VAD component
    public actor VAD {

        /// Shared VAD component instance
        public static let shared = VAD()

        /// Generic scaffold (handle / isLoaded / loadModel / destroy).
        private let inner = ComponentActor(vtable: .vad)

        /// Mirror of the loaded model id used by the same-model fast-path.
        /// Must be cleared on every load attempt before the C call so a
        /// failed load doesn't poison a subsequent retry.
        private var loadedModelId: String?

        private let logger = SDKLogger(category: "CppBridge.VAD")

        private init() {}

        // MARK: - Handle Management

        /// Get or create the VAD component handle
        public func getHandle() async throws -> rac_handle_t {
            try await inner.getHandle()
        }

        // MARK: - State

        /// Check if VAD is initialized
        public var isInitialized: Bool {
            get async {
                guard let handle = await inner.existingHandle() else { return false }
                return rac_vad_component_is_initialized(handle) == RAC_TRUE
            }
        }

        // MARK: - Model Lifecycle

        /// Check if a VAD model is loaded
        public var isModelLoaded: Bool {
            get async { await inner.isLoaded }
        }

        /// Get the currently loaded model ID
        public var currentModelId: String? { loadedModelId }

        /// Load a VAD model (e.g., Silero VAD via ONNX backend)
        public func loadModel(
            _ modelPath: String,
            modelId: String,
            modelName: String
        ) async throws {
            // Skip if the same model is already loaded
            guard loadedModelId != modelId else {
                logger.info("VAD model already loaded: \(modelId)")
                return
            }

            // `rac_vad_component_load_model` unloads any previously loaded model
            // first. If the subsequent load fails, the C++ side is already
            // unloaded, so clear our mirror before the call so a retry isn't
            // skipped by the `loadedModelId != modelId` fast path above.
            loadedModelId = nil

            try await inner.loadModel(path: modelPath, id: modelId, name: modelName)
            loadedModelId = modelId
        }

        /// Unload the current VAD model (reverts to energy-based VAD)
        public func unloadModel() async {
            guard let handle = await inner.existingHandle() else { return }
            rac_vad_component_unload(handle)
            loadedModelId = nil
            await inner.markAssetLoaded(nil)
            logger.info("VAD model unloaded")
        }

        /// Load a VAD model from a `RAModelLoadResult` returned by the proto-backed
        /// lifecycle API. Mirrors `CppBridge.STT.loadModel(from:)` / `CppBridge.TTS.loadVoice(from:)`
        /// so the Swift component actor's `isLoaded` mirror tracks the lifecycle
        /// service's state after `RunAnywhere.loadModel(...)` returns `success=true`.
        /// Without this, VAD never connects to the lifecycle-loaded Silero model
        /// (SWIFT-VAD-001).
        func loadModel(from result: RAModelLoadResult, modelName: String? = nil) async throws {
            if loadedModelId == result.modelID {
                return
            }
            guard result.success else {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: result.errorMessage.isEmpty ? "VAD lifecycle load failed" : result.errorMessage,
                    category: .component
                )
            }
            // Pass the model id — `rac_vad_component_load_model` resolves through
            // `rac_get_model(arg)` → `rac_get_model_by_path(arg)` → basename,
            // and the registry already knows the resolved path from the lifecycle
            // load that just succeeded. Matches STT/TTS pattern.
            try await loadModel(
                result.modelID,
                modelId: result.modelID,
                modelName: modelName ?? result.modelID
            )
        }

        // MARK: - Lifecycle

        /// Initialize VAD — binds to the commons lifecycle VAD service.
        /// Returns the post-configure service state.
        @discardableResult
        public func initialize(_ config: RAVADConfiguration = RAVADConfiguration()) throws -> RAVADServiceState {
            let state = try configureLifecycle(config)
            logger.info("VAD initialized (lifecycle)")
            return state
        }

        /// Start VAD processing on the lifecycle-loaded service.
        @discardableResult
        public func start() throws -> RAVADServiceState {
            try startLifecycle()
        }

        /// Stop VAD processing on the lifecycle-loaded service.
        @discardableResult
        public func stop() throws -> RAVADServiceState {
            try stopLifecycle()
        }

        /// Reset VAD internal state (adaptive thresholds, speech segments, timing).
        @discardableResult
        public func reset() throws -> RAVADServiceState {
            let state = try resetLifecycle()
            logger.info("VAD state reset (lifecycle)")
            return state
        }

        /// Cleanup VAD
        public func cleanup() async {
            guard let handle = await inner.existingHandle() else { return }
            rac_vad_component_cleanup(handle)
            logger.info("VAD cleaned up")
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() async {
            await inner.destroy()
            loadedModelId = nil
        }
    }
}
