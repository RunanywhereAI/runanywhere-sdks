/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * RAAudioFormatExtensions.kt
 *
 * Audio-related type extensions used across audio components (STT, TTS, VAD).
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/RAAudioFormat+Extensions.swift`.
 *
 * Swift adds `Codable` conformance with lowercase-short-name JSON encoding
 * (e.g. "pcm", "wav") backed by the codegen-generated `wireString` /
 * `from(wireString:)` accessors. Kotlin doesn't use Codable; the Wire-
 * generated `AudioFormat` ProtoAdapter already serializes the canonical proto
 * form. This file exposes the equivalent lowercase short-name <-> enum
 * accessors so JSON payloads share wire format with the Swift SDK.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.AudioFormat

// MARK: - Lowercase short-name wire string

/**
 * Lowercase short-name wire string for an audio format ("pcm", "wav", …).
 * Matches Swift `RAAudioFormat.wireString` (generated from
 * `rac_wire_string` annotations in `idl/model_types.proto`).
 *
 * Used by JSON wire payloads where the lowercase short name (rather than
 * the proto3 canonical `AUDIO_FORMAT_*` form) is the cross-SDK convention.
 */
val AudioFormat.wireString: String
    get() =
        when (this) {
            AudioFormat.AUDIO_FORMAT_PCM -> "pcm"
            AudioFormat.AUDIO_FORMAT_WAV -> "wav"
            AudioFormat.AUDIO_FORMAT_MP3 -> "mp3"
            AudioFormat.AUDIO_FORMAT_OPUS -> "opus"
            AudioFormat.AUDIO_FORMAT_AAC -> "aac"
            AudioFormat.AUDIO_FORMAT_FLAC -> "flac"
            AudioFormat.AUDIO_FORMAT_OGG -> "ogg"
            AudioFormat.AUDIO_FORMAT_M4A -> "m4a"
            AudioFormat.AUDIO_FORMAT_PCM_S16LE -> "pcm_s16le"
            AudioFormat.AUDIO_FORMAT_UNSPECIFIED -> "unspecified"
        }

/**
 * Parse a lowercase short-name string back into the proto enum.
 * Case-insensitive. Returns `AUDIO_FORMAT_UNSPECIFIED` on unknown inputs
 * to mirror Swift's `.from(wireString:) ?? .unspecified` decode fallback.
 */
fun audioFormatFromWireString(value: String): AudioFormat =
    when (value.lowercase()) {
        "pcm" -> AudioFormat.AUDIO_FORMAT_PCM
        "wav" -> AudioFormat.AUDIO_FORMAT_WAV
        "mp3" -> AudioFormat.AUDIO_FORMAT_MP3
        "opus" -> AudioFormat.AUDIO_FORMAT_OPUS
        "aac" -> AudioFormat.AUDIO_FORMAT_AAC
        "flac" -> AudioFormat.AUDIO_FORMAT_FLAC
        "ogg" -> AudioFormat.AUDIO_FORMAT_OGG
        "m4a" -> AudioFormat.AUDIO_FORMAT_M4A
        "pcm_s16le", "pcm_16bit" -> AudioFormat.AUDIO_FORMAT_PCM_S16LE
        else -> AudioFormat.AUDIO_FORMAT_UNSPECIFIED
    }
