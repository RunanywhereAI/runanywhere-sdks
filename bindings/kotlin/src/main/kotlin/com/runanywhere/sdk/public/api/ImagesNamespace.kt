/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: `RunAnywhere.images`, `RunAnywhere.diarization`, and
 * `RunAnywhere.segmentation`.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.DiarizationRequest
import ai.runanywhere.proto.v1.SegmentationRequest
import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import okio.ByteString.Companion.toByteString

/**
 * Image generation and inpainting.
 *
 * ```kotlin
 * val art = RunAnywhere.images.generate("a lighthouse at dusk", ImageOptions(steps = 20))
 * render(art.images.first().bytes)
 * ```
 */
public class ImagesNamespace internal constructor() {
    /**
     * Paint an image for [prompt], or repaint a masked region when
     * `options.mode` is [ImageMode.Inpaint].
     *
     * @throws SDKException when no image-generation model is loaded.
     */
    public suspend fun generate(prompt: String, options: ImageOptions? = null): ImageResult {
        val opts = options.orDefault()
        if (prompt.isBlank()) throw SDKException.invalidArgument("prompt must not be blank")
        return legacyGenerateImage(opts.toProto(prompt)).toImageResult(opts.steps ?: 0)
    }

    /**
     * Stream an image generation.
     *
     * Commons exposes no intermediate-image callback on the Android diffusion
     * ABI, so this emits `started` and then `completed`.
     *
     * @throws SDKException when no image-generation model is loaded.
     */
    public fun generateStream(prompt: String, options: ImageOptions? = null): Flow<ImageEvent> =
        flow {
            emit(ImageEvent.Started)
            emit(ImageEvent.Completed(generate(prompt, options)))
        }
}

/**
 * Speaker diarization over recorded audio.
 *
 * ```kotlin
 * val turns = RunAnywhere.diarization.diarize(AudioInput.wav(meeting))
 * println("${turns.speakerCount} speakers")
 * ```
 */
public class DiarizationNamespace internal constructor() {
    /**
     * Split [audio] into per-speaker turns.
     *
     * @throws SDKException when no speaker-diarization model is loaded.
     */
    public suspend fun diarize(
        audio: AudioInput,
        options: DiarizationOptions? = null,
    ): DiarizationResult =
        legacyDiarize(
            DiarizationRequest(
                audio_data = audio.normalizedBytes().toByteString(),
                options = options.orDefault().toProto(),
            ),
        ).toDiarizationResult()
}

/**
 * Semantic segmentation over one image.
 *
 * ```kotlin
 * val mask = RunAnywhere.segmentation.segment(ImageInput.bitmap(frame))
 * println(mask.classes.map { it.label })
 * ```
 */
public class SegmentationNamespace internal constructor() {
    /**
     * Produce a per-pixel class mask for [image].
     *
     * @throws SDKException when no segmentation model is loaded or the image
     *   carries no raw pixels.
     */
    public suspend fun segment(
        image: ImageInput,
        options: SegmentationOptions? = null,
    ): SegmentationResult =
        legacySegment(
            SegmentationRequest(
                image = image.toSegmentationImage(),
                options = options.orDefault().toProto(),
            ),
        ).toSegmentationResult()
}
