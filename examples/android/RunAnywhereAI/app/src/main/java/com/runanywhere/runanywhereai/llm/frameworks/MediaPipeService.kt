package com.runanywhere.runanywhereai.llm.frameworks

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.runanywhere.runanywhereai.llm.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import java.io.File

/**
 * MediaPipe LLM service implementation for on-device inference
 */
class MediaPipeService(private val context: Context) : LLMService {
    companion object {
        private const val TAG = "MediaPipeService"
        
        // Supported models
        val SUPPORTED_MODELS = listOf(
            MediaPipeModel("gemma-2b-it-gpu-int4.bin", "Gemma 2B", 1_200_000_000L),
            MediaPipeModel("phi-2-gpu-int4.bin", "Phi-2", 1_500_000_000L),
            MediaPipeModel("falcon-rw-1b-cpu-int8.bin", "Falcon 1B", 900_000_000L),
            MediaPipeModel("stablelm-3b-gpu-int4.bin", "StableLM 3B", 1_800_000_000L)
        )
    }
    
    private var llmInference: LlmInference? = null
    private var currentModel: MediaPipeModel? = null
    
    override val name: String = "MediaPipe LLM"
    
    override val isInitialized: Boolean
        get() = llmInference != null
    
    override suspend fun initialize(modelPath: String) {
        withContext(Dispatchers.IO) {
            try {
                release() // Clean up any existing instance
                
                // Find model info
                val modelFile = File(modelPath)
                currentModel = SUPPORTED_MODELS.find { it.fileName == modelFile.name }
                    ?: MediaPipeModel(modelFile.name, "Custom Model", modelFile.length())
                
                // Configure base options
                val baseOptions = BaseOptions.builder()
                    .setModelAssetPath(modelPath)
                    .build()
                
                // Configure LLM options - simplified for compatibility
                val options = LlmInference.LlmInferenceOptions.builder()
                    .build()
                
                // Create LLM inference instance
                llmInference = LlmInference.createFromOptions(context, options)
                
                Log.d(TAG, "Model loaded successfully: ${currentModel?.displayName}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize MediaPipe model", e)
                throw e
            }
        }
    }
    
    override suspend fun generate(prompt: String, options: GenerationOptions): String {
        return withContext(Dispatchers.Default) {
            val inference = llmInference ?: throw IllegalStateException("Service not initialized")
            
            try {
                // MediaPipe doesn't support all options directly, so we use what's available
                inference.generateResponse(prompt)
            } catch (e: Exception) {
                Log.e(TAG, "Generation failed", e)
                throw e
            }
        }
    }
    
    override fun generateStream(prompt: String, options: GenerationOptions): Flow<String> = flow {
        val inference = llmInference ?: throw IllegalStateException("Service not initialized")
        
        try {
            // For now, use non-streaming API and emit the full response
            // MediaPipe streaming API seems to have changed
            val response = inference.generateResponse(prompt)
            emit(response)
        } catch (e: Exception) {
            Log.e(TAG, "Generation failed", e)
            throw e
        }
    }
    
    override fun getModelInfo(): ModelInfo? {
        return currentModel?.let { model ->
            ModelInfo(
                name = model.displayName,
                sizeBytes = model.sizeBytes,
                parameters = null,
                quantization = "INT4",
                format = "MediaPipe",
                framework = LLMFramework.MEDIAPIPE
            )
        }
    }
    
    override fun release() {
        llmInference?.close()
        llmInference = null
        currentModel = null
    }
    
    /**
     * MediaPipe model information
     */
    data class MediaPipeModel(
        val fileName: String,
        val displayName: String,
        val sizeBytes: Long
    )
}