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
        return legacyProcessImage(image.toVlmImage(), opts.toVlmProto(prompt))
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
            var startedEmitted = false

            legacyProcessImageStream(image.toVlmImage(), opts.toVlmProto(prompt)).collect { event ->
                when (event.kind) {
                    VLMStreamEventKind.VLM_STREAM_EVENT_KIND_STARTED -> {
                        startedEmitted = true
                        emit(GenerationEvent.Started(requestId))
                    }
                    VLMStreamEventKind.VLM_STREAM_EVENT_KIND_TOKEN -> {
                        if (!startedEmitted) {
                            startedEmitted = true
                            emit(GenerationEvent.Started(requestId))
                        }
                        if (event.token.isNotEmpty()) {
                            answer.append(event.token)
                            emit(GenerationEvent.Token(event.token, TokenKind.TEXT))
                        }
                    }
                    VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED -> {
                        emit(
                            GenerationEvent.Completed(
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
