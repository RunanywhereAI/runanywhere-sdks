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
        let result = await CppBridge.ModelLifecycle.load(request)
        guard result.success else {
            return result
        }
        if result.category.isVLMCategory {
            return await synchronizeVLMComponentLoad(result)
        }
        if result.category == .speechRecognition {
            return await synchronizeSTTComponentLoad(result)
        }
        if result.category == .speechSynthesis {
            return await synchronizeTTSComponentLoad(result)
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
        let loadedVLMModelId = await CppBridge.VLM.shared.currentModelId
        let result = CppBridge.ModelLifecycle.unload(request)
        if shouldUnloadVLMComponent(request: request, result: result, loadedModelId: loadedVLMModelId) {
            await CppBridge.VLM.shared.unload()
        }
        return result
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

private extension RunAnywhere {
    static func synchronizeVLMComponentLoad(_ result: RAModelLoadResult) async -> RAModelLoadResult {
        do {
            try await CppBridge.VLM.shared.loadModel(from: result)
            return result
        } catch {
            var unloadRequest = RAModelUnloadRequest()
            unloadRequest.modelID = result.modelID
            unloadRequest.category = result.category
            _ = CppBridge.ModelLifecycle.unload(unloadRequest)
            await CppBridge.VLM.shared.unload()

            var failed = result
            failed.success = false
            failed.errorMessage = error.localizedDescription
            return failed
        }
    }

    /// Sync the STT component actor's `isLoaded` state with the lifecycle result,
    /// matching the VLM synchronization pattern. Without this step,
    /// `RunAnywhere.transcribe(...)` throws "STT model not loaded" even though
    /// the C++ lifecycle service reported success — because the Swift actor's
    /// handle hasn't been told about the new model yet.
    static func synchronizeSTTComponentLoad(_ result: RAModelLoadResult) async -> RAModelLoadResult {
        do {
            try await CppBridge.STT.shared.loadModel(from: result)
            return result
        } catch {
            var unloadRequest = RAModelUnloadRequest()
            unloadRequest.modelID = result.modelID
            unloadRequest.category = result.category
            _ = CppBridge.ModelLifecycle.unload(unloadRequest)
            await CppBridge.STT.shared.unload()

            var failed = result
            failed.success = false
            failed.errorMessage = error.localizedDescription
            return failed
        }
    }

    /// Sync the TTS component actor's `isLoaded` state with the lifecycle result.
    /// Same pattern as STT/VLM: `RunAnywhere.synthesize(...)` requires
    /// `CppBridge.TTS.shared.isLoaded == true`, which only becomes true after
    /// the component actor is fed the voice path.
    static func synchronizeTTSComponentLoad(_ result: RAModelLoadResult) async -> RAModelLoadResult {
        do {
            try await CppBridge.TTS.shared.loadVoice(from: result)
            return result
        } catch {
            var unloadRequest = RAModelUnloadRequest()
            unloadRequest.modelID = result.modelID
            unloadRequest.category = result.category
            _ = CppBridge.ModelLifecycle.unload(unloadRequest)
            await CppBridge.TTS.shared.unload()

            var failed = result
            failed.success = false
            failed.errorMessage = error.localizedDescription
            return failed
        }
    }

    static func shouldUnloadVLMComponent(
        request: RAModelUnloadRequest,
        result: RAModelUnloadResult,
        loadedModelId: String?
    ) -> Bool {
        if request.unloadAll {
            return true
        }
        if request.hasCategory, request.category.isVLMCategory {
            return true
        }
        guard let loadedModelId else {
            return false
        }
        return result.unloadedModelIds.contains(loadedModelId)
    }
}

private extension RAModelCategory {
    var isVLMCategory: Bool {
        self == .multimodal || self == .vision
    }
}
