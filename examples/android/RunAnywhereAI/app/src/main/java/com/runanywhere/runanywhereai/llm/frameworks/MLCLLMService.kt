package com.runanywhere.runanywhereai.llm.frameworks

import android.content.Context
import android.os.Build
import android.util.Log
import com.runanywhere.runanywhereai.llm.*
import com.runanywhere.runanywhereai.utils.HardwareDetector
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * MLC-LLM service implementation
 * MLC-LLM brings large language models to edge devices with hardware acceleration through Apache TVM
 */
class MLCLLMService(private val context: Context) : LLMService {
    companion object {
        private const val TAG = "MLCLLMService"
        
        init {
            System.loadLibrary("mlc-llm-jni")
        }
        
        @JvmStatic
        external fun nativeCreateEngine(modelPath: String, device: String): Long
        
        @JvmStatic
        external fun nativeChatCompletion(
            enginePtr: Long,
            messages: String,
            temperature: Float,
            maxTokens: Int
        ): String
        
        @JvmStatic
        external fun nativeStreamCompletion(
            enginePtr: Long,
            messages: String,
            temperature: Float,
            maxTokens: Int,
            callback: StreamCallback
        )
        
        @JvmStatic
        external fun nativeReleaseEngine(enginePtr: Long)
    }
    
    interface StreamCallback {
        fun onToken(token: String)
        fun onComplete()
        fun onError(error: String)
    }
    
    private var enginePtr: Long = 0
    private var modelInfo: ModelInfo? = null
    private var conversationHistory = mutableListOf<ChatMessage>()
    
    override val name: String = "MLC-LLM"
    override val isInitialized: Boolean
        get() = enginePtr != 0L
    
    override suspend fun initialize(modelPath: String) {
        withContext(Dispatchers.IO) {
            try {
                // Verify model file exists
                val modelFile = File(modelPath)
                if (!modelFile.exists()) {
                    throw IllegalArgumentException("Model file not found: $modelPath")
                }
                
                // Detect optimal device backend
                val device = detectOptimalDevice()
                Log.d(TAG, "Initializing MLC-LLM with device: $device")
                
                // Create native engine
                enginePtr = nativeCreateEngine(modelPath, device)
                
                if (enginePtr == 0L) {
                    throw RuntimeException("Failed to create MLC-LLM engine")
                }
                
                // Store model info
                modelInfo = ModelInfo(
                    name = modelFile.nameWithoutExtension,
                    sizeBytes = modelFile.length(),
                    parameters = estimateParameters(modelFile.length()),
                    quantization = detectQuantization(modelFile.name),
                    format = "MLC",
                    framework = LLMFramework.MLC_LLM
                )
                
                Log.d(TAG, "MLC-LLM initialized successfully with device: $device")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize MLC-LLM", e)
                throw e
            }
        }
    }
    
    private fun detectOptimalDevice(): String {
        val chipset = HardwareDetector.getChipset()
        val backend = HardwareDetector.getOptimalBackend()
        
        return when {
            // OpenCL for GPU acceleration
            HardwareDetector.hasOpenCLSupport() &&
            backend == HardwareDetector.Backend.OPENCL -> "opencl"
            
            // Vulkan for newer devices
            HardwareDetector.hasVulkanSupport() &&
            backend == HardwareDetector.Backend.VULKAN -> "vulkan"
            
            // Metal for future iOS support
            Build.MANUFACTURER.equals("Apple", ignoreCase = true) -> "metal"
            
            // CPU fallback
            else -> "cpu"
        }
    }
    
    private fun estimateParameters(fileSize: Long): Long {
        // Rough estimation based on file size
        // MLC models are typically well-optimized
        return fileSize / 2
    }
    
    private fun detectQuantization(fileName: String): String {
        return when {
            fileName.contains("q4", ignoreCase = true) -> "INT4"
            fileName.contains("q8", ignoreCase = true) -> "INT8"
            fileName.contains("fp16", ignoreCase = true) -> "FP16"
            else -> "Mixed"
        }
    }
    
    override suspend fun generate(
        prompt: String,
        options: GenerationOptions
    ): GenerationResult {
        return withContext(Dispatchers.IO) {
            if (!isInitialized) {
                return@withContext GenerationResult(
                    text = "",
                    tokensGenerated = 0,
                    timeMs = 0,
                    tokensPerSecond = 0f
                )
            }
            
            try {
                val startTime = System.currentTimeMillis()
                
                // Build messages in OpenAI format
                val messages = buildMessages(prompt)
                
                // Call native generation
                val response = nativeChatCompletion(
                    enginePtr,
                    messages.toString(),
                    options.temperature,
                    options.maxTokens
                )
                
                // Parse response
                val jsonResponse = JSONObject(response)
                
                if (jsonResponse.has("error")) {
                    throw RuntimeException("Generation error: ${jsonResponse.getString("error")}")
                }
                
                val content = jsonResponse
                    .getJSONArray("choices")
                    .getJSONObject(0)
                    .getJSONObject("message")
                    .getString("content")
                
                val endTime = System.currentTimeMillis()
                val tokensGenerated = content.length // Approximation
                val tokensPerSecond = tokensGenerated.toFloat() / ((endTime - startTime) / 1000f)
                
                // Add to conversation history
                conversationHistory.add(ChatMessage(role = ChatRole.USER, content = prompt))
                conversationHistory.add(ChatMessage(role = ChatRole.ASSISTANT, content = content))
                
                GenerationResult(
                    text = content,
                    tokensGenerated = tokensGenerated,
                    timeMs = endTime - startTime,
                    tokensPerSecond = tokensPerSecond
                )
            } catch (e: Exception) {
                Log.e(TAG, "Error during generation", e)
                GenerationResult(
                    text = "",
                    tokensGenerated = 0,
                    timeMs = 0,
                    tokensPerSecond = 0f
                )
            }
        }
    }
    
    override fun generateStream(
        prompt: String,
        options: GenerationOptions
    ): Flow<GenerationResult> = flow {
        if (!isInitialized) {
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
            val messages = buildMessages(prompt)
            var accumulatedContent = ""
            var tokenCount = 0
            
            // Add user message to history
            conversationHistory.add(ChatMessage(role = ChatRole.USER, content = prompt))
            
            withContext(Dispatchers.IO) {
                val callback = object : StreamCallback {
                    override fun onToken(token: String) {
                        try {
                            val jsonChunk = JSONObject(token)
                            if (jsonChunk.has("choices")) {
                                val delta = jsonChunk
                                    .getJSONArray("choices")
                                    .getJSONObject(0)
                                    .optJSONObject("delta")
                                
                                delta?.optString("content")?.let { content ->
                                    if (content.isNotEmpty()) {
                                        accumulatedContent += content
                                        tokenCount++
                                        
                                        val currentTime = System.currentTimeMillis()
                                        val tokensPerSecond = tokenCount.toFloat() / ((currentTime - startTime) / 1000f)
                                        
                                        kotlinx.coroutines.runBlocking {
                                            emit(GenerationResult(
                                                text = content,
                                                tokensGenerated = tokenCount,
                                                timeMs = currentTime - startTime,
                                                tokensPerSecond = tokensPerSecond
                                            ))
                                        }
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error parsing stream chunk", e)
                        }
                    }
                    
                    override fun onComplete() {
                        // Add complete response to history
                        conversationHistory.add(
                            ChatMessage(role = ChatRole.ASSISTANT, content = accumulatedContent)
                        )
                    }
                    
                    override fun onError(error: String) {
                        Log.e(TAG, "Stream error: $error")
                        kotlinx.coroutines.runBlocking {
                            emit(GenerationResult(
                                text = "",
                                tokensGenerated = 0,
                                timeMs = 0,
                                tokensPerSecond = 0f
                            ))
                        }
                    }
                }
                
                nativeStreamCompletion(
                    enginePtr,
                    messages.toString(),
                    options.temperature,
                    options.maxTokens,
                    callback
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error during streaming generation", e)
            emit(GenerationResult(
                text = "",
                tokensGenerated = 0,
                timeMs = 0,
                tokensPerSecond = 0f
            ))
        }
    }
    
    private fun buildMessages(currentPrompt: String): JSONArray {
        val messages = JSONArray()
        
        // Add conversation history
        conversationHistory.takeLast(10).forEach { msg ->
            messages.put(JSONObject().apply {
                put("role", msg.role.name.lowercase())
                put("content", msg.content)
            })
        }
        
        // Add current prompt
        messages.put(JSONObject().apply {
            put("role", "user")
            put("content", currentPrompt)
        })
        
        return messages
    }
    
    override suspend fun release() {
        withContext(Dispatchers.IO) {
            try {
                if (enginePtr != 0L) {
                    nativeReleaseEngine(enginePtr)
                    enginePtr = 0
                }
                
                conversationHistory.clear()
                modelInfo = null
                
                Log.d(TAG, "MLC-LLM service released")
            } catch (e: Exception) {
                Log.e(TAG, "Error during cleanup", e)
            }
        }
    }
    
    override fun getModelInfo(): ModelInfo? = modelInfo
    
    /**
     * Clear conversation history
     */
    fun clearHistory() {
        conversationHistory.clear()
        Log.d(TAG, "Conversation history cleared")
    }
    
    /**
     * Get current conversation history
     */
    fun getHistory(): List<ChatMessage> = conversationHistory.toList()
}