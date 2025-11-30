package com.runanywhere.sdk.core.onnx

/**
 * RunAnywhereBridge - JNI bridge to native RunAnywhere C library
 *
 * This class MUST be in this exact package to match the JNI function signatures
 * in runanywhere-core/src/bridge/jni/runanywhere_jni.cpp
 *
 * JNI functions are named: Java_com_runanywhere_sdk_core_onnx_RunAnywhereBridge_*
 */
object RunAnywhereBridge {

    // =============================================================================
    // Backend Lifecycle
    // =============================================================================

    @JvmStatic
    external fun nativeCreateBackend(backendName: String): Long

    @JvmStatic
    external fun nativeInitialize(handle: Long, configJson: String?): Int

    @JvmStatic
    external fun nativeIsInitialized(handle: Long): Boolean

    @JvmStatic
    external fun nativeDestroy(handle: Long)

    @JvmStatic
    external fun nativeGetBackendInfo(handle: Long): String?

    @JvmStatic
    external fun nativeSupportsCapability(handle: Long, capability: Int): Boolean

    @JvmStatic
    external fun nativeGetCapabilities(handle: Long): IntArray

    @JvmStatic
    external fun nativeGetDevice(handle: Long): Int

    @JvmStatic
    external fun nativeGetMemoryUsage(handle: Long): Long

    // =============================================================================
    // Text Generation (LLM)
    // =============================================================================

    @JvmStatic
    external fun nativeTextLoadModel(handle: Long, modelPath: String, configJson: String?): Int

    @JvmStatic
    external fun nativeTextIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeTextUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeTextGenerate(
        handle: Long,
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Float
    ): String?

    @JvmStatic
    external fun nativeTextCancel(handle: Long)

    // =============================================================================
    // Speech-to-Text (STT)
    // =============================================================================

    @JvmStatic
    external fun nativeSTTLoadModel(
        handle: Long,
        modelPath: String,
        modelType: String,
        configJson: String?
    ): Int

    @JvmStatic
    external fun nativeSTTIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeSTTUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeSTTTranscribe(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int,
        language: String?
    ): String?

    @JvmStatic
    external fun nativeSTTSupportsStreaming(handle: Long): Boolean

    @JvmStatic
    external fun nativeSTTCreateStream(handle: Long, configJson: String?): Long

    @JvmStatic
    external fun nativeSTTFeedAudio(
        handle: Long,
        streamHandle: Long,
        audioSamples: FloatArray,
        sampleRate: Int
    ): Int

    @JvmStatic
    external fun nativeSTTIsReady(handle: Long, streamHandle: Long): Boolean

    @JvmStatic
    external fun nativeSTTDecode(handle: Long, streamHandle: Long): String?

    @JvmStatic
    external fun nativeSTTIsEndpoint(handle: Long, streamHandle: Long): Boolean

    @JvmStatic
    external fun nativeSTTInputFinished(handle: Long, streamHandle: Long)

    @JvmStatic
    external fun nativeSTTResetStream(handle: Long, streamHandle: Long)

    @JvmStatic
    external fun nativeSTTDestroyStream(handle: Long, streamHandle: Long)

    @JvmStatic
    external fun nativeSTTCancel(handle: Long)

    // =============================================================================
    // Text-to-Speech (TTS)
    // =============================================================================

    @JvmStatic
    external fun nativeTTSLoadModel(
        handle: Long,
        modelPath: String,
        modelType: String,
        configJson: String?
    ): Int

    @JvmStatic
    external fun nativeTTSIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeTTSUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeTTSSynthesize(
        handle: Long,
        text: String,
        voiceId: String?,
        speedRate: Float,
        pitchShift: Float
    ): com.runanywhere.sdk.native.bridge.NativeTTSSynthesisResult?

    @JvmStatic
    external fun nativeTTSSupportsStreaming(handle: Long): Boolean

    @JvmStatic
    external fun nativeTTSGetVoices(handle: Long): String?

    @JvmStatic
    external fun nativeTTSCancel(handle: Long)

    // =============================================================================
    // Voice Activity Detection (VAD)
    // =============================================================================

    @JvmStatic
    external fun nativeVADLoadModel(handle: Long, modelPath: String?, configJson: String?): Int

    @JvmStatic
    external fun nativeVADIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeVADUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeVADProcess(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int
    ): com.runanywhere.sdk.native.bridge.NativeVADResult?

    @JvmStatic
    external fun nativeVADDetectSegments(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int
    ): String?

    @JvmStatic
    external fun nativeVADReset(handle: Long)

    // =============================================================================
    // Embeddings
    // =============================================================================

    @JvmStatic
    external fun nativeEmbedLoadModel(handle: Long, modelPath: String, configJson: String?): Int

    @JvmStatic
    external fun nativeEmbedIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeEmbedUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeEmbedText(handle: Long, text: String): FloatArray?

    @JvmStatic
    external fun nativeEmbedGetDimensions(handle: Long): Int

    // =============================================================================
    // Diarization
    // =============================================================================

    @JvmStatic
    external fun nativeDiarizeLoadModel(handle: Long, modelPath: String, configJson: String?): Int

    @JvmStatic
    external fun nativeDiarizeIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeDiarizeUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeDiarize(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int,
        minSpeakers: Int,
        maxSpeakers: Int
    ): String?

    @JvmStatic
    external fun nativeDiarizeCancel(handle: Long)

    // =============================================================================
    // Utility
    // =============================================================================

    @JvmStatic
    external fun nativeGetLastError(): String?

    @JvmStatic
    external fun nativeGetVersion(): String?

    @JvmStatic
    external fun nativeExtractArchive(archivePath: String, destDir: String): Int

    @JvmStatic
    external fun nativeGetAvailableBackends(): Array<String>?
}
