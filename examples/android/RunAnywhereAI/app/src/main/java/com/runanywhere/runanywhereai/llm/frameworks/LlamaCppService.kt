package com.runanywhere.runanywhereai.llm.frameworks

import android.content.Context
import android.util.Log
import com.runanywhere.runanywhereai.llm.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import java.io.File

/**
 * llama.cpp service implementation for GGUF model inference
 * 
 * Supports various quantization formats:
 * - Q4_0, Q4_1: 4-bit quantization
 * - Q5_0, Q5_1: 5-bit quantization  
 * - Q8_0: 8-bit quantization
 * - F16: 16-bit floating point
 * - F32: 32-bit floating point (unquantized)
 */
class LlamaCppService(private val context: Context) : LLMService {
    companion object {
        private const val TAG = "LlamaCppService"
        
        init {
            System.loadLibrary("llama-jni")
        }
        
        // Native methods
        @JvmStatic
        external fun nativeLoadModel(modelPath: String): Long
        
        @JvmStatic
        external fun nativeGenerate(
            modelPtr: Long, 
            prompt: String,
            maxTokens: Int,
            temperature: Float,
            topP: Float,
            topK: Int
        ): String
        
        @JvmStatic
        external fun nativeFreeModel(modelPtr: Long)
        
        @JvmStatic
        external fun nativeGetModelSize(modelPtr: Long): Long
        
        @JvmStatic
        external fun nativeGetVocabSize(modelPtr: Long): Long
        
        @JvmStatic
        external fun nativeGetContextSize(modelPtr: Long): Long
        
        @JvmStatic
        external fun nativeTokenize(modelPtr: Long, text: String): IntArray
        
        @JvmStatic
        external fun nativeDetokenize(modelPtr: Long, tokens: IntArray): String
        
        // Supported GGUF models
        val SUPPORTED_MODELS = listOf(
            GGUFModel("llama-2-7b-chat.Q4_0.gguf", "Llama 2 7B Chat", 3_900_000_000L, "Q4_0"),
            GGUFModel("mistral-7b-instruct-v0.2.Q4_K_M.gguf", "Mistral 7B Instruct", 4_100_000_000L, "Q4_K_M"),
            GGUFModel("phi-2.Q5_K_M.gguf", "Phi-2", 1_400_000_000L, "Q5_K_M"),
            GGUFModel("tinyllama-1.1b-chat-v1.0.Q8_0.gguf", "TinyLlama 1.1B", 650_000_000L, "Q8_0"),
            GGUFModel("stablelm-2-zephyr-1_6b.Q4_0.gguf", "StableLM 2 1.6B", 900_000_000L, "Q4_0")
        )
    }
    
    private var modelPtr: Long = 0
    private var currentModel: GGUFModel? = null
    private var modelInfo: ModelInfo? = null
    
    override val name: String = "llama.cpp"
    
    override val isInitialized: Boolean
        get() = modelPtr != 0L
    
    override suspend fun initialize(modelPath: String) {
        withContext(Dispatchers.IO) {
            try {
                release() // Clean up any existing instance
                
                val modelFile = File(modelPath)
                if (!modelFile.exists()) {
                    throw IllegalArgumentException("Model file does not exist: $modelPath")
                }
                
                // Find model info
                currentModel = SUPPORTED_MODELS.find { it.fileName == modelFile.name }
                    ?: GGUFModel(modelFile.name, "Custom GGUF Model", modelFile.length(), "Unknown")
                
                // Load the model
                modelPtr = nativeLoadModel(modelPath)
                if (modelPtr == 0L) {
                    throw RuntimeException("Failed to load GGUF model from $modelPath")
                }
                
                // Get model details from native code
                val vocabSize = nativeGetVocabSize(modelPtr)
                val contextSize = nativeGetContextSize(modelPtr)
                val modelSize = nativeGetModelSize(modelPtr)
                
                // Create model info
                modelInfo = ModelInfo(
                    name = currentModel!!.displayName,
                    sizeBytes = modelSize,
                    parameters = estimateParameters(currentModel!!),
                    quantization = currentModel!!.quantization,
                    format = "GGUF",
                    framework = LLMFramework.LLAMA_CPP
                )
                
                Log.d(TAG, "GGUF model loaded successfully: ${currentModel!!.displayName}")
                Log.d(TAG, "Vocab size: $vocabSize, Context size: $contextSize")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize llama.cpp model", e)
                release()
                throw e
            }
        }
    }
    
    override suspend fun generate(prompt: String, options: GenerationOptions): GenerationResult {
        return withContext(Dispatchers.Default) {
            if (modelPtr == 0L) {
                return@withContext GenerationResult(
                    text = "",
                    tokensGenerated = 0,
                    timeMs = 0,
                    tokensPerSecond = 0f
                )
            }
            
            try {
                val startTime = System.currentTimeMillis()
                
                // Call native generation
                val response = nativeGenerate(
                    modelPtr,
                    prompt,
                    options.maxTokens,
                    options.temperature,
                    options.topP,
                    options.topK
                )
                
                val endTime = System.currentTimeMillis()
                val tokens = tokenize(response)
                val tokensPerSecond = tokens.size.toFloat() / ((endTime - startTime) / 1000f)
                
                GenerationResult(
                    text = response,
                    tokensGenerated = tokens.size,
                    timeMs = endTime - startTime,
                    tokensPerSecond = tokensPerSecond
                )
            } catch (e: Exception) {
                Log.e(TAG, "Generation failed", e)
                GenerationResult(
                    text = "",
                    tokensGenerated = 0,
                    timeMs = 0,
                    tokensPerSecond = 0f
                )
            }
        }
    }
    
    override fun generateStream(prompt: String, options: GenerationOptions): Flow<GenerationResult> = flow {
        if (modelPtr == 0L) {
            emit(GenerationResult(
                text = "",
                tokensGenerated = 0,
                timeMs = 0,
                tokensPerSecond = 0f
            ))
            return@flow
        }
        
        try {
            val startTime = System.currentTimeMillis()
            var accumulatedText = ""
            var tokenCount = 0
            
            // For now, we'll generate the full response and emit it in chunks
            // In a real implementation, this would stream tokens as they're generated
            val fullResponse = generate(prompt, options)
            
            // If generation failed, emit the error result
            if (fullResponse.text.isEmpty()) {
                emit(fullResponse)
                return@flow
            }
            
            // Emit response word by word to simulate streaming
            val words = fullResponse.text.split(" ")
            words.forEach { word ->
                val chunk = "$word "
                accumulatedText += chunk
                tokenCount++
                
                val currentTime = System.currentTimeMillis()
                val tokensPerSecond = tokenCount.toFloat() / ((currentTime - startTime) / 1000f)
                
                emit(GenerationResult(
                    text = chunk,
                    tokensGenerated = tokenCount,
                    timeMs = currentTime - startTime,
                    tokensPerSecond = tokensPerSecond
                ))
                
                kotlinx.coroutines.delay(30) // Simulate generation delay
            }
        } catch (e: Exception) {
            Log.e(TAG, "Stream generation failed", e)
            emit(GenerationResult(
                text = "",
                tokensGenerated = 0,
                timeMs = 0,
                tokensPerSecond = 0f
            ))
        }
    }
    
    override fun getModelInfo(): ModelInfo? = modelInfo
    
    override suspend fun release() {
        withContext(Dispatchers.IO) {
            if (modelPtr != 0L) {
                nativeFreeModel(modelPtr)
                modelPtr = 0
            }
            currentModel = null
            modelInfo = null
            Log.d(TAG, "llama.cpp resources released")
        }
    }
    
    /**
     * Tokenize text using the loaded model's tokenizer
     */
    fun tokenize(text: String): IntArray {
        if (modelPtr == 0L) {
            throw IllegalStateException("Model not loaded")
        }
        return nativeTokenize(modelPtr, text)
    }
    
    /**
     * Detokenize tokens back to text
     */
    fun detokenize(tokens: IntArray): String {
        if (modelPtr == 0L) {
            throw IllegalStateException("Model not loaded")
        }
        return nativeDetokenize(modelPtr, tokens)
    }
    
    /**
     * Estimate parameter count based on model and quantization
     */
    private fun estimateParameters(model: GGUFModel): Long {
        // Rough estimation based on file size and quantization
        return when (model.quantization) {
            "Q4_0", "Q4_1", "Q4_K_S", "Q4_K_M" -> model.sizeBytes * 2  // ~4 bits per param
            "Q5_0", "Q5_1", "Q5_K_S", "Q5_K_M" -> (model.sizeBytes * 1.6).toLong()  // ~5 bits per param
            "Q8_0" -> model.sizeBytes  // ~8 bits per param
            "F16" -> model.sizeBytes / 2  // 16 bits per param
            "F32" -> model.sizeBytes / 4  // 32 bits per param
            else -> model.sizeBytes  // Default assumption
        }
    }
    
    /**
     * GGUF model information
     */
    data class GGUFModel(
        val fileName: String,
        val displayName: String,
        val sizeBytes: Long,
        val quantization: String
    )
}