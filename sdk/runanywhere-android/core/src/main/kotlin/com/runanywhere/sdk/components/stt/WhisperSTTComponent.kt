package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.components.base.*
import com.runanywhere.sdk.jni.WhisperJNI
import com.runanywhere.sdk.models.ModelManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext

/**
 * STT Configuration
 */
data class STTConfig(
    val modelId: String = "whisper-base",
    val language: String = "en",
    val enableTimestamps: Boolean = false
) : ComponentConfig

/**
 * Whisper STT Component implementation
 */
class WhisperSTTComponent : STTComponent {
    private val jni = WhisperJNI()
    private var modelPtr: Long = 0
    private val modelManager = ModelManager()
    private var config: STTConfig? = null

    override suspend fun initialize(config: ComponentConfig) {
        require(config is STTConfig) { "Invalid config type" }
        this.config = config

        // Ensure model is available and load it
        val modelPath = modelManager.ensureModel(config.modelId)
        modelPtr = withContext(Dispatchers.IO) {
            jni.loadModel(modelPath)
        }
    }

    override suspend fun transcribe(audioData: ByteArray): TranscriptionResult {
        require(modelPtr != 0L) { "Model not loaded" }
        val cfg = config ?: throw IllegalStateException("Component not initialized")

        return withContext(Dispatchers.IO) {
            val text = jni.transcribe(modelPtr, audioData, cfg.language)
            TranscriptionResult(
                text = text,
                confidence = 0.95f,
                language = cfg.language,
                duration = audioData.size / 32000.0 // 16kHz stereo
            )
        }
    }

    override fun transcribeStream(audioFlow: Flow<ByteArray>): Flow<TranscriptionUpdate> = flow {
        require(modelPtr != 0L) { "Model not loaded" }

        audioFlow.collect { chunk ->
            val partial = withContext(Dispatchers.IO) {
                jni.transcribePartial(modelPtr, chunk)
            }
            emit(
                TranscriptionUpdate(
                    text = partial,
                    isFinal = false,
                    timestamp = System.currentTimeMillis()
                )
            )
        }
    }

    override suspend fun cleanup() {
        if (modelPtr != 0L) {
            withContext(Dispatchers.IO) {
                jni.unloadModel(modelPtr)
            }
            modelPtr = 0
        }
    }
}
