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
class WhisperSTTComponent : STTService {
    private val jni = WhisperJNI()
    private var modelPtr: Long = 0
    private val modelManager = ModelManager()
    private var config: STTConfig? = null

    override val isReady: Boolean
        get() = modelPtr != 0L

    override val currentModel: String?
        get() = config?.modelId

    override suspend fun initialize(modelPath: String?) {
        if (modelPath == null) {
            throw SDKError.ModelNotFound("Model path is required")
        }

        // Ensure model is available and load it
        val actualPath = modelManager.ensureModel(modelPath)
        modelPtr = withContext(Dispatchers.IO) {
            jni.loadModel(actualPath)
        }
        config = STTConfig(modelId = modelPath)
    }

    override suspend fun transcribe(
        audioData: ByteArray,
        options: STTOptions
    ): STTTranscriptionResult {
        require(modelPtr != 0L) { "Model not loaded" }
        val cfg = config ?: throw IllegalStateException("Component not initialized")

        return withContext(Dispatchers.IO) {
            val text = jni.transcribe(modelPtr, audioData, options.language)

            // Parse timestamps if enabled
            val timestamps = if (options.enableTimestamps) {
                // This would need JNI support for timestamps
                null // For now, return null
            } else {
                null
            }

            STTTranscriptionResult(
                transcript = text,
                confidence = 0.95f,
                timestamps = timestamps,
                language = options.language
            )
        }
    }

    override suspend fun <T> streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit
    ): STTTranscriptionResult {
        require(modelPtr != 0L) { "Model not loaded" }

        val fullText = StringBuilder()

        audioStream.collect { chunk ->
            val partial = withContext(Dispatchers.IO) {
                jni.transcribePartial(modelPtr, chunk)
            }
            onPartial(partial)
            fullText.append(partial).append(" ")
        }

        return STTTranscriptionResult(
            transcript = fullText.toString().trim(),
            confidence = 0.95f,
            language = options.language
        )
    }

    override suspend fun cleanup() {
        if (modelPtr != 0L) {
            withContext(Dispatchers.IO) {
                jni.unloadModel(modelPtr)
            }
            modelPtr = 0
            config = null
        }
    }
}
