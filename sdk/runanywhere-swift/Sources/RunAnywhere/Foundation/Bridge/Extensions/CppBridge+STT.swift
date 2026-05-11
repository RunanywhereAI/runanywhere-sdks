//
//  CppBridge+STT.swift
//  RunAnywhere SDK
//
//  STT component bridge - manages C++ STT component lifecycle.
//
//  Generic scaffolding (handle creation, isLoaded, unload, destroy)
//  lives in `CppBridge.ComponentActor`. STT-specific surfaces kept here:
//  `supportsStreaming`, the `framework:`-aware `loadModel(...)` variant
//  (which configures the component before loading), and the same-model
//  fast-path.
//

import CRACommons
import Foundation

// MARK: - STT Component Bridge

extension CppBridge {

    /// STT component manager
    /// Provides thread-safe access to the C++ STT component
    public actor STT {

        /// Shared STT component instance
        public static let shared = STT()

        /// Generic scaffold (handle / isLoaded / loadModel / unload / destroy).
        private let inner = ComponentActor(vtable: .stt)

        /// Mirror of the inner actor's loadedAssetId for the same-model
        /// fast-path; allows the fast-path check without awaiting the
        /// inner actor first.
        private var loadedModelId: String?

        private let logger = SDKLogger(category: "CppBridge.STT")

        private init() {}

        // MARK: - Handle Management

        /// Get or create the STT component handle
        public func getHandle() async throws -> rac_handle_t {
            try await inner.getHandle()
        }

        // MARK: - State

        /// Check if a model is loaded
        public var isLoaded: Bool {
            get async { await inner.isLoaded }
        }

        /// Get the currently loaded model ID
        public var currentModelId: String? { loadedModelId }

        /// Check if streaming is supported
        public var supportsStreaming: Bool {
            get async {
                guard let handle = await inner.existingHandle() else { return false }
                return rac_stt_component_supports_streaming(handle) == RAC_TRUE
            }
        }

        // MARK: - Model Lifecycle

        /// Load an STT model
        public func loadModel(
            _ modelPath: String,
            modelId: String,
            modelName: String,
            framework: rac_inference_framework_t = RAC_FRAMEWORK_UNKNOWN
        ) async throws {
            // Skip if the same model is already loaded — avoids redundant
            // backend model-compilation/load work.
            guard loadedModelId != modelId else {
                logger.info("Model already loaded: \(modelId)")
                return
            }

            let handle = try await inner.getHandle()

            // Configure the component with the correct framework so telemetry events
            // carry the real framework value instead of "unknown".
            if framework != RAC_FRAMEWORK_UNKNOWN {
                var config = RAC_STT_CONFIG_DEFAULT
                config.preferred_framework = Int32(framework.rawValue)
                let configResult = rac_stt_component_configure(handle, &config)
                if configResult != RAC_SUCCESS {
                    logger.warning("Failed to configure STT framework: \(configResult)")
                }
            }

            try await inner.loadModel(path: modelPath, id: modelId, name: modelName)
            loadedModelId = modelId
        }

        /// Unload the current model
        public func unload() async {
            await inner.unload()
            loadedModelId = nil
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() async {
            await inner.destroy()
            loadedModelId = nil
        }
    }
}
