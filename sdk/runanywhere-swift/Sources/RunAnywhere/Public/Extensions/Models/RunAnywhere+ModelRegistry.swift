//
//  RunAnywhere+ModelRegistry.swift
//  RunAnywhere SDK
//
//  Proto-backed model registry plumbing plus the deprecated flat verbs it used
//  to be reached through. The v3 surface reaches this through
//  `RunAnywhere.models`.
//

extension RunAnywhere {

    // MARK: - Internal plumbing

    internal static func performList(_ request: RAModelListRequest = RAModelListRequest()) async -> RAModelListResult {
        guard isReady else {
            var result = RAModelListResult()
            result.error = RASDKError.make(
                code: .notInitialized,
                message: "SDK not initialized",
                category: .component
            )
            return result
        }
        try? await ensureServicesReady()
        return await CppBridge.ModelRegistry.shared.list(request)
    }

    internal static func performGet(_ request: RAModelGetRequest) async -> RAModelGetResult {
        guard isReady else {
            var result = RAModelGetResult()
            result.found = false
            result.error = RASDKError.make(
                code: .notInitialized,
                message: "SDK not initialized",
                category: .component
            )
            return result
        }
        try? await ensureServicesReady()
        return await CppBridge.ModelRegistry.shared.get(request)
    }

    internal static func performRegistryRefresh(
        rescanLocal: Bool = true,
        includeRemoteCatalog: Bool = false,
        pruneOrphans: Bool = false
    ) async {
        guard isReady else { return }
        try? await ensureServicesReady()

        if rescanLocal {
            _ = await CppBridge.ModelRegistry.shared.discoverDownloadedModels()
        }

        var request = RAModelRegistryRefreshRequest()
        request.rescanLocal = rescanLocal
        request.includeRemoteCatalog = includeRemoteCatalog
        request.pruneOrphans = pruneOrphans
        request.includeDownloadedState = true
        _ = await CppBridge.ModelRegistry.shared.refresh(request)
    }

    // MARK: - Deprecated flat verbs

    @available(*, deprecated, renamed: "models.list(filter:)")
    public static func listModels(_ request: RAModelListRequest = RAModelListRequest()) async -> RAModelListResult {
        await performList(request)
    }

    @available(*, deprecated, renamed: "models.list(filter:)")
    public static func queryModels(_ query: RAModelQuery) async -> RAModelListResult {
        var request = RAModelListRequest()
        request.query = query
        return await performList(request)
    }

    @available(*, deprecated, renamed: "models.get(id:)")
    public static func getModel(_ request: RAModelGetRequest) async -> RAModelGetResult {
        await performGet(request)
    }

    @available(*, deprecated, renamed: "models.list(filter:)")
    public static func downloadedModels() async -> RAModelListResult {
        var query = RAModelQuery()
        query.downloadedOnly = true
        var request = RAModelListRequest()
        request.query = query
        return await performList(request)
    }

    /// Rescan managed model directories and reconcile downloaded state.
    @available(*, deprecated, renamed: "models.refresh(rescanLocal:includeRemoteCatalog:pruneOrphans:)")
    public static func refreshModelRegistry(
        rescanLocal: Bool = true,
        includeRemoteCatalog: Bool = false,
        pruneOrphans: Bool = false
    ) async {
        await performRegistryRefresh(
            rescanLocal: rescanLocal,
            includeRemoteCatalog: includeRemoteCatalog,
            pruneOrphans: pruneOrphans
        )
    }
}
