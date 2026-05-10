//
//  CppBridge+VAD.swift
//  RunAnywhere SDK
//
//  VAD component bridge - manages C++ VAD component lifecycle
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

        private var handle: rac_handle_t?
        private var loadedModelId: String?
        private let logger = SDKLogger(category: "CppBridge.VAD")

        private init() {}

        // MARK: - Handle Management

        /// Get or create the VAD component handle
        public func getHandle() throws -> rac_handle_t {
            if let handle = handle {
                return handle
            }

            var newHandle: rac_handle_t?
            let result = rac_vad_component_create(&newHandle)
            guard result == RAC_SUCCESS, let handle = newHandle else {
                throw SDKException(code: .notInitialized, message: "Failed to create VAD component: \(result)", category: .component)
            }

            self.handle = handle
            logger.debug("VAD component created")
            return handle
        }

        // MARK: - State

        /// Check if VAD is initialized
        public var isInitialized: Bool {
            guard let handle = handle else { return false }
            return rac_vad_component_is_initialized(handle) == RAC_TRUE
        }

        // MARK: - Model Lifecycle

        /// Check if a VAD model is loaded
        public var isModelLoaded: Bool {
            guard let handle = handle else { return false }
            return rac_vad_component_is_loaded(handle) == RAC_TRUE
        }

        /// Get the currently loaded model ID
        public var currentModelId: String? { loadedModelId }

        /// Load a VAD model (e.g., Silero VAD via ONNX backend)
        public func loadModel(
            _ modelPath: String,
            modelId: String,
            modelName: String
        ) throws {
            // Skip if the same model is already loaded
            guard loadedModelId != modelId else {
                logger.info("VAD model already loaded: \(modelId)")
                return
            }

            let handle = try getHandle()

            // `rac_vad_component_load_model` unloads any previously loaded model
            // first. If the subsequent load fails, the C++ side is already
            // unloaded, so clear our mirror before the call so a retry isn't
            // skipped by the `loadedModelId != modelId` fast path above.
            loadedModelId = nil

            let result = modelPath.withCString { pathPtr in
                modelId.withCString { idPtr in
                    modelName.withCString { namePtr in
                        rac_vad_component_load_model(handle, pathPtr, idPtr, namePtr)
                    }
                }
            }
            guard result == RAC_SUCCESS else {
                throw SDKException(code: .modelLoadFailed, message: "Failed to load VAD model: \(result)", category: .component)
            }
            loadedModelId = modelId
            logger.info("VAD model loaded: \(modelId)")
        }

        /// Unload the current VAD model (reverts to energy-based VAD)
        public func unloadModel() {
            guard let handle = handle else { return }
            rac_vad_component_unload(handle)
            loadedModelId = nil
            logger.info("VAD model unloaded")
        }

        /// Load a VAD model from a `RAModelLoadResult` returned by the proto-backed
        /// lifecycle API. Mirrors `CppBridge.STT.loadModel(from:)` / `CppBridge.TTS.loadVoice(from:)`
        /// so the Swift component actor's `isLoaded` mirror tracks the lifecycle
        /// service's state after `RunAnywhere.loadModel(...)` returns `success=true`.
        /// Without this, VAD never connects to the lifecycle-loaded Silero model
        /// (SWIFT-VAD-001).
        func loadModel(from result: RAModelLoadResult, modelName: String? = nil) throws {
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
            try loadModel(
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
        public func cleanup() {
            guard let handle = handle else { return }
            rac_vad_component_cleanup(handle)
            logger.info("VAD cleaned up")
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() {
            if let handle = handle {
                rac_vad_component_destroy(handle)
                self.handle = nil
                loadedModelId = nil
                logger.debug("VAD component destroyed")
            }
        }
    }
}
