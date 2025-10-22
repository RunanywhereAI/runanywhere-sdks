package com.runanywhere.ai.models.repository

import android.content.Context
import android.os.StatFs
import com.runanywhere.ai.models.data.*
import com.runanywhere.ai.models.ui.extension
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
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

            // Convert SDK models to UI state models
            val models = sdkModels.map { sdkModel ->
                ModelUiState.fromSdkModel(sdkModel)
            }

            _availableModels.value = models
        } catch (e: Exception) {
            // If SDK not initialized or fails, show empty list
            _availableModels.value = emptyList()
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
                    // Check for cancellation before emitting
                    currentCoroutineContext().ensureActive()

                    // SDK returns Float progress (0.0 to 1.0)
                    emit(progress)
                    updateDownloadProgress(modelId, progress)
                }
            } else {
                // Mock download progress
                for (i in 0..100 step 5) {
                    // Check for cancellation before each iteration
                    currentCoroutineContext().ensureActive()

                    emit(i / 100f)
                    updateDownloadProgress(modelId, i / 100f)
                    kotlinx.coroutines.delay(100)
                }
            }

            // Update model state and path
            val localPath = File(modelsDir, "${modelId}${model.format.extension}").absolutePath
            updateModelPath(modelId, localPath)
            updateModelState(modelId, ModelState.DOWNLOADED)

        } catch (e: kotlinx.coroutines.CancellationException) {
            // Download was cancelled - clean up partial files and reset state
            val partialFile = File(modelsDir, "${modelId}${model.format.extension}")
            if (partialFile.exists()) {
                partialFile.delete()
            }
            updateModelState(modelId, ModelState.AVAILABLE)
            // Clear download progress
            _downloadProgress.update { it - modelId }
            // Re-throw to propagate cancellation
            throw e
        } catch (e: Exception) {
            updateModelState(modelId, ModelState.AVAILABLE)
            // Clear download progress
            _downloadProgress.update { it - modelId }
            throw e
        } finally {
            // Clear download progress (redundant but safe for non-cancellation exits)
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
                val deleted = file.delete()
                if (!deleted) {
                    throw IllegalStateException("Failed to delete model file at $path")
                }
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

        // Device storage - use app-accessible directory to avoid SecurityException on Android 11+
        val (totalDeviceStorage, availableDeviceStorage) = try {
            // Try to use external files directory (app-specific, doesn't require permissions)
            val externalPath = context.getExternalFilesDir(null)?.path
                ?: context.externalMediaDirs.firstOrNull()?.path
                ?: context.filesDir.path // Fallback to internal storage

            val externalStatFs = StatFs(externalPath)
            val total = externalStatFs.blockCountLong * externalStatFs.blockSizeLong
            val available = externalStatFs.availableBlocksLong * externalStatFs.blockSizeLong
            Pair(total, available)
        } catch (e: SecurityException) {
            // If we still hit a SecurityException, fall back to internal storage stats
            Pair(totalAppStorage, availableAppStorage)
        } catch (e: IllegalArgumentException) {
            // Handle invalid path
            Pair(totalAppStorage, availableAppStorage)
        }

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
                    // Update the underlying SDK model's localPath
                    val updatedSdkModel = model.modelInfo.copy(localPath = path)
                    model.copy(modelInfo = updatedSdkModel)
                } else {
                    model
                }
            }
        }
    }

    private fun updateDownloadProgress(modelId: String, progress: Float) {
        _downloadProgress.update { it + (modelId to progress) }

        // Also update the model's download progress in UI state
        _availableModels.update { models ->
            models.map { model ->
                if (model.id == modelId) {
                    model.copy(downloadProgress = progress)
                } else {
                    model
                }
            }
        }
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
}
