package com.runanywhere.reactnative

import com.facebook.react.bridge.*
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.modules.core.DeviceEventManagerModule
import kotlinx.coroutines.*
import android.util.Base64
import org.json.JSONObject
import org.json.JSONArray
import com.runanywhere.sdk.core.onnx.RunAnywhereBridge

/**
 * RunAnywhere React Native Module
 *
 * Bridges React Native to the native RunAnywhere C library via JNI.
 * Uses the RunAnywhereBridge JNI wrapper from runanywhere-core.
 */
@ReactModule(name = RunAnywhereModule.NAME)
class RunAnywhereModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    companion object {
        const val NAME = "RunAnywhere"

        init {
            try {
                // Load native libraries in order
                System.loadLibrary("c++_shared")
                System.loadLibrary("onnxruntime")
                System.loadLibrary("runanywhere_bridge")
                System.loadLibrary("runanywhere_jni")
            } catch (e: UnsatisfiedLinkError) {
                android.util.Log.e(NAME, "Failed to load native libraries: ${e.message}")
            }
        }
    }

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var backendHandle: Long = 0
    private var isInitialized = false

    override fun getName(): String = NAME

    override fun invalidate() {
        scope.cancel()
        if (backendHandle != 0L) {
            RunAnywhereBridge.nativeDestroy(backendHandle)
            backendHandle = 0
        }
        super.invalidate()
    }

    // =============================================================================
    // Event Emitter
    // =============================================================================

    private fun sendEvent(eventName: String, params: WritableMap?) {
        reactApplicationContext
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit(eventName, params)
    }

    // =============================================================================
    // Backend Lifecycle
    // =============================================================================

    @ReactMethod
    fun createBackend(name: String, promise: Promise) {
        scope.launch {
            try {
                backendHandle = RunAnywhereBridge.nativeCreateBackend(name)
                if (backendHandle != 0L) {
                    promise.resolve(true)
                } else {
                    promise.reject("CREATE_FAILED", "Failed to create backend")
                }
            } catch (e: Exception) {
                promise.reject("CREATE_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun initialize(configJson: String?, promise: Promise) {
        scope.launch {
            try {
                if (backendHandle == 0L) {
                    // Auto-create ONNX backend if not created
                    backendHandle = RunAnywhereBridge.nativeCreateBackend("onnx")
                }

                val result = RunAnywhereBridge.nativeInitialize(backendHandle, configJson)
                if (result == 0) { // RA_SUCCESS
                    isInitialized = true
                    promise.resolve(true)
                } else {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    promise.reject("INIT_FAILED", error)
                }
            } catch (e: Exception) {
                promise.reject("INIT_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun destroy(promise: Promise) {
        scope.launch {
            try {
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeDestroy(backendHandle)
                    backendHandle = 0
                    isInitialized = false
                }
                promise.resolve(true)
            } catch (e: Exception) {
                promise.reject("DESTROY_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun isInitialized(promise: Promise) {
        promise.resolve(isInitialized && backendHandle != 0L &&
            RunAnywhereBridge.nativeIsInitialized(backendHandle))
    }

    @ReactMethod
    fun getBackendInfo(promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()
                val info = RunAnywhereBridge.nativeGetBackendInfo(backendHandle)
                promise.resolve(info)
            } catch (e: Exception) {
                promise.reject("ERROR", e.message, e)
            }
        }
    }

    // =============================================================================
    // STT (Speech-to-Text)
    // =============================================================================

    @ReactMethod
    fun loadSTTModel(modelPath: String, modelType: String, configJson: String?, promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()
                val result = RunAnywhereBridge.nativeSTTLoadModel(
                    backendHandle, modelPath, modelType, configJson
                )
                if (result == 0) {
                    promise.resolve(true)
                } else {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    promise.reject("STT_LOAD_FAILED", error)
                }
            } catch (e: Exception) {
                promise.reject("STT_LOAD_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun isSTTModelLoaded(promise: Promise) {
        try {
            val loaded = backendHandle != 0L &&
                RunAnywhereBridge.nativeSTTIsModelLoaded(backendHandle)
            promise.resolve(loaded)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun unloadSTTModel(promise: Promise) {
        scope.launch {
            try {
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeSTTUnloadModel(backendHandle)
                }
                promise.resolve(true)
            } catch (e: Exception) {
                promise.reject("ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun transcribe(audioBase64: String, sampleRate: Int, language: String?, promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()

                // Decode base64 to float array
                val audioBytes = Base64.decode(audioBase64, Base64.DEFAULT)
                val audioSamples = bytesToFloatArray(audioBytes)

                val resultJson = RunAnywhereBridge.nativeSTTTranscribe(
                    backendHandle, audioSamples, sampleRate, language
                )

                promise.resolve(resultJson ?: "{}")
            } catch (e: Exception) {
                promise.reject("TRANSCRIBE_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun createSTTStream(configJson: String?, promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()
                val streamHandle = RunAnywhereBridge.nativeSTTCreateStream(backendHandle, configJson)
                promise.resolve(streamHandle.toDouble())
            } catch (e: Exception) {
                promise.reject("STREAM_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun feedSTTAudio(streamId: Double, audioBase64: String, sampleRate: Int, promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()
                val streamHandle = streamId.toLong()
                val audioBytes = Base64.decode(audioBase64, Base64.DEFAULT)
                val audioSamples = bytesToFloatArray(audioBytes)

                val result = RunAnywhereBridge.nativeSTTFeedAudio(
                    backendHandle, streamHandle, audioSamples, sampleRate
                )
                promise.resolve(result == 0)
            } catch (e: Exception) {
                promise.reject("FEED_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun decodeSTT(streamId: Double, promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()
                val streamHandle = streamId.toLong()
                val result = RunAnywhereBridge.nativeSTTDecode(backendHandle, streamHandle)
                promise.resolve(result ?: "{}")
            } catch (e: Exception) {
                promise.reject("DECODE_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun destroySTTStream(streamId: Double, promise: Promise) {
        scope.launch {
            try {
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeSTTDestroyStream(backendHandle, streamId.toLong())
                }
                promise.resolve(true)
            } catch (e: Exception) {
                promise.reject("ERROR", e.message, e)
            }
        }
    }

    // =============================================================================
    // TTS (Text-to-Speech)
    // =============================================================================

    @ReactMethod
    fun loadTTSModel(modelPath: String, modelType: String, configJson: String?, promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()
                val result = RunAnywhereBridge.nativeTTSLoadModel(
                    backendHandle, modelPath, modelType, configJson
                )
                if (result == 0) {
                    promise.resolve(true)
                } else {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    promise.reject("TTS_LOAD_FAILED", error)
                }
            } catch (e: Exception) {
                promise.reject("TTS_LOAD_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun isTTSModelLoaded(promise: Promise) {
        try {
            val loaded = backendHandle != 0L &&
                RunAnywhereBridge.nativeTTSIsModelLoaded(backendHandle)
            promise.resolve(loaded)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun unloadTTSModel(promise: Promise) {
        scope.launch {
            try {
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeTTSUnloadModel(backendHandle)
                }
                promise.resolve(true)
            } catch (e: Exception) {
                promise.reject("ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun synthesize(text: String, voiceId: String?, speedRate: Double, pitchShift: Double, promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()

                val result = RunAnywhereBridge.nativeTTSSynthesize(
                    backendHandle, text, voiceId,
                    speedRate.toFloat(), pitchShift.toFloat()
                )

                if (result != null) {
                    // Convert to JSON response with base64 audio
                    val audioBase64 = Base64.encodeToString(
                        floatArrayToBytes(result.samples),
                        Base64.NO_WRAP
                    )
                    val response = JSONObject().apply {
                        put("audio", audioBase64)
                        put("sampleRate", result.sampleRate)
                        put("numSamples", result.samples.size)
                    }
                    promise.resolve(response.toString())
                } else {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    promise.reject("SYNTHESIZE_FAILED", error)
                }
            } catch (e: Exception) {
                promise.reject("SYNTHESIZE_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun getVoices(promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()
                val voices = RunAnywhereBridge.nativeTTSGetVoices(backendHandle)
                promise.resolve(voices ?: "[]")
            } catch (e: Exception) {
                promise.reject("ERROR", e.message, e)
            }
        }
    }

    // =============================================================================
    // VAD (Voice Activity Detection)
    // =============================================================================

    @ReactMethod
    fun loadVADModel(modelPath: String?, configJson: String?, promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()
                val result = RunAnywhereBridge.nativeVADLoadModel(backendHandle, modelPath, configJson)
                if (result == 0) {
                    promise.resolve(true)
                } else {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    promise.reject("VAD_LOAD_FAILED", error)
                }
            } catch (e: Exception) {
                promise.reject("VAD_LOAD_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun isVADModelLoaded(promise: Promise) {
        try {
            val loaded = backendHandle != 0L &&
                RunAnywhereBridge.nativeVADIsModelLoaded(backendHandle)
            promise.resolve(loaded)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun processVAD(audioBase64: String, sampleRate: Int, promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()
                val audioBytes = Base64.decode(audioBase64, Base64.DEFAULT)
                val audioSamples = bytesToFloatArray(audioBytes)

                val result = RunAnywhereBridge.nativeVADProcess(backendHandle, audioSamples, sampleRate)
                if (result != null) {
                    val response = JSONObject().apply {
                        put("isSpeech", result.isSpeech)
                        put("probability", result.probability.toDouble())
                    }
                    promise.resolve(response.toString())
                } else {
                    promise.reject("VAD_FAILED", "VAD processing failed")
                }
            } catch (e: Exception) {
                promise.reject("VAD_ERROR", e.message, e)
            }
        }
    }

    // =============================================================================
    // Text Generation (LLM)
    // =============================================================================

    @ReactMethod
    fun loadTextModel(modelPath: String, configJson: String?, promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()
                val result = RunAnywhereBridge.nativeTextLoadModel(backendHandle, modelPath, configJson)
                if (result == 0) {
                    promise.resolve(true)
                } else {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    promise.reject("TEXT_LOAD_FAILED", error)
                }
            } catch (e: Exception) {
                promise.reject("TEXT_LOAD_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun isTextModelLoaded(promise: Promise) {
        try {
            val loaded = backendHandle != 0L &&
                RunAnywhereBridge.nativeTextIsModelLoaded(backendHandle)
            promise.resolve(loaded)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun generate(prompt: String, systemPrompt: String?, maxTokens: Int, temperature: Double, promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()
                val result = RunAnywhereBridge.nativeTextGenerate(
                    backendHandle, prompt, systemPrompt,
                    maxTokens, temperature.toFloat()
                )
                promise.resolve(result ?: "{}")
            } catch (e: Exception) {
                promise.reject("GENERATE_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun cancelGeneration(promise: Promise) {
        try {
            if (backendHandle != 0L) {
                RunAnywhereBridge.nativeTextCancel(backendHandle)
            }
            promise.resolve(true)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    // =============================================================================
    // Embeddings
    // =============================================================================

    @ReactMethod
    fun loadEmbeddingModel(modelPath: String, configJson: String?, promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()
                val result = RunAnywhereBridge.nativeEmbedLoadModel(backendHandle, modelPath, configJson)
                if (result == 0) {
                    promise.resolve(true)
                } else {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    promise.reject("EMBED_LOAD_FAILED", error)
                }
            } catch (e: Exception) {
                promise.reject("EMBED_LOAD_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun embedText(text: String, promise: Promise) {
        scope.launch {
            try {
                ensureInitialized()
                val embedding = RunAnywhereBridge.nativeEmbedText(backendHandle, text)
                if (embedding != null) {
                    val array = Arguments.createArray()
                    embedding.forEach { array.pushDouble(it.toDouble()) }
                    promise.resolve(array)
                } else {
                    promise.reject("EMBED_FAILED", "Embedding failed")
                }
            } catch (e: Exception) {
                promise.reject("EMBED_ERROR", e.message, e)
            }
        }
    }

    // =============================================================================
    // Utility Methods
    // =============================================================================

    @ReactMethod
    fun getVersion(promise: Promise) {
        try {
            val version = RunAnywhereBridge.nativeGetVersion()
            promise.resolve(version)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun getLastError(promise: Promise) {
        try {
            val error = RunAnywhereBridge.nativeGetLastError()
            promise.resolve(error)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun getAvailableBackends(promise: Promise) {
        try {
            val backends = RunAnywhereBridge.nativeGetAvailableBackends()
            val array = Arguments.createArray()
            backends?.forEach { array.pushString(it) }
            promise.resolve(array)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    // Required for RN
    @ReactMethod
    fun addListener(eventName: String) {
        // Required for RN event emitter
    }

    @ReactMethod
    fun removeListeners(count: Int) {
        // Required for RN event emitter
    }

    // =============================================================================
    // Private Helpers
    // =============================================================================

    private fun ensureInitialized() {
        if (backendHandle == 0L) {
            throw IllegalStateException("Backend not initialized. Call initialize() first.")
        }
    }

    private fun bytesToFloatArray(bytes: ByteArray): FloatArray {
        // Assuming bytes are float32 little-endian
        val floats = FloatArray(bytes.size / 4)
        val buffer = java.nio.ByteBuffer.wrap(bytes)
        buffer.order(java.nio.ByteOrder.LITTLE_ENDIAN)
        for (i in floats.indices) {
            floats[i] = buffer.getFloat()
        }
        return floats
    }

    private fun floatArrayToBytes(floats: FloatArray): ByteArray {
        val bytes = ByteArray(floats.size * 4)
        val buffer = java.nio.ByteBuffer.wrap(bytes)
        buffer.order(java.nio.ByteOrder.LITTLE_ENDIAN)
        floats.forEach { buffer.putFloat(it) }
        return bytes
    }
}
