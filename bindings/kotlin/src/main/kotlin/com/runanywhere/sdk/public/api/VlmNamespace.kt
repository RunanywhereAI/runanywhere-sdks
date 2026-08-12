/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: `RunAnywhere.vlm`.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.VLMStreamEventKind
import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.util.UUID

/**
 * Vision-language generation over one image.
 *
 * ```kotlin
 * val caption = RunAnywhere.vlm.generate(ImageInput.bitmap(photo), "What is in this photo?")
 * println(caption.text)
 * ```
 */
public class VlmNamespace internal constructor() {
    /**
     * Answer [prompt] about [image].
     *
     * @throws SDKException when no vision-language model can be loaded.
     */
    public suspend fun generate(
        image: ImageInput,
        prompt: String,
        options: LlmOptions? = null,
    ): GenerationResult {
        val opts = options.orDefault()
        val model = prepareVlm(opts)
        val requestId = UUID.randomUUID().toString()
        return legacyProcessImage(opts.toVlmProto(prompt, listOf(image.toVlmImage())))
            .toGenerationResult(requestId, model)
    }

    /**
     * Stream an answer to [prompt] about [image].
     *
     * @throws SDKException when no vision-language model can be loaded.
     */
    public fun generateStream(
        image: ImageInput,
        prompt: String,
        options: LlmOptions? = null,
    ): Flow<GenerationEvent> =
        flow {
            val opts = options.orDefault()
            val model = prepareVlm(opts)
            val requestId = UUID.randomUUID().toString()
            val answer = StringBuilder()
            val textItemId = UUID.randomUUID().toString()
            var startedEmitted = false
            var sawTerminal = false
            var sequence = 0L

            suspend fun announceStarted() {
                if (!startedEmitted) {
                    startedEmitted = true
                    emit(GenerationEvent.Started(requestId))
                }
            }

            legacyProcessImageStream(opts.toVlmProto(prompt, listOf(image.toVlmImage()))).collect { event ->
                when (event.kind) {
                    VLMStreamEventKind.VLM_STREAM_EVENT_KIND_STARTED -> announceStarted()
                    VLMStreamEventKind.VLM_STREAM_EVENT_KIND_TOKEN -> {
                        announceStarted()
                        if (event.token.isNotEmpty()) {
                            answer.append(event.token)
                            emit(GenerationEvent.TextDelta(requestId, sequence++, textItemId, 0, event.token))
                        }
                    }
                    VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED -> {
                        sawTerminal = true
                        emit(
                            GenerationEvent.Completed(
                                requestId,
                                event.result?.toGenerationResult(requestId, model)
                                    ?: GenerationResult(
                                        text = answer.toString(),
                                        requestId = requestId,
                                        model = model,
                                    ),
                            ),
                        )
                    }
                    else -> Unit
                }
            }

            if (!sawTerminal) {
                emit(
                    GenerationEvent.Failed(
                        requestId,
                        answer.toString().takeIf { it.isNotEmpty() },
                        SDKException.operation("Generation stream ended before a terminal event"),
                    ),
                )
            }
        }

    private suspend fun prepareVlm(opts: LlmOptions): String {
        opts.model?.takeIf { it.isNotBlank() }?.let {
            ensureModelLoaded(it, ModelCategory.MODEL_CATEGORY_MULTIMODAL)
        }
        val active = resolveActiveModelId(opts.model, ModelCategory.MODEL_CATEGORY_MULTIMODAL)
        if (active.isNotEmpty()) return active
        val vision = resolveActiveModelId(null, ModelCategory.MODEL_CATEGORY_VISION)
        if (vision.isNotEmpty()) return vision
        throw SDKException.modelNotLoaded(opts.model)
    }
}
