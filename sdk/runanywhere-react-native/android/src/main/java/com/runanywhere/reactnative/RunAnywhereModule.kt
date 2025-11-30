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
        "piper-en-us-lessac" to mapOf(
            "id" to "piper-en-us-lessac",
            "name" to "Piper US English (Lessac)",
            "description" to "High quality US English TTS",
            "category" to "tts",
            "modality" to "tts",
            "size" to 65000000L,
            "downloadUrl" to "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2",
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
