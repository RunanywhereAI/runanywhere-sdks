//
//  RunAnywhere+ModelLifecycle.swift
//  RunAnywhere SDK
//
//  Public proto-backed model/component lifecycle API.
//

import Foundation

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
        return await CppBridge.ModelLifecycle.load(request)
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

    static func componentLifecycleSnapshot(
        _ component: RASDKComponent
    ) -> RAComponentLifecycleSnapshot? {
        CppBridge.ModelLifecycle.componentSnapshot(component: component)
    }
}
