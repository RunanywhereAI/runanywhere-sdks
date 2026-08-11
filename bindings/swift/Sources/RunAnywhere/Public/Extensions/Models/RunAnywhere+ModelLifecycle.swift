//
//  RunAnywhere+ModelLifecycle.swift
//  RunAnywhere SDK
//
//  Proto-backed model/component lifecycle plumbing plus the deprecated flat
//  verbs it used to be reached through. The v3 surface reaches this through
//  `RunAnywhere.models`.
//
//  The C++ lifecycle service is the canonical source of truth for "is this
//  modality loaded". Inference paths (voice_agent.cpp and every rac_*_proto
//  entry point, including VLM generate / stream / cancel) consult it via
//  `acquire_lifecycle_*`; Swift readiness checks consult it via
//  `RACurrentModelRequest`.
//

extension RunAnywhere {

    // MARK: - Internal plumbing

    internal static func performLoad(_ request: RAModelLoadRequest) async -> RAModelLoadResult {
        guard isReady else {
            var result = RAModelLoadResult()
            result.modelID = request.modelID
            result.category = request.category
            result.framework = request.framework
            result.error = RASDKError.make(
                code: .notInitialized,
                message: "SDK not initialized",
                category: .component
            )
            return result
        }
        try? await ensureServicesReady()
        let result = await CppBridge.ModelLifecycle.load(request)
        if !result.hasError {
            let modelID = result.modelID.isEmpty ? request.modelID : result.modelID
            SDKLogger.models.info("Model load succeeded for \(modelID)")
        }
        return result
    }

    internal static func performUnload(_ request: RAModelUnloadRequest) async -> RAModelUnloadResult {
        guard isReady else {
            var result = RAModelUnloadResult()
            result.error = RASDKError.make(
                code: .notInitialized,
                message: "SDK not initialized",
                category: .component
            )
            return result
        }
        let result = CppBridge.ModelLifecycle.unload(request)
        if !result.hasError {
            await CppBridge.Diarization.shared.reconcileCanonicalUnload(
                request: request,
                result: result
            )
        }
        return result
    }

    internal static func loadedModelSnapshot(
        category: RAModelCategory,
        includeModelMetadata: Bool = false
    ) -> RACurrentModelResult {
        var request = RACurrentModelRequest()
        request.category = category
        request.includeModelMetadata = includeModelMetadata
        return CppBridge.ModelLifecycle.currentModel(request)
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

    // MARK: - Deprecated flat verbs

    @available(*, deprecated, renamed: "models.load(id:options:)")
    public static func loadModel(_ request: RAModelLoadRequest) async -> RAModelLoadResult {
        await performLoad(request)
    }

    @available(*, deprecated, renamed: "models.unload(category:)")
    public static func unloadModel(_ request: RAModelUnloadRequest) async -> RAModelUnloadResult {
        await performUnload(request)
    }

    @available(*, deprecated, renamed: "models.state()")
    public static func currentModel(_ request: RACurrentModelRequest = RACurrentModelRequest()) -> RACurrentModelResult {
        CppBridge.ModelLifecycle.currentModel(request)
    }

    /// Full `RAModelInfo` for the model currently loaded under `category`.
    @available(*, deprecated, renamed: "models.state()")
    public static func modelInfoForCategory(_ category: RAModelCategory) -> RAModelInfo? {
        let result = loadedModelSnapshot(category: category, includeModelMetadata: true)
        guard result.found, result.hasModel else { return nil }
        return result.model
    }

    /// Per-component lifecycle snapshot straight from commons.
    public static func componentLifecycleSnapshot(
        _ component: RASDKComponent
    ) -> RAComponentLifecycleSnapshot? {
        CppBridge.ModelLifecycle.componentSnapshot(component: component)
    }
}
