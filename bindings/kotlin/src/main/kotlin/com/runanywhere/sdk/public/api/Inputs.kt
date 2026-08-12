/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: the input envelopes every modality accepts.
 */

package com.runanywhere.sdk.public.api

import android.graphics.Bitmap
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Sample layout of a raw audio buffer. */
public enum class AudioEncoding {
    /** Signed 16-bit little-endian samples. */
    PCM16,

    /** 32-bit float samples in `[-1.0, 1.0]`. */
    FLOAT32,

    /** Self-describing container such as WAV. */
    CONTAINER,
}

/** How to interpret the bytes of an [AudioInput]. */
public data class AudioFormatSpec(
    val encoding: AudioEncoding,
    val sampleRate: Int = DEFAULT_SAMPLE_RATE,
    val channels: Int = 1,
) {
    public companion object {
        public const val DEFAULT_SAMPLE_RATE: Int = 16_000
    }
}

/**
 * Audio handed to the SDK, together with the format needed to read it.
 *
 * Build one with [pcm16], [float32], [wav], or [file] rather than the
 * constructor, so the format spec always matches the bytes.
 */
public class AudioInput internal constructor(
    public val bytes: ByteArray,
    public val format: AudioFormatSpec,
) {
    /** Bytes normalised to the float32 layout every commons audio path expects. */
    internal fun normalizedBytes(): ByteArray =
        when (format.encoding) {
            AudioEncoding.PCM16 -> pcm16ToFloat32Bytes(bytes)
            AudioEncoding.FLOAT32, AudioEncoding.CONTAINER -> bytes
        }

    /**
     * Bytes as signed 16-bit little-endian PCM — the layout the sherpa STT
     * engine expects (it reinterprets the buffer as int16 and converts to float
     * itself; see the iOS bridge, which sends unconverted PCM16). Sending
     * float32 here would be misread as int16 and transcribed as noise.
     */
    internal fun pcm16Bytes(): ByteArray =
        when (format.encoding) {
            AudioEncoding.PCM16, AudioEncoding.CONTAINER -> bytes
            AudioEncoding.FLOAT32 -> float32ToPcm16Bytes(bytes)
        }

    public companion object {
        /** Wrap signed 16-bit little-endian microphone samples. */
        public fun pcm16(
            bytes: ByteArray,
            sampleRate: Int = AudioFormatSpec.DEFAULT_SAMPLE_RATE,
            channels: Int = 1,
        ): AudioInput = AudioInput(bytes, AudioFormatSpec(AudioEncoding.PCM16, sampleRate, channels))

        /** Wrap float samples already normalised to `[-1.0, 1.0]`. */
        public fun float32(
            samples: FloatArray,
            sampleRate: Int = AudioFormatSpec.DEFAULT_SAMPLE_RATE,
        ): AudioInput {
            val buffer = ByteBuffer.allocate(samples.size * Float.SIZE_BYTES).order(ByteOrder.LITTLE_ENDIAN)
            samples.forEach(buffer::putFloat)
            return AudioInput(buffer.array(), AudioFormatSpec(AudioEncoding.FLOAT32, sampleRate))
        }

        /** Wrap float32 bytes that are already little-endian. */
        public fun float32Bytes(
            bytes: ByteArray,
            sampleRate: Int = AudioFormatSpec.DEFAULT_SAMPLE_RATE,
        ): AudioInput = AudioInput(bytes, AudioFormatSpec(AudioEncoding.FLOAT32, sampleRate))

        /** Wrap a complete WAV container. */
        public fun wav(bytes: ByteArray): AudioInput =
            AudioInput(bytes, AudioFormatSpec(AudioEncoding.CONTAINER))

        /**
         * Read an audio file from disk.
         *
         * @throws SDKException when the file is missing or unreadable.
         */
        public fun file(path: String): AudioInput {
            val data = readFileOrThrow(path, "audio")
            return AudioInput(data, AudioFormatSpec(AudioEncoding.CONTAINER))
        }
    }
}

/** Raw pixel layout of an [ImageInput]. */
public enum class ImagePixelLayout {
    RGB8,
    RGBA8,
}

/**
 * An image handed to the SDK.
 *
 * Build one with [file], [bytes], [rawRgb], [rawRgba], or [bitmap].
 */
public class ImageInput private constructor(
    internal val encoded: ByteArray?,
    internal val raw: ByteArray?,
    internal val width: Int,
    internal val height: Int,
    internal val layout: ImagePixelLayout?,
    internal val filePath: String?,
) {
    public companion object {
        /** Reference an image on disk without reading it into memory. */
        public fun file(path: String): ImageInput =
            ImageInput(null, null, 0, 0, null, path)

        /** Wrap encoded JPEG, PNG, or WebP bytes. */
        public fun bytes(data: ByteArray): ImageInput =
            ImageInput(data, null, 0, 0, null, null)

        /** Wrap tightly packed 3-byte-per-pixel RGB data. */
        public fun rawRgb(data: ByteArray, width: Int, height: Int): ImageInput =
            ImageInput(null, data, width, height, ImagePixelLayout.RGB8, null)

        /** Wrap tightly packed 4-byte-per-pixel RGBA data. */
        public fun rawRgba(data: ByteArray, width: Int, height: Int): ImageInput =
            ImageInput(null, data, width, height, ImagePixelLayout.RGBA8, null)

        /** Wrap an Android [Bitmap], packing it as RGBA. */
        public fun bitmap(bitmap: Bitmap): ImageInput {
            val width = bitmap.width
            val height = bitmap.height
            val pixels = IntArray(width * height)
            bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
            val rgba = ByteArray(pixels.size * 4)
            pixels.forEachIndexed { index, pixel ->
                val offset = index * 4
                rgba[offset] = ((pixel shr 16) and 0xFF).toByte()
                rgba[offset + 1] = ((pixel shr 8) and 0xFF).toByte()
                rgba[offset + 2] = (pixel and 0xFF).toByte()
                rgba[offset + 3] = ((pixel shr 24) and 0xFF).toByte()
            }
            return rawRgba(rgba, width, height)
        }
    }
}

/** Who authored a message in a chat transcript. */
public enum class ChatRole {
    SYSTEM,
    USER,
    ASSISTANT,
    TOOL,
}

/** One turn of a chat transcript. */
public data class ChatMessage(
    val role: ChatRole,
    val content: String,
    val toolCallId: String? = null,
)

/** Points a session or generation at a registered model, optionally at one voice inside it. */
public data class ModelRef(
    val id: String,
    val voice: String? = null,
)

/** A document to index into a RAG session. */
public class RagDocument private constructor(
    internal val text: String,
    internal val metadata: Map<String, String>,
    internal val sourceUri: String?,
) {
    public constructor(text: String, metadata: Map<String, String>? = null) :
        this(text, metadata.orEmpty(), null)

    public companion object {
        /**
         * Read a UTF-8 text document from disk.
         *
         * @throws SDKException when the file is missing or unreadable.
         */
        public fun file(path: String): RagDocument {
            val data = readFileOrThrow(path, "document")
            return RagDocument(data.decodeToString(), emptyMap(), path)
        }
    }
}

private fun readFileOrThrow(path: String, kind: String): ByteArray {
    val handle = File(path)
    if (!handle.isFile) {
        throw SDKException.invalidArgument("No $kind file at $path")
    }
    return runCatching { handle.readBytes() }.getOrElse { error ->
        throw SDKException.invalidArgument("Could not read $kind file at $path", error)
    }
}

private fun pcm16ToFloat32Bytes(pcm16: ByteArray): ByteArray {
    val samples =
        RunAnywhereBridge.racAudioPcm16ToFloat32(pcm16)
            ?: throw SDKException.invalidArgument("rac_audio_pcm16_to_float32 failed")
    if (samples.isEmpty()) return ByteArray(0)
    val output = ByteBuffer.allocate(samples.size * Float.SIZE_BYTES).order(ByteOrder.LITTLE_ENDIAN)
    for (sample in samples) {
        output.putFloat(sample)
    }
    return output.array()
}

private fun float32ToPcm16Bytes(float32: ByteArray): ByteArray {
    val sampleCount = float32.size / Float.SIZE_BYTES
    if (sampleCount == 0) return ByteArray(0)
    val input = ByteBuffer.wrap(float32).order(ByteOrder.LITTLE_ENDIAN)
    val samples = FloatArray(sampleCount) { input.float }
    return RunAnywhereBridge.racAudioFloat32ToPcm16(samples)
        ?: throw SDKException.invalidArgument("rac_audio_float32_to_pcm16 failed")
}
