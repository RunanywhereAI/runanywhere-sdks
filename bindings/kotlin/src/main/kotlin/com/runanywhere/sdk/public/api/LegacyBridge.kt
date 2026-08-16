/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Single seam where the v3 namespaces reach the v2 extension verbs that still
 * own the real work (download orchestration, compatibility preflight, native
 * request coordination). Those verbs are deprecated for callers but remain the
 * implementation, so the migration adds no duplicate logic.
 */

@file:Suppress("DEPRECATION")

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.DiarizationRequest
import ai.runanywhere.proto.v1.DiffusionGenerationOptions
import ai.runanywhere.proto.v1.DiffusionResult
import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelGetRequest
import ai.runanywhere.proto.v1.ModelGetResult
import ai.runanywhere.proto.v1.ModelListRequest
import ai.runanywhere.proto.v1.ModelListResult
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.ModelLoadResult
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.ModelUnloadResult
import ai.runanywhere.proto.v1.RerankRequest
import ai.runanywhere.proto.v1.RerankResult
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.STTPartialResult
import ai.runanywhere.proto.v1.STTServiceState
import ai.runanywhere.proto.v1.SegmentationRequest
import ai.runanywhere.proto.v1.StorageDeleteResult
import ai.runanywhere.proto.v1.StorageInfoRequest
import ai.runanywhere.proto.v1.StorageInfoResult
import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.TTSOutput
import ai.runanywhere.proto.v1.TTSVoiceInfo
import ai.runanywhere.proto.v1.VADOptions
import ai.runanywhere.proto.v1.VADResult
import ai.runanywhere.proto.v1.VLMGenerationRequest
import ai.runanywhere.proto.v1.VLMResult
import ai.runanywhere.proto.v1.VLMStreamEvent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.availableTTSVoicesInternal
import com.runanywhere.sdk.public.extensions.currentModel
import com.runanywhere.sdk.public.extensions.deleteModel
import com.runanywhere.sdk.public.extensions.detectVoiceActivity
import com.runanywhere.sdk.public.extensions.diarize
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.generateImage
import com.runanywhere.sdk.public.extensions.getModel
import com.runanywhere.sdk.public.extensions.getStorageInfo
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.extensions.processImageStream
import com.runanywhere.sdk.public.extensions.refreshModelRegistry
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.extensions.rerank
import com.runanywhere.sdk.public.extensions.segment
import com.runanywhere.sdk.public.extensions.speak
import com.runanywhere.sdk.public.extensions.stopSpeaking
import com.runanywhere.sdk.public.extensions.sttState
import com.runanywhere.sdk.public.extensions.synthesize
import com.runanywhere.sdk.public.extensions.synthesizeStream
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.extensions.transcribeStream
import com.runanywhere.sdk.public.extensions.unloadModel
import kotlinx.coroutines.flow.Flow
import ai.runanywhere.proto.v1.DiarizationResult as ProtoDiarizationResult
import ai.runanywhere.proto.v1.SegmentationResult as ProtoSegmentationResult

// Models and storage

internal suspend fun legacyLoadModel(request: ModelLoadRequest): ModelLoadResult =
    RunAnywhere.loadModel(request)

internal suspend fun legacyUnloadModel(request: ModelUnloadRequest): ModelUnloadResult =
    RunAnywhere.unloadModel(request)

internal suspend fun legacyCurrentModel(request: CurrentModelRequest): CurrentModelResult =
    RunAnywhere.currentModel(request)

internal suspend fun legacyListModels(request: ModelListRequest): ModelListResult =
    RunAnywhere.listModels(request)

internal suspend fun legacyGetModel(request: ModelGetRequest): ModelGetResult =
    RunAnywhere.getModel(request)

internal suspend fun legacyDownloadModel(
    model: ModelInfo,
    onProgress: (suspend (DownloadProgress) -> Unit)? = null,
): DownloadProgress = RunAnywhere.downloadModel(model, onProgress)

internal suspend fun legacyDeleteModel(modelId: String): StorageDeleteResult =
    RunAnywhere.deleteModel(modelId)

/** Remove a model's catalog record. Callers must already have unloaded/deleted it. */
internal fun legacyUnregisterModel(modelId: String) {
    CppBridgeModelRegistry.remove(modelId)
}

internal suspend fun legacyStorageInfo(request: StorageInfoRequest): StorageInfoResult =
    RunAnywhere.getStorageInfo(request)

@Suppress("DEPRECATION")
internal suspend fun legacyRefreshModelRegistry(
    rescanLocal: Boolean,
    includeRemoteCatalog: Boolean,
    pruneOrphans: Boolean,
) = RunAnywhere.refreshModelRegistry(
    rescanLocal = rescanLocal,
    includeRemoteCatalog = includeRemoteCatalog,
    pruneOrphans = pruneOrphans,
)

internal suspend fun legacyRegisterFromUrl(model: ModelRegistration): ModelInfo =
    RunAnywhere.registerModel(
        id = model.id,
        name = model.name,
        url = model.url,
        framework = model.framework,
        modality = model.category,
        memoryRequirement = model.memoryBytes,
        supportsThinking = model.supportsThinking,
        supportsLora = model.supportsLora,
        downloadSize = model.downloadBytes,
        cuaProfile = model.cuaProfile,
    )

internal suspend fun legacyRegisterArchive(model: ModelRegistration): ModelInfo =
    RunAnywhere.registerModel(
        archiveUrl = model.url,
        structure = requireNotNull(model.archiveStructure) { "archive registration needs a structure" },
        id = model.id,
        name = model.name,
        framework = model.framework,
        modality = model.category,
        archiveType = model.archiveType,
        memoryRequirement = model.memoryBytes,
        supportsThinking = model.supportsThinking,
        supportsLora = model.supportsLora,
        cuaProfile = model.cuaProfile,
    )

internal suspend fun legacyRegisterMultiFile(model: ModelRegistration): ModelInfo =
    RunAnywhere.registerModel(
        multiFile = model.files,
        id = requireNotNull(model.id) { "multi-file registration needs an id" },
        name = model.name,
        framework = model.framework,
        modality = model.category,
        memoryRequirement = model.memoryBytes,
        contextLength = model.contextLength,
        supportsThinking = model.supportsThinking,
        downloadSize = model.downloadBytes,
        cuaProfile = model.cuaProfile,
    )

// Speech

internal suspend fun legacyTranscribe(audio: ByteArray, options: STTOptions): STTOutput =
    RunAnywhere.transcribe(audio, options)

internal fun legacyTranscribeStream(
    audio: Flow<ByteArray>,
    options: STTOptions,
): Flow<STTPartialResult> = RunAnywhere.transcribeStream(audio, options)

/**
 * Fail with the actual reason a live STT stream cannot open.
 *
 * `transcribeStream` answers an uninitialized SDK or an unloaded model by
 * closing its `callbackFlow` without emitting, so the caller saw a stream that
 * ended immediately and had nothing to distinguish "no model" from "no speech".
 * This is the port of Swift's `RunAnywhere.requireSTTModel()` preflight
 * (`STTNamespace.openStream`), so both SDKs name the precondition they failed.
 */
internal suspend fun legacyRequireSttModel() {
    if (!RunAnywhere.isInitialized) {
        throw SDKException.notInitialized("RunAnywhere")
    }
    val current =
        RunAnywhere.currentModel(
            CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION),
        )
    if (!current.found) {
        throw SDKException.modelNotLoaded()
    }
}

internal suspend fun legacySttState(): STTServiceState = RunAnywhere.sttState()

internal suspend fun legacySynthesize(text: String, options: TTSOptions): TTSOutput =
    RunAnywhere.synthesize(text, options)

internal fun legacySynthesizeStream(text: String, options: TTSOptions): Flow<TTSOutput> =
    RunAnywhere.synthesizeStream(text, options)

internal suspend fun legacySpeak(text: String, options: TTSOptions) {
    RunAnywhere.speak(text, options)
}

internal suspend fun legacyStopSpeaking() {
    RunAnywhere.stopSpeaking()
}

internal suspend fun legacyVoices(): List<TTSVoiceInfo> = RunAnywhere.availableTTSVoicesInternal()

internal suspend fun legacyDetectVoiceActivity(audio: ByteArray, options: VADOptions): VADResult =
    RunAnywhere.detectVoiceActivity(audio, options)

// Vision and other primitives

internal suspend fun legacyProcessImage(request: VLMGenerationRequest): VLMResult =
    RunAnywhere.processImage(request)

internal fun legacyProcessImageStream(request: VLMGenerationRequest): Flow<VLMStreamEvent> =
    RunAnywhere.processImageStream(request)

internal suspend fun legacyGenerateImage(options: DiffusionGenerationOptions): DiffusionResult =
    RunAnywhere.generateImage(options)

internal suspend fun legacyDiarize(request: DiarizationRequest): ProtoDiarizationResult =
    RunAnywhere.diarize(request)

internal suspend fun legacySegment(request: SegmentationRequest): ProtoSegmentationResult =
    RunAnywhere.segment(request)

internal suspend fun legacyRerank(request: RerankRequest): RerankResult =
    RunAnywhere.rerank(request)
