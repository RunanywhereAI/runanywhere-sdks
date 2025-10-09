package com.runanywhere.ai.models.repository

import android.content.Context
import android.os.Environment
import android.os.StatFs
import com.runanywhere.ai.models.data.*
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Date

class ModelRepository(
    private val context: Context
) {
    private val modelsDir = File(context.filesDir, "models")
    private val cacheDir = context.cacheDir

    private val _availableModels = MutableStateFlow<List<ModelInfo>>(emptyList())
    val availableModels: StateFlow<List<ModelInfo>> = _availableModels.asStateFlow()

    private val _currentModel = MutableStateFlow<ModelInfo?>(null)
    val currentModel: StateFlow<ModelInfo?> = _currentModel.asStateFlow()

    private val _downloadProgress = MutableStateFlow<Map<String, Float>>(emptyMap())
    val downloadProgress: StateFlow<Map<String, Float>> = _downloadProgress.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    init {
        // Ensure models directory exists
        if (!modelsDir.exists()) {
            modelsDir.mkdirs()
        }
    }

    suspend fun refreshModels() = withContext(Dispatchers.IO) {
        _isLoading.value = true
        try {
            // Get models from SDK
            val sdkModels = RunAnywhere.availableModels()

            // Map SDK models to our ModelInfo
            val models = sdkModels.map { sdkModel ->
                ModelInfo(
                    id = sdkModel.id,
                    name = sdkModel.name,
                    category = mapCategory(sdkModel.category.toString()),
                    format = mapFormat(sdkModel.format.toString()),
                    downloadURL = sdkModel.downloadURL,
                    localPath = sdkModel.localPath,
                    downloadSize = sdkModel.downloadSize,
                    memoryRequired = sdkModel.memoryRequired,
                    compatibleFrameworks = mapFrameworks(listOf(sdkModel.preferredFramework?.toString() ?: "LLAMACPP")),
                    preferredFramework = mapFramework(sdkModel.preferredFramework?.toString()),
                    contextLength = sdkModel.contextLength,
                    supportsThinking = sdkModel.supportsThinking,
                    metadata = mapMetadata(null), // Handle metadata separately
                    state = determineModelState(sdkModel)
                )
            }

            // Add some mock models for demo
            val allModels = models + getMockModels()

            _availableModels.value = allModels
        } catch (e: Exception) {
            // If SDK not initialized or fails, use mock models
            _availableModels.value = getMockModels()
        } finally {
            _isLoading.value = false
        }
    }

    suspend fun downloadModel(modelId: String): Flow<Float> = flow {
        val model = _availableModels.value.find { it.id == modelId }
            ?: throw IllegalArgumentException("Model not found: $modelId")

        if (!model.canDownload) {
            throw IllegalStateException("Model cannot be downloaded")
        }

        // Update model state to downloading
        updateModelState(modelId, ModelState.DOWNLOADING)

        try {
            // Use SDK download if available
            if (RunAnywhere.isInitialized) {
                RunAnywhere.downloadModel(modelId).collect { progress ->
                    // SDK returns Float progress (0.0 to 1.0)
                    emit(progress)
                    updateDownloadProgress(modelId, progress)
                }
            } else {
                // Mock download progress
                for (i in 0..100 step 5) {
                    emit(i / 100f)
                    updateDownloadProgress(modelId, i / 100f)
                    kotlinx.coroutines.delay(100)
                }
            }

            // Update model state and path
            val localPath = File(modelsDir, "${modelId}.${model.format.extension}").absolutePath
            updateModelPath(modelId, localPath)
            updateModelState(modelId, ModelState.DOWNLOADED)

        } catch (e: Exception) {
            updateModelState(modelId, ModelState.AVAILABLE)
            throw e
        } finally {
            // Clear download progress
            _downloadProgress.update { it - modelId }
        }
    }.flowOn(Dispatchers.IO)

    suspend fun loadModel(modelId: String) = withContext(Dispatchers.IO) {
        val model = _availableModels.value.find { it.id == modelId }
            ?: throw IllegalArgumentException("Model not found: $modelId")

        if (model.state != ModelState.DOWNLOADED && model.state != ModelState.BUILT_IN) {
            throw IllegalStateException("Model must be downloaded first")
        }

        // Update state to loading
        updateModelState(modelId, ModelState.LOADING)

        try {
            // Load model through SDK
            if (RunAnywhere.isInitialized) {
                val success = RunAnywhere.loadModel(modelId)
                if (success) {
                    updateModelState(modelId, ModelState.LOADED)
                    _currentModel.value = model.copy(state = ModelState.LOADED)
                } else {
                    throw Exception("Failed to load model")
                }
            } else {
                // Mock loading
                kotlinx.coroutines.delay(2000)
                updateModelState(modelId, ModelState.LOADED)
                _currentModel.value = model.copy(state = ModelState.LOADED)
            }
        } catch (e: Exception) {
            updateModelState(modelId, ModelState.DOWNLOADED)
            throw e
        }
    }

    suspend fun deleteModel(modelId: String) = withContext(Dispatchers.IO) {
        val model = _availableModels.value.find { it.id == modelId }
            ?: throw IllegalArgumentException("Model not found: $modelId")

        model.localPath?.let { path ->
            val file = File(path)
            if (file.exists()) {
                file.delete()
            }
        }

        // Update model state
        updateModelPath(modelId, null)
        updateModelState(modelId, ModelState.AVAILABLE)

        // If this was the current model, clear it
        if (_currentModel.value?.id == modelId) {
            _currentModel.value = null
        }
    }

    suspend fun getStorageInfo(): StorageInfo = withContext(Dispatchers.IO) {
        val statFs = StatFs(context.filesDir.path)
        val blockSize = statFs.blockSizeLong
        val totalBlocks = statFs.blockCountLong
        val availableBlocks = statFs.availableBlocksLong

        val totalAppStorage = totalBlocks * blockSize
        val availableAppStorage = availableBlocks * blockSize
        val usedAppStorage = totalAppStorage - availableAppStorage

        // Device storage
        val externalStatFs = StatFs(Environment.getExternalStorageDirectory().path)
        val totalDeviceStorage = externalStatFs.blockCountLong * externalStatFs.blockSizeLong
        val availableDeviceStorage = externalStatFs.availableBlocksLong * externalStatFs.blockSizeLong

        // Calculate models storage
        val modelsStorage = calculateDirectorySize(modelsDir)
        val cacheSize = calculateDirectorySize(cacheDir)

        // Get stored models
        val storedModels = getStoredModels()

        StorageInfo(
            totalAppStorage = totalAppStorage,
            usedAppStorage = usedAppStorage,
            totalDeviceStorage = totalDeviceStorage,
            availableDeviceStorage = availableDeviceStorage,
            modelsStorage = modelsStorage,
            cacheSize = cacheSize,
            downloadedModelsCount = storedModels.size,
            storedModels = storedModels
        )
    }

    suspend fun clearCache() = withContext(Dispatchers.IO) {
        cacheDir.deleteRecursively()
        cacheDir.mkdirs()
    }

    private fun updateModelState(modelId: String, state: ModelState) {
        _availableModels.update { models ->
            models.map { model ->
                if (model.id == modelId) {
                    model.copy(state = state)
                } else {
                    model
                }
            }
        }
    }

    private fun updateModelPath(modelId: String, path: String?) {
        _availableModels.update { models ->
            models.map { model ->
                if (model.id == modelId) {
                    model.copy(
                        localPath = path,
                        downloadedAt = if (path != null) Date() else null
                    )
                } else {
                    model
                }
            }
        }
    }

    private fun updateDownloadProgress(modelId: String, progress: Float) {
        _downloadProgress.update { it + (modelId to progress) }
    }

    private fun calculateDirectorySize(dir: File): Long {
        var size = 0L
        if (dir.exists() && dir.isDirectory) {
            dir.walkTopDown().forEach { file ->
                if (file.isFile) {
                    size += file.length()
                }
            }
        }
        return size
    }

    private fun getStoredModels(): List<StoredModel> {
        val models = mutableListOf<StoredModel>()
        if (modelsDir.exists() && modelsDir.isDirectory) {
            modelsDir.listFiles()?.forEach { file ->
                if (file.isFile) {
                    // Find corresponding model info
                    val modelId = file.nameWithoutExtension
                    val modelInfo = _availableModels.value.find { it.id == modelId }
                    if (modelInfo != null) {
                        models.add(
                            StoredModel(
                                modelInfo = modelInfo,
                                fileSize = file.length(),
                                lastAccessed = file.lastModified(),
                                filePath = file.absolutePath
                            )
                        )
                    }
                }
            }
        }
        return models
    }

    private fun mapCategory(category: String?): ModelCategory {
        return when (category?.lowercase()) {
            "language" -> ModelCategory.LANGUAGE
            "vision" -> ModelCategory.VISION
            "audio" -> ModelCategory.AUDIO
            "multimodal" -> ModelCategory.MULTIMODAL
            else -> ModelCategory.SPECIALIZED
        }
    }

    private fun mapFormat(format: String?): ModelFormat {
        return ModelFormat.values().find {
            it.extension == format || it.name == format?.uppercase()
        } ?: ModelFormat.UNKNOWN
    }

    private fun mapFramework(framework: String?): LLMFramework? {
        return when (framework?.lowercase()) {
            "llamacpp", "llama.cpp" -> LLMFramework.LLAMACPP
            "onnx", "onnxruntime" -> LLMFramework.ONNX_RUNTIME
            "tflite", "tensorflow" -> LLMFramework.TENSORFLOW_LITE
            "foundation" -> LLMFramework.FOUNDATION_MODELS
            "whisper" -> LLMFramework.WHISPER_CPP
            else -> null
        }
    }

    private fun mapFrameworks(frameworks: List<String>?): List<LLMFramework> {
        return frameworks?.mapNotNull { mapFramework(it) } ?: emptyList()
    }

    private fun mapMetadata(metadata: Map<String, Any>?): ModelMetadata? {
        if (metadata == null) return null

        return ModelMetadata(
            description = metadata["description"] as? String,
            author = metadata["author"] as? String,
            version = metadata["version"] as? String,
            license = metadata["license"] as? String,
            tags = (metadata["tags"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
            capabilities = (metadata["capabilities"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
            limitations = (metadata["limitations"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
            baseModel = metadata["baseModel"] as? String,
            quantization = metadata["quantization"] as? String
        )
    }

    private fun determineModelState(sdkModel: com.runanywhere.sdk.models.ModelInfo): ModelState {
        return when {
            sdkModel.localPath != null -> ModelState.DOWNLOADED
            sdkModel.downloadURL != null -> ModelState.AVAILABLE
            else -> ModelState.NOT_AVAILABLE
        }
    }

    private fun getMockModels(): List<ModelInfo> {
        return listOf(
            ModelInfo(
                id = "llama3.2-3b",
                name = "Llama 3.2 3B",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                downloadURL = "https://example.com/llama3.2-3b.gguf",
                downloadSize = 2_147_483_648, // 2GB
                memoryRequired = 4_294_967_296, // 4GB
                compatibleFrameworks = listOf(LLMFramework.LLAMACPP),
                preferredFramework = LLMFramework.LLAMACPP,
                contextLength = 8192,
                supportsThinking = true,
                thinkingTags = listOf("reasoning", "analysis"),
                state = ModelState.AVAILABLE
            ),
            ModelInfo(
                id = "whisper-base",
                name = "Whisper Base",
                category = ModelCategory.AUDIO,
                format = ModelFormat.GGUF,
                downloadURL = "https://example.com/whisper-base.gguf",
                downloadSize = 147_483_648, // 140MB
                memoryRequired = 500_000_000, // 500MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_CPP),
                preferredFramework = LLMFramework.WHISPER_CPP,
                state = ModelState.AVAILABLE
            ),
            ModelInfo(
                id = "gemma-2b",
                name = "Gemma 2B",
                category = ModelCategory.LANGUAGE,
                format = ModelFormat.GGUF,
                localPath = "${modelsDir.absolutePath}/gemma-2b.gguf",
                downloadSize = 1_610_612_736, // 1.5GB
                memoryRequired = 3_221_225_472, // 3GB
                compatibleFrameworks = listOf(LLMFramework.LLAMACPP, LLMFramework.ONNX_RUNTIME),
                preferredFramework = LLMFramework.LLAMACPP,
                contextLength = 4096,
                state = ModelState.DOWNLOADED
            )
        )
    }
}
