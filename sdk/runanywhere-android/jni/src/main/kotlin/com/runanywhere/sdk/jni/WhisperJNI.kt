package com.runanywhere.sdk.jni

/**
 * JNI interface for Whisper speech-to-text
 */
class WhisperJNI {
    companion object {
        init {
            // Load native library from resources
            NativeLoader.loadLibrary("whisper-jni")
        }
    }

    /**
     * Load a Whisper model from file path
     * @return pointer to the loaded model
     */
    external fun loadModel(modelPath: String): Long

    /**
     * Transcribe audio data using the loaded model
     */
    external fun transcribe(modelPtr: Long, audioData: ByteArray, language: String): String

    /**
     * Transcribe partial audio (for streaming)
     */
    external fun transcribePartial(modelPtr: Long, audioData: ByteArray): String

    /**
     * Unload a model and free memory
     */
    external fun unloadModel(modelPtr: Long)

    /**
     * Get information about the loaded model
     */
    external fun getModelInfo(modelPtr: Long): String
}
