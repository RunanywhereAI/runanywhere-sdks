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
