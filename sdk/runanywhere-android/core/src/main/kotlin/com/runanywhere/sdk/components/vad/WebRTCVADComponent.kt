package com.runanywhere.sdk.components.vad

import com.konovalov.vad.webrtc.VadWebRTC
import com.konovalov.vad.webrtc.config.FrameSize
import com.konovalov.vad.webrtc.config.Mode
import com.konovalov.vad.webrtc.config.SampleRate
import com.runanywhere.sdk.components.base.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * VAD Configuration
 */
data class VADConfig(
    val sampleRate: Int = 16000,
    val frameSize: Int = 320, // For 16kHz, valid sizes are 160, 320, 480
    val mode: VADMode = VADMode.VERY_AGGRESSIVE,
    val speechDurationMs: Int = 50, // Minimum speech duration
    val silenceDurationMs: Int = 300, // Minimum silence duration to stop
) : ComponentConfig

enum class VADMode {
    NORMAL,
    LOW_BITRATE,
    AGGRESSIVE,
    VERY_AGGRESSIVE
}

/**
 * WebRTC VAD Component implementation using android-vad library
 */
class WebRTCVADComponent : VADComponent {
    private var vad: VadWebRTC? = null
    private var config: VADConfig? = null

    override suspend fun initialize(config: ComponentConfig) {
        require(config is VADConfig) { "Invalid config type" }
        this.config = config

        withContext(Dispatchers.IO) {
            // Map config to library types
            val sampleRate = when (config.sampleRate) {
                8000 -> SampleRate.SAMPLE_RATE_8K
                16000 -> SampleRate.SAMPLE_RATE_16K
                32000 -> SampleRate.SAMPLE_RATE_32K
                48000 -> SampleRate.SAMPLE_RATE_48K
                else -> throw IllegalArgumentException("Unsupported sample rate: ${config.sampleRate}")
            }

            val frameSize = when (config.frameSize) {
                80 -> FrameSize.FRAME_SIZE_80
                160 -> FrameSize.FRAME_SIZE_160
                240 -> FrameSize.FRAME_SIZE_240
                320 -> FrameSize.FRAME_SIZE_320
                480 -> FrameSize.FRAME_SIZE_480
                640 -> FrameSize.FRAME_SIZE_640
                960 -> FrameSize.FRAME_SIZE_960
                1440 -> FrameSize.FRAME_SIZE_1440
                else -> throw IllegalArgumentException("Unsupported frame size: ${config.frameSize}")
            }

            val mode = when (config.mode) {
                VADMode.NORMAL -> Mode.NORMAL
                VADMode.LOW_BITRATE -> Mode.LOW_BITRATE
                VADMode.AGGRESSIVE -> Mode.AGGRESSIVE
                VADMode.VERY_AGGRESSIVE -> Mode.VERY_AGGRESSIVE
            }

            vad = VadWebRTC(
                sampleRate = sampleRate,
                frameSize = frameSize,
                mode = mode,
                speechDurationMs = config.speechDurationMs,
                silenceDurationMs = config.silenceDurationMs
            )
        }
    }

    override fun processAudioChunk(audio: FloatArray): VADResult {
        val vadInstance = vad ?: throw IllegalStateException("VAD not initialized")

        // VadWebRTC.isSpeech() handles the continuous speech detection logic
        // internally using speechDurationMs and silenceDurationMs
        val isSpeech = vadInstance.isSpeech(audio)

        // Calculate a simple energy level for confidence
        val energy = audio.map { it * it }.average().toFloat()
        val confidence = if (isSpeech) {
            0.5f + minOf(energy * 10, 0.5f) // 0.5 to 1.0 range
        } else {
            maxOf(0.1f, energy * 10) // 0.1 to 0.5 range
        }

        return VADResult(
            isSpeech = isSpeech,
            confidence = confidence,
            timestamp = System.currentTimeMillis()
        )
    }

    override suspend fun cleanup() {
        withContext(Dispatchers.IO) {
            vad?.close()
            vad = null
        }
    }
}
