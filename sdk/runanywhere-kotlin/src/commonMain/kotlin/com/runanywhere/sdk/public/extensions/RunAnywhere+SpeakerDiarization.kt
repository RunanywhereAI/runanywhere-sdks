/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for Speaker Diarization (B12, §8) — identifies which speaker
 * produced each chunk of an audio stream.
 *
 * Mirrors Swift `RunAnywhere+SpeakerDiarization.swift`. Platform actuals
 * delegate to the C ABI in runanywhere-commons:
 *   • rac_speaker_diarization_init(model_path, out_handle)
 *   • rac_speaker_diarization_process(handle, samples, count, out_json)
 *   • rac_speaker_diarization_destroy(handle)
 *
 * The native implementation is currently a stub that returns
 * RAC_ERROR_FEATURE_NOT_AVAILABLE; actuals log a warning and return an
 * empty segment list so callers get a well-defined "feature not ready"
 * signal rather than a crash.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere

/**
 * One speaker segment returned by [RunAnywhere.diarize].
 *
 * Represents a contiguous span of audio attributed to a single speaker.
 *
 * @property speaker Zero-based speaker index. Stable within one session.
 * @property startMs Segment start time in milliseconds.
 * @property endMs   Segment end time in milliseconds.
 */
data class SpeakerSegment(
    val speaker: Int,
    val startMs: Long,
    val endMs: Long,
)

/**
 * Load the speaker-diarization model.
 *
 * Optional — [diarize] also lazily loads if no model is active. Throws
 * [com.runanywhere.sdk.foundation.errors.SDKException] if the feature
 * is not yet available in commons.
 *
 * @param modelPath Filesystem path to the diarization model.
 */
expect suspend fun RunAnywhere.loadDiarizationModel(modelPath: String)

/**
 * True if a diarization session is currently loaded.
 */
expect val RunAnywhere.isDiarizationLoaded: Boolean

/**
 * Run speaker diarization on a buffer of PCM audio.
 *
 * @param audio IEEE-754 single-precision PCM samples (little-endian, 4
 *   bytes per sample, 16 kHz mono).
 * @return Segments ordered by [SpeakerSegment.startMs]. Empty when either
 *   no speech was detected or the native feature is not yet available
 *   (a warning is logged in the latter case).
 */
expect suspend fun RunAnywhere.diarize(audio: ByteArray): List<SpeakerSegment>

/**
 * Release the diarization session and its native resources.
 */
expect suspend fun RunAnywhere.unloadDiarization()
