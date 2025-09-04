package com.runanywhere.sdk.components.vad

import com.runanywhere.sdk.components.base.*
import com.runanywhere.sdk.jni.WebRTCVadJNI
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * VAD Configuration
 */
data class VADConfig(
    val aggressiveness: Int = 2, // 0-3, higher = more aggressive
    val sampleRate: Int = 16000,
    val frameDuration: Int = 30, // ms
    val silenceThreshold: Int = 500 // ms of silence to stop
) : ComponentConfig

/**
 * WebRTC VAD Component implementation
 */
class WebRTCVADComponent : VADComponent {
    private val jni = WebRTCVadJNI()
    private var vadPtr: Long = 0
    private var config: VADConfig? = null

    override suspend fun initialize(config: ComponentConfig) {
        require(config is VADConfig) { "Invalid config type" }
        this.config = config
        vadPtr = withContext(Dispatchers.IO) {
            jni.initialize(config.aggressiveness, config.sampleRate)
        }
    }

    override fun processAudioChunk(audio: FloatArray): VADResult {
        require(vadPtr != 0L) { "VAD not initialized" }
        val isSpeech = jni.isSpeech(vadPtr, audio)
        return VADResult(
            isSpeech = isSpeech,
            confidence = if (isSpeech) 0.9f else 0.1f,
            timestamp = System.currentTimeMillis()
        )
    }

    override suspend fun cleanup() {
        if (vadPtr != 0L) {
            withContext(Dispatchers.IO) {
                jni.destroy(vadPtr)
            }
            vadPtr = 0
        }
    }
}
