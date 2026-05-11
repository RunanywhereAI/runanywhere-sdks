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
        // The lifecycle service is the canonical source of truth for
        // "is this modality loaded". Inference paths (voice_agent.cpp and
        // every rac_*_proto entry point) consult it via acquire_lifecycle_*;
        // Swift readiness checks (TTS/VLM isLoaded) consult it via
        // RACurrentModelRequest. Per-component Swift actor handles
        // (CppBridge.{STT,TTS,VAD,VLM}.shared) remain only for legacy
        // direct-handle ops still on rac_*_component_* (cancel,
        // supports_streaming, etc.) and are not consulted for inference
        // or compose-readiness. See gaps/gaps/inconsistencies/swift.md
        // SWIFT-VOICE-AGENT-001 (closed in 4dc98989a) and the
        // rac_vlm_process_proto precedent from Phase 6j.
        if result.category.isVLMCategory {
            return await synchronizeVLMComponentLoad(result)
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
