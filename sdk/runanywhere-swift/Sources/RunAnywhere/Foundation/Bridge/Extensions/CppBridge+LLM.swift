//
//  CppBridge+LLM.swift
//  RunAnywhere SDK
//
//  LLM component bridge - manages C++ LLM component lifecycle.
//
//  All generic scaffolding (handle creation, isLoaded, loadModel,
//  unload, destroy) lives in `CppBridge.ComponentActor`; this file
//  only adds the LLM-specific `cancel()` op on top.
//

import CRACommons

// MARK: - LLM Component Bridge

extension CppBridge {

    /// LLM component manager
    /// Provides thread-safe access to the C++ LLM component
    public actor LLM {

        /// Shared LLM component instance
        public static let shared = LLM()

        /// Generic scaffold (handle / isLoaded / loadModel / unload / destroy).
        private let inner = ComponentActor(vtable: .llm)

        private init() {}

        // MARK: - State

        /// Check if a model is loaded
        public var isLoaded: Bool {
            get async { await inner.isLoaded }
        }

        /// Get the currently loaded model ID
        public var currentModelId: String? {
            get async { await inner.currentAssetId }
        }

        // MARK: - Model Lifecycle

        /// Load an LLM model
        public func loadModel(_ modelPath: String, modelId: String, modelName: String) async throws {
            try await inner.loadModel(path: modelPath, id: modelId, name: modelName)
        }

        /// Unload the current model
        public func unload() async {
            await inner.unload()
        }

        /// Cancel ongoing generation
        public func cancel() async {
            guard let handle = await inner.existingHandle() else { return }
            rac_llm_component_cancel(handle.rawValue)
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() async {
            await inner.destroy()
        }
    }
}
