package com.runanywhere.reactnative

import com.facebook.react.bridge.*
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.modules.core.DeviceEventManagerModule
import kotlinx.coroutines.*
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import org.json.JSONArray
import com.runanywhere.sdk.core.onnx.RunAnywhereBridge
import java.io.File
import java.io.FileOutputStream
import java.net.URL
import java.net.HttpURLConnection
import java.util.concurrent.ConcurrentHashMap

/**
 * RunAnywhere React Native Module
 *
 * Bridges React Native to the native RunAnywhere C library via JNI.
 * Uses the RunAnywhereBridge JNI wrapper from runanywhere-core.
 *
 * IMPORTANT: Dual-backend architecture:
 * - llamaBackendHandle: Used for LlamaCPP (GGUF models, LLM text generation)
 * - onnxBackendHandle: Used for ONNX (Sherpa-ONNX STT, TTS, VAD)
 */
@ReactModule(name = RunAnywhereModule.NAME)
class RunAnywhereModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    companion object {
        const val NAME = "RunAnywhere"
        private const val TAG = "RunAnywhere"
        private const val MIN_GGUF_SIZE = 1L * 1024 * 1024 // 1MB minimum for GGUF files

        init {
            try {
                // Load native libraries in order
                Log.d(TAG, "Loading native libraries...")
                System.loadLibrary("c++_shared")
                System.loadLibrary("onnxruntime")
                System.loadLibrary("runanywhere_bridge")
                System.loadLibrary("runanywhere_jni")
                Log.d(TAG, "Native libraries loaded successfully")
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "Failed to load native libraries: ${e.message}")
            }
        }
    }

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    // Dual-backend architecture (matches iOS implementation)
    private var llamaBackendHandle: Long = 0  // For LlamaCPP (GGUF LLM models)
    private var onnxBackendHandle: Long = 0   // For ONNX (STT, TTS, VAD via Sherpa-ONNX)

    // Legacy support - maps to appropriate backend based on usage
    private var backendHandle: Long = 0
    private var isInitialized = false
    private val downloadJobs = ConcurrentHashMap<String, Job>()

    // Model catalog - matches iOS implementation
    private val modelCatalog = mapOf(
        "whisper-tiny-en" to mapOf(
            "id" to "whisper-tiny-en",
            "name" to "Whisper Tiny English",
            "description" to "Fast English speech recognition",
            "category" to "stt",
            "modality" to "stt",
            "size" to 75000000L,
            "downloadUrl" to "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2",
            "format" to "sherpa-onnx",
            "modelType" to "whisper"
        ),
        "whisper-base-en" to mapOf(
            "id" to "whisper-base-en",
            "name" to "Whisper Base English",
            "description" to "Balanced English speech recognition",
            "category" to "stt",
            "modality" to "stt",
            "size" to 150000000L,
            "downloadUrl" to "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.en.tar.bz2",
            "format" to "sherpa-onnx",
            "modelType" to "whisper"
        ),
        "silero-vad" to mapOf(
            "id" to "silero-vad",
            "name" to "Silero VAD",
            "description" to "Voice Activity Detection",
            "category" to "vad",
            "modality" to "vad",
            "size" to 2000000L,
            "downloadUrl" to "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx",
            "format" to "onnx",
            "modelType" to "silero"
        ),
        "piper-en-us-lessac-medium" to mapOf(
            "id" to "piper-en-us-lessac-medium",
            "name" to "Piper TTS (US English - Medium)",
            "description" to "High quality US English TTS voice",
            "category" to "tts",
            "modality" to "tts",
            "size" to 65000000L,
            "downloadUrl" to "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2",
            "format" to "sherpa-onnx",
            "modelType" to "piper"
        ),
        "piper-en-gb-alba-medium" to mapOf(
            "id" to "piper-en-gb-alba-medium",
            "name" to "Piper TTS (British English)",
            "description" to "British English TTS voice",
            "category" to "tts",
            "modality" to "tts",
            "size" to 65000000L,
            "downloadUrl" to "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2",
            "format" to "sherpa-onnx",
            "modelType" to "piper"
        ),
        "qwen2-0.5b-instruct-q4" to mapOf(
            "id" to "qwen2-0.5b-instruct-q4",
            "name" to "Qwen2 0.5B Instruct (Q4)",
            "description" to "Small but capable chat model for on-device inference",
            "category" to "llm",
            "modality" to "llm",
            "size" to 400000000L,
            "downloadUrl" to "https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF/resolve/main/qwen2-0_5b-instruct-q4_0.gguf",
            "format" to "gguf",
            "modelType" to "llama",
            "contextLength" to 32768
        ),
        "tinyllama-1.1b-chat-q4" to mapOf(
            "id" to "tinyllama-1.1b-chat-q4",
            "name" to "TinyLlama 1.1B Chat (Q4)",
            "description" to "Efficient chat model optimized for mobile",
            "category" to "llm",
            "modality" to "llm",
            "size" to 670000000L,
            "downloadUrl" to "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
            "format" to "gguf",
            "modelType" to "llama",
            "contextLength" to 2048
        ),
        "smollm-135m-instruct-q8" to mapOf(
            "id" to "smollm-135m-instruct-q8",
            "name" to "SmolLM 135M Instruct (Q8)",
            "description" to "Ultra-small model for quick responses",
            "category" to "llm",
            "modality" to "llm",
            "size" to 150000000L,
            "downloadUrl" to "https://huggingface.co/HuggingFaceTB/smollm-135M-instruct-v0.2-GGUF/resolve/main/smollm-135m-instruct-v0.2-q8_0.gguf",
            "format" to "gguf",
            "modelType" to "llama",
            "contextLength" to 2048
        )
    )

    override fun getName(): String = NAME

    override fun invalidate() {
        scope.cancel()
        // Clean up both backends
        if (llamaBackendHandle != 0L) {
            RunAnywhereBridge.nativeDestroy(llamaBackendHandle)
            llamaBackendHandle = 0
        }
        if (onnxBackendHandle != 0L) {
            RunAnywhereBridge.nativeDestroy(onnxBackendHandle)
            onnxBackendHandle = 0
        }
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
                Log.d(TAG, "createBackend called with name: $name")
                val isLlamaCpp = name == "llamacpp"

                if (isLlamaCpp) {
                    // LlamaCPP backend for GGUF LLM models
                    if (llamaBackendHandle != 0L) {
                        RunAnywhereBridge.nativeDestroy(llamaBackendHandle)
                    }
                    llamaBackendHandle = RunAnywhereBridge.nativeCreateBackend(name)
                    Log.d(TAG, "LlamaCPP backend created: ${if (llamaBackendHandle != 0L) "SUCCESS" else "FAILED"}")
                    promise.resolve(llamaBackendHandle != 0L)
                } else {
                    // ONNX backend for STT, TTS, VAD (Sherpa-ONNX)
                    if (onnxBackendHandle != 0L) {
                        RunAnywhereBridge.nativeDestroy(onnxBackendHandle)
                    }
                    onnxBackendHandle = RunAnywhereBridge.nativeCreateBackend(name)
                    // Also set legacy backendHandle for compatibility
                    backendHandle = onnxBackendHandle
                    Log.d(TAG, "ONNX backend created: ${if (onnxBackendHandle != 0L) "SUCCESS" else "FAILED"}")
                    promise.resolve(onnxBackendHandle != 0L)
                }
            } catch (e: Exception) {
                Log.e(TAG, "createBackend error: ${e.message}", e)
                promise.reject("CREATE_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun initialize(configJson: String?, promise: Promise) {
        scope.launch {
            try {
                Log.d(TAG, "initialize called")

                // Initialize LlamaCPP backend if it exists
                if (llamaBackendHandle != 0L) {
                    val llamaResult = RunAnywhereBridge.nativeInitialize(llamaBackendHandle, configJson)
                    Log.d(TAG, "initialize llamacpp backend result: $llamaResult (0=SUCCESS)")
                    if (llamaResult != 0) {
                        val error = RunAnywhereBridge.nativeGetLastError()
                        Log.e(TAG, "LlamaCPP init failed: $error")
                    }
                }

                // Initialize ONNX backend if it exists (or auto-create if neither exists)
                if (onnxBackendHandle == 0L && llamaBackendHandle == 0L) {
                    // Auto-create ONNX backend if nothing exists
                    Log.d(TAG, "No backend exists, auto-creating ONNX backend")
                    onnxBackendHandle = RunAnywhereBridge.nativeCreateBackend("onnx")
                    backendHandle = onnxBackendHandle
                }

                if (onnxBackendHandle != 0L) {
                    val onnxResult = RunAnywhereBridge.nativeInitialize(onnxBackendHandle, configJson)
                    Log.d(TAG, "initialize onnx backend result: $onnxResult (0=SUCCESS)")
                    if (onnxResult != 0) {
                        val error = RunAnywhereBridge.nativeGetLastError()
                        Log.e(TAG, "ONNX init failed: $error")
                    }
                }

                isInitialized = true
                promise.resolve(true)
            } catch (e: Exception) {
                Log.e(TAG, "initialize error: ${e.message}", e)
                promise.reject("INIT_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun destroy(promise: Promise) {
        scope.launch {
            try {
                if (llamaBackendHandle != 0L) {
                    RunAnywhereBridge.nativeDestroy(llamaBackendHandle)
                    llamaBackendHandle = 0
                }
                if (onnxBackendHandle != 0L) {
                    RunAnywhereBridge.nativeDestroy(onnxBackendHandle)
                    onnxBackendHandle = 0
                }
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeDestroy(backendHandle)
                    backendHandle = 0
                }
                isInitialized = false
                promise.resolve(true)
            } catch (e: Exception) {
                promise.reject("DESTROY_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun isInitialized(promise: Promise) {
        val llamaInit = llamaBackendHandle != 0L && RunAnywhereBridge.nativeIsInitialized(llamaBackendHandle)
        val onnxInit = onnxBackendHandle != 0L && RunAnywhereBridge.nativeIsInitialized(onnxBackendHandle)
        promise.resolve(isInitialized && (llamaInit || onnxInit))
    }

    @ReactMethod
    fun getBackendInfo(promise: Promise) {
        scope.launch {
            try {
                Log.d(TAG, "getBackendInfo called")
                val result = JSONObject()

                // Get LlamaCPP backend info if available
                if (llamaBackendHandle != 0L) {
                    val llamaInfo = RunAnywhereBridge.nativeGetBackendInfo(llamaBackendHandle)
                    if (llamaInfo != null) {
                        val llamaJson = JSONObject(llamaInfo)
                        for (key in llamaJson.keys()) {
                            result.put(key, llamaJson.get(key))
                        }
                    }
                }

                // Get ONNX backend info if available
                if (onnxBackendHandle != 0L) {
                    val onnxInfo = RunAnywhereBridge.nativeGetBackendInfo(onnxBackendHandle)
                    if (onnxInfo != null) {
                        val onnxJson = JSONObject(onnxInfo)
                        for (key in onnxJson.keys()) {
                            result.put(key, onnxJson.get(key))
                        }
                    }
                }

                Log.d(TAG, "getBackendInfo: $result")
                promise.resolve(result.toString())
            } catch (e: Exception) {
                Log.e(TAG, "getBackendInfo error: ${e.message}", e)
                promise.reject("ERROR", e.message, e)
            }
        }
    }

    // =============================================================================
    // STT (Speech-to-Text) - Uses ONNX backend (Sherpa-ONNX)
    // =============================================================================

    /**
     * Ensures ONNX backend is available for STT/TTS/VAD operations
     */
    private suspend fun ensureOnnxBackend(): Long {
        if (onnxBackendHandle == 0L) {
            Log.d(TAG, "Creating ONNX backend for STT/TTS/VAD")
            onnxBackendHandle = RunAnywhereBridge.nativeCreateBackend("onnx")
            val initResult = RunAnywhereBridge.nativeInitialize(onnxBackendHandle, null)
            Log.d(TAG, "ONNX backend init result: $initResult (0=SUCCESS)")
            backendHandle = onnxBackendHandle
        }
        return onnxBackendHandle
    }

    @ReactMethod
    fun loadSTTModel(modelPath: String, modelType: String, configJson: String?, promise: Promise) {
        scope.launch {
            try {
                Log.d(TAG, "loadSTTModel called - path: $modelPath, type: $modelType")

                // Ensure ONNX backend is available
                val handle = ensureOnnxBackend()
                if (handle == 0L) {
                    promise.reject("BACKEND_ERROR", "Failed to create ONNX backend")
                    return@launch
                }

                // Check path exists
                val file = File(modelPath)
                if (!file.exists()) {
                    Log.e(TAG, "loadSTTModel: Path does not exist: $modelPath")
                    promise.reject("FILE_NOT_FOUND", "Model path does not exist: $modelPath")
                    return@launch
                }

                // Detect actual model type for Sherpa-ONNX (matching iOS pattern)
                // For Whisper models, we need to pass "whisper" as the type
                val actualModelType = when {
                    modelPath.contains("whisper", ignoreCase = true) -> "whisper"
                    modelPath.contains("zipformer", ignoreCase = true) -> "zipformer"
                    modelPath.contains("paraformer", ignoreCase = true) -> "paraformer"
                    else -> modelType
                }
                Log.d(TAG, "loadSTTModel: Using model type '$actualModelType'")

                val result = RunAnywhereBridge.nativeSTTLoadModel(
                    handle, modelPath, actualModelType, null // Always pass null for config (per iOS pattern)
                )

                Log.d(TAG, "loadSTTModel result: $result (0=SUCCESS)")
                if (result == 0) {
                    promise.resolve(true)
                } else {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    Log.e(TAG, "loadSTTModel failed: $error")
                    promise.reject("STT_LOAD_FAILED", error ?: "Unknown error (code: $result)")
                }
            } catch (e: Exception) {
                Log.e(TAG, "loadSTTModel error: ${e.message}", e)
                promise.reject("STT_LOAD_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun isSTTModelLoaded(promise: Promise) {
        try {
            val loaded = onnxBackendHandle != 0L &&
                RunAnywhereBridge.nativeSTTIsModelLoaded(onnxBackendHandle)
            promise.resolve(loaded)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun unloadSTTModel(promise: Promise) {
        scope.launch {
            try {
                if (onnxBackendHandle != 0L) {
                    RunAnywhereBridge.nativeSTTUnloadModel(onnxBackendHandle)
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
                val handle = ensureOnnxBackend()
                if (handle == 0L) {
                    promise.reject("BACKEND_ERROR", "ONNX backend not available")
                    return@launch
                }

                // Decode base64 to float array
                val audioBytes = Base64.decode(audioBase64, Base64.DEFAULT)
                val audioSamples = bytesToFloatArray(audioBytes)

                val resultJson = RunAnywhereBridge.nativeSTTTranscribe(
                    handle, audioSamples, sampleRate, language
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
                val handle = ensureOnnxBackend()
                if (handle == 0L) {
                    promise.reject("BACKEND_ERROR", "ONNX backend not available")
                    return@launch
                }
                val streamHandle = RunAnywhereBridge.nativeSTTCreateStream(handle, configJson)
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
                val handle = ensureOnnxBackend()
                if (handle == 0L) {
                    promise.reject("BACKEND_ERROR", "ONNX backend not available")
                    return@launch
                }
                val streamHandle = streamId.toLong()
                val audioBytes = Base64.decode(audioBase64, Base64.DEFAULT)
                val audioSamples = bytesToFloatArray(audioBytes)

                val result = RunAnywhereBridge.nativeSTTFeedAudio(
                    handle, streamHandle, audioSamples, sampleRate
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
                val handle = ensureOnnxBackend()
                if (handle == 0L) {
                    promise.reject("BACKEND_ERROR", "ONNX backend not available")
                    return@launch
                }
                val streamHandle = streamId.toLong()
                val result = RunAnywhereBridge.nativeSTTDecode(handle, streamHandle)
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
                if (onnxBackendHandle != 0L) {
                    RunAnywhereBridge.nativeSTTDestroyStream(onnxBackendHandle, streamId.toLong())
                }
                promise.resolve(true)
            } catch (e: Exception) {
                promise.reject("ERROR", e.message, e)
            }
        }
    }

    // =============================================================================
    // TTS (Text-to-Speech) - Uses ONNX backend (Sherpa-ONNX with VITS)
    // =============================================================================

    @ReactMethod
    fun loadTTSModel(modelPath: String, modelType: String, configJson: String?, promise: Promise) {
        scope.launch {
            try {
                Log.d(TAG, "loadTTSModel called - path: $modelPath, type: $modelType")

                // Ensure ONNX backend is available
                val handle = ensureOnnxBackend()
                if (handle == 0L) {
                    promise.reject("BACKEND_ERROR", "Failed to create ONNX backend")
                    return@launch
                }

                // Check path exists
                val file = File(modelPath)
                if (!file.exists()) {
                    Log.e(TAG, "loadTTSModel: Path does not exist: $modelPath")
                    promise.reject("FILE_NOT_FOUND", "Model path does not exist: $modelPath")
                    return@launch
                }

                // IMPORTANT: Always use "vits" model type for Sherpa-ONNX TTS (per Swift SDK pattern)
                // The Swift SDK hardcodes "vits" for all Piper TTS models
                Log.d(TAG, "loadTTSModel: Using hardcoded model type 'vits' (Sherpa-ONNX pattern)")
                val result = RunAnywhereBridge.nativeTTSLoadModel(
                    handle, modelPath, "vits", null // Hardcoded "vits" per Swift SDK
                )

                Log.d(TAG, "loadTTSModel result: $result (0=SUCCESS)")
                if (result == 0) {
                    promise.resolve(true)
                } else {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    Log.e(TAG, "loadTTSModel failed: $error")
                    promise.reject("TTS_LOAD_FAILED", error ?: "Unknown error (code: $result)")
                }
            } catch (e: Exception) {
                Log.e(TAG, "loadTTSModel error: ${e.message}", e)
                promise.reject("TTS_LOAD_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun isTTSModelLoaded(promise: Promise) {
        try {
            val loaded = onnxBackendHandle != 0L &&
                RunAnywhereBridge.nativeTTSIsModelLoaded(onnxBackendHandle)
            promise.resolve(loaded)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun unloadTTSModel(promise: Promise) {
        scope.launch {
            try {
                if (onnxBackendHandle != 0L) {
                    RunAnywhereBridge.nativeTTSUnloadModel(onnxBackendHandle)
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
                val handle = ensureOnnxBackend()
                if (handle == 0L) {
                    promise.reject("BACKEND_ERROR", "ONNX backend not available")
                    return@launch
                }

                val result = RunAnywhereBridge.nativeTTSSynthesize(
                    handle, text, voiceId,
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
                val handle = ensureOnnxBackend()
                if (handle == 0L) {
                    promise.reject("BACKEND_ERROR", "ONNX backend not available")
                    return@launch
                }
                val voices = RunAnywhereBridge.nativeTTSGetVoices(handle)
                promise.resolve(voices ?: "[]")
            } catch (e: Exception) {
                promise.reject("ERROR", e.message, e)
            }
        }
    }

    // =============================================================================
    // VAD (Voice Activity Detection) - Uses ONNX backend (Sherpa-ONNX Silero VAD)
    // =============================================================================

    @ReactMethod
    fun loadVADModel(modelPath: String?, configJson: String?, promise: Promise) {
        scope.launch {
            try {
                Log.d(TAG, "loadVADModel called - path: $modelPath")

                // Ensure ONNX backend is available
                val handle = ensureOnnxBackend()
                if (handle == 0L) {
                    promise.reject("BACKEND_ERROR", "Failed to create ONNX backend")
                    return@launch
                }

                // Check path exists if provided
                if (modelPath != null) {
                    val file = File(modelPath)
                    if (!file.exists()) {
                        Log.e(TAG, "loadVADModel: Path does not exist: $modelPath")
                        promise.reject("FILE_NOT_FOUND", "Model path does not exist: $modelPath")
                        return@launch
                    }
                }

                val result = RunAnywhereBridge.nativeVADLoadModel(handle, modelPath, null)
                Log.d(TAG, "loadVADModel result: $result (0=SUCCESS)")
                if (result == 0) {
                    promise.resolve(true)
                } else {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    Log.e(TAG, "loadVADModel failed: $error")
                    promise.reject("VAD_LOAD_FAILED", error ?: "Unknown error (code: $result)")
                }
            } catch (e: Exception) {
                Log.e(TAG, "loadVADModel error: ${e.message}", e)
                promise.reject("VAD_LOAD_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun isVADModelLoaded(promise: Promise) {
        try {
            val loaded = onnxBackendHandle != 0L &&
                RunAnywhereBridge.nativeVADIsModelLoaded(onnxBackendHandle)
            promise.resolve(loaded)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun processVAD(audioBase64: String, sampleRate: Int, promise: Promise) {
        scope.launch {
            try {
                val handle = ensureOnnxBackend()
                if (handle == 0L) {
                    promise.reject("BACKEND_ERROR", "ONNX backend not available")
                    return@launch
                }

                val audioBytes = Base64.decode(audioBase64, Base64.DEFAULT)
                val audioSamples = bytesToFloatArray(audioBytes)

                val result = RunAnywhereBridge.nativeVADProcess(handle, audioSamples, sampleRate)
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
    // Text Generation (LLM) - Uses LlamaCPP backend for GGUF models
    // =============================================================================

    /**
     * Ensures LlamaCPP backend is available for LLM operations
     */
    private suspend fun ensureLlamaCppBackend(): Long {
        if (llamaBackendHandle == 0L) {
            Log.d(TAG, "Creating LlamaCPP backend for LLM")
            llamaBackendHandle = RunAnywhereBridge.nativeCreateBackend("llamacpp")
            val initResult = RunAnywhereBridge.nativeInitialize(llamaBackendHandle, null)
            Log.d(TAG, "LlamaCPP backend init result: $initResult (0=SUCCESS)")
        }
        return llamaBackendHandle
    }

    @ReactMethod
    fun loadTextModel(modelPath: String, configJson: String?, promise: Promise) {
        scope.launch {
            try {
                Log.d(TAG, "loadTextModel called - path: $modelPath")

                // Check path exists
                val file = File(modelPath)
                if (!file.exists()) {
                    Log.e(TAG, "loadTextModel: Path does not exist: $modelPath")
                    promise.reject("FILE_NOT_FOUND", "Model path does not exist: $modelPath")
                    return@launch
                }

                val isGGUF = modelPath.endsWith(".gguf", ignoreCase = true)
                Log.d(TAG, "loadTextModel: File size: ${file.length()} bytes, isGGUF: $isGGUF")

                // Check for corrupted GGUF files (matching iOS pattern)
                if (isGGUF && file.length() < MIN_GGUF_SIZE) {
                    Log.e(TAG, "loadTextModel: Model file appears corrupted (size: ${file.length()} bytes)")
                    promise.reject(
                        "MODEL_CORRUPTED",
                        "Model file appears corrupted or incomplete (size: ${file.length()} bytes). " +
                        "Please delete and re-download the model."
                    )
                    return@launch
                }

                // Use LlamaCPP backend for GGUF models
                if (isGGUF) {
                    Log.d(TAG, "loadTextModel: Creating/using LlamaCPP backend for GGUF model")
                    val handle = ensureLlamaCppBackend()
                    if (handle == 0L) {
                        promise.reject("BACKEND_ERROR", "Failed to create LlamaCPP backend")
                        return@launch
                    }

                    val result = RunAnywhereBridge.nativeTextLoadModel(handle, modelPath, configJson)
                    Log.d(TAG, "loadTextModel result (LlamaCPP): $result (0=SUCCESS)")
                    if (result == 0) {
                        promise.resolve(true)
                    } else {
                        val error = RunAnywhereBridge.nativeGetLastError()
                        Log.e(TAG, "loadTextModel failed: $error")
                        promise.reject("TEXT_LOAD_FAILED", error ?: "Unknown error (code: $result)")
                    }
                } else {
                    // Use ONNX backend for non-GGUF models
                    Log.d(TAG, "loadTextModel: Using ONNX backend for non-GGUF model")
                    val handle = ensureOnnxBackend()
                    if (handle == 0L) {
                        promise.reject("BACKEND_ERROR", "Failed to create ONNX backend")
                        return@launch
                    }

                    val result = RunAnywhereBridge.nativeTextLoadModel(handle, modelPath, configJson)
                    Log.d(TAG, "loadTextModel result (ONNX): $result (0=SUCCESS)")
                    if (result == 0) {
                        promise.resolve(true)
                    } else {
                        val error = RunAnywhereBridge.nativeGetLastError()
                        Log.e(TAG, "loadTextModel failed: $error")
                        promise.reject("TEXT_LOAD_FAILED", error ?: "Unknown error (code: $result)")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "loadTextModel error: ${e.message}", e)
                promise.reject("TEXT_LOAD_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun isTextModelLoaded(promise: Promise) {
        try {
            // Check both backends
            val llamaLoaded = llamaBackendHandle != 0L &&
                RunAnywhereBridge.nativeTextIsModelLoaded(llamaBackendHandle)
            val onnxLoaded = onnxBackendHandle != 0L &&
                RunAnywhereBridge.nativeTextIsModelLoaded(onnxBackendHandle)
            promise.resolve(llamaLoaded || onnxLoaded)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun generate(prompt: String, systemPrompt: String?, maxTokens: Int, temperature: Double, promise: Promise) {
        scope.launch {
            try {
                Log.d(TAG, "generate called - prompt: ${prompt.take(50)}..., maxTokens: $maxTokens, temp: $temperature")

                // Try LlamaCPP backend first (for GGUF models)
                val handle = if (llamaBackendHandle != 0L &&
                    RunAnywhereBridge.nativeTextIsModelLoaded(llamaBackendHandle)) {
                    Log.d(TAG, "generate: Using LlamaCPP backend")
                    llamaBackendHandle
                } else if (onnxBackendHandle != 0L &&
                    RunAnywhereBridge.nativeTextIsModelLoaded(onnxBackendHandle)) {
                    Log.d(TAG, "generate: Using ONNX backend")
                    onnxBackendHandle
                } else {
                    Log.e(TAG, "generate: No model loaded")
                    promise.reject("NO_MODEL", "No text model is loaded")
                    return@launch
                }

                Log.d(TAG, "generate: Calling nativeTextGenerate...")
                val result = RunAnywhereBridge.nativeTextGenerate(
                    handle, prompt, systemPrompt,
                    maxTokens, temperature.toFloat()
                )
                Log.d(TAG, "generate: Result received, length: ${result?.length ?: 0}")
                promise.resolve(result ?: "{}")
            } catch (e: Exception) {
                Log.e(TAG, "generate error: ${e.message}", e)
                promise.reject("GENERATE_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun cancelGeneration(promise: Promise) {
        try {
            if (llamaBackendHandle != 0L) {
                RunAnywhereBridge.nativeTextCancel(llamaBackendHandle)
            }
            if (onnxBackendHandle != 0L) {
                RunAnywhereBridge.nativeTextCancel(onnxBackendHandle)
            }
            promise.resolve(true)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    // =============================================================================
    // Embeddings - Uses ONNX backend
    // =============================================================================

    @ReactMethod
    fun loadEmbeddingModel(modelPath: String, configJson: String?, promise: Promise) {
        scope.launch {
            try {
                Log.d(TAG, "loadEmbeddingModel called - path: $modelPath")

                val handle = ensureOnnxBackend()
                if (handle == 0L) {
                    promise.reject("BACKEND_ERROR", "Failed to create ONNX backend")
                    return@launch
                }

                val result = RunAnywhereBridge.nativeEmbedLoadModel(handle, modelPath, configJson)
                Log.d(TAG, "loadEmbeddingModel result: $result (0=SUCCESS)")
                if (result == 0) {
                    promise.resolve(true)
                } else {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    Log.e(TAG, "loadEmbeddingModel failed: $error")
                    promise.reject("EMBED_LOAD_FAILED", error ?: "Unknown error (code: $result)")
                }
            } catch (e: Exception) {
                Log.e(TAG, "loadEmbeddingModel error: ${e.message}", e)
                promise.reject("EMBED_LOAD_ERROR", e.message, e)
            }
        }
    }

    @ReactMethod
    fun embedText(text: String, promise: Promise) {
        scope.launch {
            try {
                val handle = ensureOnnxBackend()
                if (handle == 0L) {
                    promise.reject("BACKEND_ERROR", "ONNX backend not available")
                    return@launch
                }

                val embedding = RunAnywhereBridge.nativeEmbedText(handle, text)
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
    // Model Registry Methods
    // =============================================================================

    private fun getModelsDirectory(): File {
        val modelsDir = File(reactApplicationContext.filesDir, "RunAnywhere/Models")
        if (!modelsDir.exists()) {
            modelsDir.mkdirs()
        }
        return modelsDir
    }

    @ReactMethod
    fun getAvailableModels(promise: Promise) {
        try {
            val modelsDir = getModelsDirectory()
            val models = JSONArray()

            for ((modelId, info) in modelCatalog) {
                val model = JSONObject()
                for ((key, value) in info) {
                    model.put(key, value)
                }

                // Check if model is downloaded
                val modelPath = File(modelsDir, modelId)
                val isDownloaded = modelPath.exists() && modelPath.isDirectory
                model.put("isDownloaded", isDownloaded)
                if (isDownloaded) {
                    model.put("localPath", modelPath.absolutePath)
                }

                models.put(model)
            }

            promise.resolve(models.toString())
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun getModelInfo(modelId: String, promise: Promise) {
        try {
            val info = modelCatalog[modelId]
            if (info == null) {
                promise.resolve("null")
                return
            }

            val model = JSONObject()
            for ((key, value) in info) {
                model.put(key, value)
            }

            val modelsDir = getModelsDirectory()
            val modelPath = File(modelsDir, modelId)
            val isDownloaded = modelPath.exists() && modelPath.isDirectory
            model.put("isDownloaded", isDownloaded)
            if (isDownloaded) {
                model.put("localPath", modelPath.absolutePath)
            }

            promise.resolve(model.toString())
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun isModelDownloaded(modelId: String, promise: Promise) {
        try {
            val modelPath = File(getModelsDirectory(), modelId)
            promise.resolve(modelPath.exists() && modelPath.isDirectory)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun getModelPath(modelId: String, promise: Promise) {
        try {
            val modelPath = File(getModelsDirectory(), modelId)
            if (modelPath.exists() && modelPath.isDirectory) {
                promise.resolve(modelPath.absolutePath)
            } else {
                promise.resolve(null)
            }
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun getDownloadedModels(promise: Promise) {
        try {
            val modelsDir = getModelsDirectory()
            val downloaded = JSONArray()

            modelsDir.listFiles()?.filter { it.isDirectory }?.forEach { dir ->
                val modelId = dir.name
                val info = modelCatalog[modelId]
                val model = JSONObject()

                if (info != null) {
                    for ((key, value) in info) {
                        model.put(key, value)
                    }
                } else {
                    model.put("id", modelId)
                    model.put("name", modelId)
                }

                model.put("isDownloaded", true)
                model.put("localPath", dir.absolutePath)
                downloaded.put(model)
            }

            promise.resolve(downloaded.toString())
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    // =============================================================================
    // Model Download Methods
    // =============================================================================

    @ReactMethod
    fun downloadModel(modelId: String, promise: Promise) {
        val info = modelCatalog[modelId]
        if (info == null) {
            promise.reject("MODEL_NOT_FOUND", "Model $modelId not found in catalog")
            return
        }

        val downloadUrl = info["downloadUrl"] as? String
        if (downloadUrl == null) {
            promise.reject("NO_DOWNLOAD_URL", "Model has no download URL")
            return
        }

        // Check if already downloading
        if (downloadJobs.containsKey(modelId)) {
            promise.resolve(modelId)
            return
        }

        val modelsDir = getModelsDirectory()
        val modelDir = File(modelsDir, modelId)
        modelDir.mkdirs()

        val job = scope.launch(Dispatchers.IO) {
            try {
                val url = URL(downloadUrl)
                val fileName = url.path.substringAfterLast("/")
                val downloadFile = File(modelsDir, fileName)

                Log.d(NAME, "Downloading $modelId from $downloadUrl")

                val connection = url.openConnection() as HttpURLConnection
                connection.connectTimeout = 30000
                connection.readTimeout = 30000
                connection.requestMethod = "GET"
                connection.setRequestProperty("User-Agent", "RunAnywhere-Android/1.0")

                // Handle redirects
                var finalConnection = connection
                if (connection.responseCode in 300..399) {
                    val redirectUrl = connection.getHeaderField("Location")
                    if (redirectUrl != null) {
                        finalConnection = URL(redirectUrl).openConnection() as HttpURLConnection
                        finalConnection.connectTimeout = 30000
                        finalConnection.readTimeout = 30000
                    }
                }

                val totalBytes = finalConnection.contentLengthLong
                var downloadedBytes = 0L

                finalConnection.inputStream.use { input ->
                    FileOutputStream(downloadFile).use { output ->
                        val buffer = ByteArray(8192)
                        var bytesRead: Int

                        while (input.read(buffer).also { bytesRead = it } != -1) {
                            if (!isActive) {
                                // Download was cancelled
                                downloadFile.delete()
                                return@launch
                            }

                            output.write(buffer, 0, bytesRead)
                            downloadedBytes += bytesRead

                            // Emit progress
                            val progress = if (totalBytes > 0) downloadedBytes.toDouble() / totalBytes else 0.0
                            withContext(Dispatchers.Main) {
                                sendEvent("onModelDownloadProgress", Arguments.createMap().apply {
                                    putString("modelId", modelId)
                                    putDouble("bytesDownloaded", downloadedBytes.toDouble())
                                    putDouble("totalBytes", totalBytes.toDouble())
                                    putDouble("progress", progress)
                                })
                            }
                        }
                    }
                }

                // Extract if it's an archive
                val extension = fileName.substringAfterLast(".")
                if (extension in listOf("bz2", "gz", "zip", "tar")) {
                    Log.d(NAME, "Extracting $fileName to $modelDir")
                    val result = RunAnywhereBridge.nativeExtractArchive(
                        downloadFile.absolutePath,
                        modelDir.absolutePath
                    )

                    if (result == 0) {
                        // Success, delete archive
                        downloadFile.delete()
                        withContext(Dispatchers.Main) {
                            sendEvent("onModelDownloadComplete", Arguments.createMap().apply {
                                putString("modelId", modelId)
                                putString("localPath", modelDir.absolutePath)
                            })
                        }
                    } else {
                        withContext(Dispatchers.Main) {
                            sendEvent("onModelDownloadError", Arguments.createMap().apply {
                                putString("modelId", modelId)
                                putString("error", "Failed to extract archive")
                            })
                        }
                    }
                } else {
                    // Not an archive, move to model dir
                    val finalPath = File(modelDir, fileName)
                    downloadFile.renameTo(finalPath)
                    withContext(Dispatchers.Main) {
                        sendEvent("onModelDownloadComplete", Arguments.createMap().apply {
                            putString("modelId", modelId)
                            putString("localPath", modelDir.absolutePath)
                        })
                    }
                }
            } catch (e: Exception) {
                Log.e(NAME, "Download error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    sendEvent("onModelDownloadError", Arguments.createMap().apply {
                        putString("modelId", modelId)
                        putString("error", e.message ?: "Unknown error")
                    })
                }
            } finally {
                downloadJobs.remove(modelId)
            }
        }

        downloadJobs[modelId] = job
        promise.resolve(modelId)
    }

    @ReactMethod
    fun cancelDownload(modelId: String, promise: Promise) {
        try {
            downloadJobs[modelId]?.cancel()
            downloadJobs.remove(modelId)
            promise.resolve(true)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun deleteModel(modelId: String, promise: Promise) {
        try {
            val modelPath = File(getModelsDirectory(), modelId)
            val success = modelPath.deleteRecursively()
            promise.resolve(success)
        } catch (e: Exception) {
            promise.reject("DELETE_FAILED", e.message, e)
        }
    }

    @ReactMethod
    fun extractArchive(archivePath: String, destDir: String, promise: Promise) {
        scope.launch {
            try {
                val result = RunAnywhereBridge.nativeExtractArchive(archivePath, destDir)
                promise.resolve(result == 0)
            } catch (e: Exception) {
                promise.reject("EXTRACT_ERROR", e.message, e)
            }
        }
    }

    // =============================================================================
    // Private Helpers
    // =============================================================================

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
