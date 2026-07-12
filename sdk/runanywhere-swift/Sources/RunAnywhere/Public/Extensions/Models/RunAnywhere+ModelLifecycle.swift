//
//  RunAnywhere+ModelLifecycle.swift
//  RunAnywhere SDK
//
//  Public proto-backed model/component lifecycle API.
//
//  The C++ lifecycle service is the canonical source of truth for "is this
//  modality loaded". Inference paths (voice_agent.cpp and every rac_*_proto
//  entry point, including VLM generate / stream / cancel) consult
//  it via `acquire_lifecycle_*`; Swift readiness checks (TTS / VLM
//  `isLoaded`) consult it via `RACurrentModelRequest`. Per-component Swift
//  direct-handle introspection APIs and are not consulted for inference or
//  compose-readiness.
//


public extension RunAnywhere {
    static func loadModel(_ request: RAModelLoadRequest) async -> RAModelLoadResult {
        guard isInitialized else {
            var result = RAModelLoadResult()
            result.success = false
            result.modelID = request.modelID
            result.category = request.category
            result.framework = request.framework
            result.errorMessage = "SDK not initialized"
            return result
        }
        try? await ensureServicesReady()
        let result = await CppBridge.ModelLifecycle.load(request)
        if result.success {
            let modelID = result.modelID.isEmpty ? request.modelID : result.modelID
            SDKLogger.models.info("Model load succeeded for \(modelID)")
        }
        return result
    }

    static func unloadModel(_ request: RAModelUnloadRequest) async -> RAModelUnloadResult {
        guard isInitialized else {
            var result = RAModelUnloadResult()
            result.success = false
            result.errorMessage = "SDK not initialized"
            return result
        }
        return CppBridge.ModelLifecycle.unload(request)
    }

    static func currentModel(_ request: RACurrentModelRequest = RACurrentModelRequest()) -> RACurrentModelResult {
        CppBridge.ModelLifecycle.currentModel(request)
    }

    internal static func loadedModelSnapshot(
        category: RAModelCategory,
        includeModelMetadata: Bool = false
    ) -> RACurrentModelResult {
        var request = RACurrentModelRequest()
        request.category = category
        request.includeModelMetadata = includeModelMetadata
        return currentModel(request)
    }

    internal static func firstLoadedModelSnapshot(
        categories: [RAModelCategory],
        includeModelMetadata: Bool = false
    ) -> RACurrentModelResult? {
        for category in categories {
            let result = loadedModelSnapshot(category: category, includeModelMetadata: includeModelMetadata)
            if result.found {
                return result
            }
        }
        return nil
    }

    /// Full `RAModelInfo` for the model currently loaded under `category`,
    /// or `nil` when nothing is loaded for it.
    ///
    /// Wraps `currentModel(_:)` with `includeModelMetadata = true` so callers
    /// (e.g. view models surfacing the loaded model's display name / framework)
    /// get the populated proto instead of reconstructing a stand-in.
    static func modelInfoForCategory(_ category: RAModelCategory) -> RAModelInfo? {
        let result = loadedModelSnapshot(category: category, includeModelMetadata: true)
        guard result.found, result.hasModel else { return nil }
        return result.model
    }

    static func componentLifecycleSnapshot(
        _ component: RASDKComponent
    ) -> RAComponentLifecycleSnapshot? {
        CppBridge.ModelLifecycle.componentSnapshot(component: component)
    }
}
