//
//  RunAnywhere+ModelLifecycle.swift
//  RunAnywhere SDK
//
//  Public proto-backed model/component lifecycle API.
//
//  The C++ lifecycle service is the canonical source of truth for "is this
//  modality loaded". Inference paths (voice_agent.cpp and every rac_*_proto
//  entry point, including VLM's process / process_stream / cancel) consult
//  it via `acquire_lifecycle_*`; Swift readiness checks (TTS / VLM
//  `isLoaded`) consult it via `RACurrentModelRequest`. Per-component Swift
//  actor handles (`CppBridge.{STT,TTS,VAD,VLM}.shared`) remain only for
//  legacy direct-handle ops still on `rac_*_component_*` (supports_streaming,
//  introspection, etc.) and are not consulted for inference or compose-
//  readiness. See gaps/gaps/inconsistencies/swift.md
//  SWIFT-VOICE-AGENT-001 (closed in 4dc98989a) and the rac_vlm_process_proto
//  precedent from Phase 6j. Wave 7 / T23 removed the last remnant of the
//  VLM-specific synchroniser that mirrored the lifecycle into the Swift
//  actor — there is now nothing to mirror.
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
