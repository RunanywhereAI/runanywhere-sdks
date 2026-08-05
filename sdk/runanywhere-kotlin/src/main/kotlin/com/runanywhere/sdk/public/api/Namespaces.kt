/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: the namespaces hanging off `RunAnywhere`.
 */

package com.runanywhere.sdk.public.api

import com.runanywhere.sdk.public.RunAnywhere

private val llmNamespace = LlmNamespace()
private val vlmNamespace = VlmNamespace()
private val sttNamespace = SttNamespace()
private val ttsNamespace = TtsNamespace()
private val vadNamespace = VadNamespace()
private val embeddingsNamespace = EmbeddingsNamespace()
private val rerankNamespace = RerankNamespace()
private val imagesNamespace = ImagesNamespace()
private val diarizationNamespace = DiarizationNamespace()
private val segmentationNamespace = SegmentationNamespace()
private val voiceNamespace = VoiceNamespace()
private val ragNamespace = RagNamespace()
private val modelsNamespace = ModelsNamespace()
private val loraNamespace = LoraNamespace()

/** Text generation. */
public val RunAnywhere.llm: LlmNamespace get() = llmNamespace

/** Vision-language generation. */
public val RunAnywhere.vlm: VlmNamespace get() = vlmNamespace

/** Speech-to-text transcription. */
public val RunAnywhere.stt: SttNamespace get() = sttNamespace

/** Text-to-speech synthesis and playback. */
public val RunAnywhere.tts: TtsNamespace get() = ttsNamespace

/** Voice-activity detection. */
public val RunAnywhere.vad: VadNamespace get() = vadNamespace

/** Text embeddings. */
public val RunAnywhere.embeddings: EmbeddingsNamespace get() = embeddingsNamespace

/** Cross-encoder reranking. */
public val RunAnywhere.rerank: RerankNamespace get() = rerankNamespace

/** Image generation and inpainting. */
public val RunAnywhere.images: ImagesNamespace get() = imagesNamespace

/** Speaker diarization. */
public val RunAnywhere.diarization: DiarizationNamespace get() = diarizationNamespace

/** Semantic segmentation. */
public val RunAnywhere.segmentation: SegmentationNamespace get() = segmentationNamespace

/** Live voice conversations. */
public val RunAnywhere.voice: VoiceNamespace get() = voiceNamespace

/** Retrieval-augmented generation. */
public val RunAnywhere.rag: RagNamespace get() = ragNamespace

/** The model catalog and its residency. */
public val RunAnywhere.models: ModelsNamespace get() = modelsNamespace

/** LoRA adapters layered onto the loaded base model. */
public val RunAnywhere.lora: LoraNamespace get() = loraNamespace

/** Modality ids the v4 public API spec explicitly excludes from every SDK. */
private val EXPLICITLY_ABSENT_CAPABILITIES =
    listOf(
        UnavailableCapability("agents", "RunAnywhere.agents is not part of the v4 public API surface."),
        UnavailableCapability("wakeword", "RunAnywhere.wakeword is not part of the v4 public API surface."),
        UnavailableCapability(
            "realtime",
            "RunAnywhere.realtime is not part of the v4 public API surface (no WebRTC/SIP/S2S transport namespace).",
        ),
    )

/**
 * Static per-build manifest of the namespaces and backends this Android SDK
 * ships. Backing [RunAnywhere.capabilities]; see its doc comment for what
 * this does and does not probe.
 */
internal fun sdkCapabilitiesSnapshot(): SDKCapabilities =
    SDKCapabilities(
        modalities =
            setOf(
                "llm",
                "vlm",
                "stt",
                "tts",
                "vad",
                "embeddings",
                "rerank",
                "images",
                "diarization",
                "segmentation",
                "voice",
                "rag",
                "models",
                "lora",
                "cua",
            ),
        backends = setOf(Backend.INFERENCE_FRAMEWORK_LLAMA_CPP, Backend.INFERENCE_FRAMEWORK_ONNX),
        audioFormats = setOf(AudioFormat.AUDIO_FORMAT_PCM, AudioFormat.AUDIO_FORMAT_WAV, AudioFormat.AUDIO_FORMAT_PCM_S16LE),
        streaming = StreamingCapabilities(),
        tools = ToolCapabilities(),
        rag = RagCapabilities(multiSession = true, persistent = true),
        unavailable = EXPLICITLY_ABSENT_CAPABILITIES,
    )
