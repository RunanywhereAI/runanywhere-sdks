//
//  RunAnywhere+ModelRegistry.swift
//  RunAnywhere SDK
//
//  Public proto-backed model registry API.
//


public extension RunAnywhere {
    static func listModels(_ request: RAModelListRequest = RAModelListRequest()) async -> RAModelListResult {
        guard isInitialized else {
            var result = RAModelListResult()
            result.success = false
            result.errorMessage = "SDK not initialized"
            return result
        }
        try? await ensureServicesReady()
        return await CppBridge.ModelRegistry.shared.list(request)
    }

    static func queryModels(_ query: RAModelQuery) async -> RAModelListResult {
        var request = RAModelListRequest()
        request.query = query
        return await listModels(request)
    }

    static func getModel(_ request: RAModelGetRequest) async -> RAModelGetResult {
        guard isInitialized else {
            var result = RAModelGetResult()
            result.found = false
            result.errorMessage = "SDK not initialized"
            return result
        }
        try? await ensureServicesReady()
        return await CppBridge.ModelRegistry.shared.get(request)
    }

    static func downloadedModels() async -> RAModelListResult {
        var query = RAModelQuery()
        query.downloadedOnly = true
        return await queryModels(query)
    }

    /// Rescan managed model directories and reconcile downloaded state in the registry.
    /// Mirrors Flutter `RunAnywhere.refreshModelRegistry()`.
    static func refreshModelRegistry(
        rescanLocal: Bool = true,
        includeRemoteCatalog: Bool = false,
        pruneOrphans: Bool = false
    ) async {
        guard isInitialized else { return }
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
}
