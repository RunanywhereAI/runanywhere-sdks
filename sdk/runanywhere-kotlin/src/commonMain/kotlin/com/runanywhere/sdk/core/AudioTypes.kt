package com.runanywhere.sdk.core

import kotlinx.serialization.Serializable

/**
 * Audio format enum matching iOS AudioFormat pattern exactly
 * This is the single source of truth for audio formats across STT, TTS, and VAD
 *
 * iOS reference: Core/Types/AudioTypes.swift
 */
@Serializable
enum class AudioFormat(val rawValue: String) {
    PCM("pcm"),
    WAV("wav"),
    MP3("mp3"),
    OPUS("opus"),
    AAC("aac"),
    FLAC("flac"),
    OGG("ogg"),
    PCM_16BIT("pcm_16bit");  // Android-specific raw PCM format

    /**
     * File extension for this format (matches iOS fileExtension)
     */
    val fileExtension: String
        get() = rawValue

    companion object {
        /**
         * Get AudioFormat from raw value string
         */
        fun fromRawValue(value: String): AudioFormat? =
            entries.find { it.rawValue == value.lowercase() }
    }
}
