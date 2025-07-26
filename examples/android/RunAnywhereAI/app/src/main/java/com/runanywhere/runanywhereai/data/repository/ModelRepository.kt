package com.runanywhere.runanywhereai.data.repository

import android.content.Context
import android.util.Log
import com.runanywhere.runanywhereai.llm.LLMFramework
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import android.os.Build
import com.runanywhere.runanywhereai.llm.frameworks.GeminiNanoService
import java.security.MessageDigest

/**
 * Repository for managing LLM models
 */
class ModelRepository(private val context: Context) {
    companion object {
        private const val TAG = "ModelRepository"
        private const val MODELS_DIR = "llm_models"
    }
    
    private val client = OkHttpClient()
    private val modelsDirectory: File by lazy {
        File(context.filesDir, MODELS_DIR).apply {
            if (!exists()) mkdirs()
        }
    }
    
    /**
     * Get available models for download
     */
    fun getAvailableModels(): List<ModelInfo> {
        val models = mutableListOf<ModelInfo>()
        
        // Add Gemini Nano if device supports it
        if (checkGeminiNanoAvailability()) {
            models.add(
                ModelInfo(
                    id = "gemini-nano",
                    name = "Gemini Nano",
                    description = "Google's on-device foundation model (3.25B parameters)",
                    framework = LLMFramework.GEMINI_NANO,
                    sizeBytes = 0, // System-managed
                    downloadUrl = "", // System-managed
                    fileName = "gemini-nano",
                    quantization = "INT4",
                    isDownloaded = true // Always available if supported
                )
            )
        }
        
        // Add other models
        models.addAll(listOf(
            ModelInfo(
                id = "gemma-2b",
                name = "Gemma 2B",
                description = "Google's efficient 2B parameter model",
                framework = LLMFramework.MEDIAPIPE,
                sizeBytes = 1_200_000_000L,
                downloadUrl = "https://example.com/models/gemma-2b-it-gpu-int4.bin",
                fileName = "gemma-2b-it-gpu-int4.bin",
                quantization = "INT4"
            ),
            ModelInfo(
                id = "phi-2",
                name = "Phi-2",
                description = "Microsoft's compact 2.7B model",
                framework = LLMFramework.MEDIAPIPE,
                sizeBytes = 1_500_000_000L,
                downloadUrl = "https://example.com/models/phi-2-gpu-int4.bin",
                fileName = "phi-2-gpu-int4.bin",
                quantization = "INT4"
            ),
            ModelInfo(
                id = "tinyllama",
                name = "TinyLlama 1.1B",
                description = "Compact Llama model for mobile",
                framework = LLMFramework.ONNX_RUNTIME,
                sizeBytes = 600_000_000L,
                downloadUrl = "https://example.com/models/tinyllama-1.1b.onnx",
                fileName = "tinyllama-1.1b.onnx",
                quantization = "FP16"
            ),
            ModelInfo(
                id = "mobilenet-gpt2",
                name = "MobileNet GPT-2",
                description = "Lightweight GPT-2 variant for mobile",
                framework = LLMFramework.TFLITE,
                sizeBytes = 180_000_000L,
                downloadUrl = "https://example.com/models/mobilenet-gpt2.tflite",
                fileName = "mobilenet-gpt2.tflite",
                quantization = "INT8"
            ),
            ModelInfo(
                id = "distilbert-qa",
                name = "DistilBERT QA",
                description = "Question answering model",
                framework = LLMFramework.TFLITE,
                sizeBytes = 125_000_000L,
                downloadUrl = "https://example.com/models/distilbert-qa.tflite",
                fileName = "distilbert-qa.tflite",
                quantization = "FLOAT16"
            ),
            ModelInfo(
                id = "tinyllama-1.1b-q8",
                name = "TinyLlama 1.1B Chat",
                description = "Compact Llama model with chat template",
                framework = LLMFramework.LLAMA_CPP,
                sizeBytes = 650_000_000L,
                downloadUrl = "https://example.com/models/tinyllama-1.1b-chat-v1.0.Q8_0.gguf",
                fileName = "tinyllama-1.1b-chat-v1.0.Q8_0.gguf",
                quantization = "Q8_0"
            ),
            ModelInfo(
                id = "phi-2-q5",
                name = "Phi-2 GGUF",
                description = "Microsoft Phi-2 quantized for mobile",
                framework = LLMFramework.LLAMA_CPP,
                sizeBytes = 1_400_000_000L,
                downloadUrl = "https://example.com/models/phi-2.Q5_K_M.gguf",
                fileName = "phi-2.Q5_K_M.gguf",
                quantization = "Q5_K_M"
            ),
            ModelInfo(
                id = "stablelm-2-1.6b",
                name = "StableLM 2 Zephyr 1.6B",
                description = "Stability AI's efficient chat model",
                framework = LLMFramework.LLAMA_CPP,
                sizeBytes = 900_000_000L,
                downloadUrl = "https://example.com/models/stablelm-2-zephyr-1_6b.Q4_0.gguf",
                fileName = "stablelm-2-zephyr-1_6b.Q4_0.gguf",
                quantization = "Q4_0"
            )
        ))
        
        return models
    }
    
    /**
     * Get downloaded models
     */
    suspend fun getDownloadedModels(): List<ModelInfo> = withContext(Dispatchers.IO) {
        val downloadedModels = mutableListOf<ModelInfo>()
        
        // Add Gemini Nano if available (it's system-managed, not file-based)
        getAvailableModels().find { it.framework == LLMFramework.GEMINI_NANO }?.let {
            downloadedModels.add(it)
        }
        
        // Add file-based models
        modelsDirectory.listFiles()?.forEach { file ->
            // Match with available models
            getAvailableModels().find { it.fileName == file.name && it.framework != LLMFramework.GEMINI_NANO }?.let { modelInfo ->
                downloadedModels.add(modelInfo.copy(
                    isDownloaded = true,
                    localPath = file.absolutePath
                ))
            }
        }
        
        downloadedModels
    }
    
    /**
     * Check if Gemini Nano is available on this device
     */
    private fun checkGeminiNanoAvailability(): Boolean {
        // Check if device meets minimum requirements
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return false
        }
        
        // Check with GeminiNanoService
        return try {
            val service = GeminiNanoService(context)
            service.isModelAvailable()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to check Gemini Nano availability", e)
            false
        }
    }
    
    /**
     * Download a model with progress tracking
     */
    fun downloadModel(modelInfo: ModelInfo): Flow<DownloadProgress> = flow {
        try {
            val file = File(modelsDirectory, modelInfo.fileName)
            
            // Check if already downloaded
            if (file.exists() && file.length() == modelInfo.sizeBytes) {
                emit(DownloadProgress.Completed(file.absolutePath))
                return@flow
            }
            
            emit(DownloadProgress.Starting)
            
            // Build request
            val request = Request.Builder()
                .url(modelInfo.downloadUrl)
                .build()
            
            // Execute download
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    throw Exception("Download failed: ${response.code}")
                }
                
                val body = response.body ?: throw Exception("Empty response body")
                val contentLength = body.contentLength()
                
                // Download with progress
                body.byteStream().use { input ->
                    FileOutputStream(file).use { output ->
                        val buffer = ByteArray(8192)
                        var totalBytesRead = 0L
                        var bytesRead: Int
                        
                        while (input.read(buffer).also { bytesRead = it } != -1) {
                            output.write(buffer, 0, bytesRead)
                            totalBytesRead += bytesRead
                            
                            val progress = if (contentLength > 0) {
                                (totalBytesRead.toFloat() / contentLength)
                            } else {
                                0f
                            }
                            
                            emit(DownloadProgress.InProgress(
                                progress = progress,
                                bytesDownloaded = totalBytesRead,
                                totalBytes = contentLength
                            ))
                        }
                    }
                }
            }
            
            // Verify downloaded file if hash is provided
            if (modelInfo.sha256Hash != null) {
                emit(DownloadProgress.Verifying)
                val isValid = verifyModelIntegrity(file, modelInfo.sha256Hash)
                if (!isValid) {
                    file.delete()
                    emit(DownloadProgress.Failed("File verification failed. Hash mismatch."))
                    return@flow
                }
            }
            
            emit(DownloadProgress.Completed(file.absolutePath))
            
        } catch (e: Exception) {
            Log.e(TAG, "Download failed", e)
            emit(DownloadProgress.Failed(e.message ?: "Unknown error"))
        }
    }
    
    /**
     * Delete a downloaded model
     */
    suspend fun deleteModel(modelInfo: ModelInfo): Boolean = withContext(Dispatchers.IO) {
        try {
            val file = File(modelsDirectory, modelInfo.fileName)
            file.delete()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete model", e)
            false
        }
    }
    
    /**
     * Get model file path
     */
    fun getModelPath(fileName: String): String {
        return File(modelsDirectory, fileName).absolutePath
    }
    
    /**
     * Check if model exists
     */
    fun isModelDownloaded(modelInfo: ModelInfo): Boolean {
        val file = File(modelsDirectory, modelInfo.fileName)
        return file.exists() && file.length() > 0
    }
    
    /**
     * Verify model file integrity using SHA-256 hash
     */
    private suspend fun verifyModelIntegrity(file: File, expectedHash: String): Boolean = 
        withContext(Dispatchers.IO) {
            try {
                val calculatedHash = calculateSHA256(file)
                calculatedHash.equals(expectedHash, ignoreCase = true)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to verify model integrity", e)
                false
            }
        }
    
    /**
     * Calculate SHA-256 hash of a file
     */
    private fun calculateSHA256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(8192)
            var bytesRead: Int
            while (input.read(buffer).also { bytesRead = it } != -1) {
                digest.update(buffer, 0, bytesRead)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
    
    /**
     * Get device available memory
     */
    fun getAvailableMemory(): Long {
        val runtime = Runtime.getRuntime()
        return runtime.maxMemory() - (runtime.totalMemory() - runtime.freeMemory())
    }
    
    /**
     * Check if device has enough memory for model
     */
    fun canLoadModel(modelInfo: ModelInfo): Boolean {
        val requiredMemory = modelInfo.requiredRam ?: (modelInfo.sizeBytes * 2) // Estimate if not provided
        val availableMemory = getAvailableMemory()
        return availableMemory >= requiredMemory
    }
}

/**
 * Model information
 */
data class ModelInfo(
    val id: String,
    val name: String,
    val description: String,
    val framework: LLMFramework,
    val sizeBytes: Long,
    val downloadUrl: String,
    val fileName: String,
    val quantization: String,
    val isDownloaded: Boolean = false,
    val localPath: String? = null,
    val sha256Hash: String? = null,  // SHA-256 hash for verification
    val requiredRam: Long? = null,    // Estimated RAM requirement
    val supportedDevices: List<String>? = null  // Device compatibility list
)

/**
 * Download progress states
 */
sealed class DownloadProgress {
    object Starting : DownloadProgress()
    data class InProgress(
        val progress: Float,
        val bytesDownloaded: Long,
        val totalBytes: Long
    ) : DownloadProgress()
    object Verifying : DownloadProgress()
    data class Completed(val filePath: String) : DownloadProgress()
    data class Failed(val error: String) : DownloadProgress()
}