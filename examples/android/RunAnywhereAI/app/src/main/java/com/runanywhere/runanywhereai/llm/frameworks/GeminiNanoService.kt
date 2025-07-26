package com.runanywhere.runanywhereai.llm.frameworks

import android.content.Context
import android.os.Build
import android.util.Log
import com.google.ai.client.generativeai.GenerativeModel
import com.google.ai.client.generativeai.type.*
import com.runanywhere.runanywhereai.llm.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext

/**
 * Gemini Nano service implementation for on-device inference using Google AI SDK
 * 
 * Note: Gemini Nano requires:
 * - Android 14+ (API 34+)
 * - Supported devices (Pixel 8 Pro, Samsung S24 series, etc.)
 * - Google Play Services with AI Core
 */
class GeminiNanoService(private val context: Context) : LLMService {
    companion object {
        private const val TAG = "GeminiNanoService"
        private const val GEMINI_NANO_MODEL = "gemini-nano"
        
        // Device compatibility requirements
        private const val MIN_API_LEVEL = Build.VERSION_CODES.UPSIDE_DOWN_CAKE // Android 14
        private val SUPPORTED_DEVICES = listOf(
            "Pixel 8 Pro", "Pixel 8", "Pixel 9", "Pixel 9 Pro",
            "SM-S921", "SM-S926", "SM-S928" // Samsung S24 series
        )
    }
    
    private var generativeModel: GenerativeModel? = null
    private var modelInfo: ModelInfo? = null
    
    override val name: String = "Gemini Nano"
    
    override val isInitialized: Boolean
        get() = generativeModel != null
    
    override suspend fun initialize(modelPath: String) {
        withContext(Dispatchers.IO) {
            try {
                release() // Clean up any existing instance
                
                // Check device compatibility
                if (!checkDeviceCompatibility()) {
                    throw UnsupportedOperationException(
                        "Device does not support Gemini Nano. " +
                        "Requires Android 14+ and compatible hardware."
                    )
                }
                
                // For Gemini Nano, we don't use a file path - it's system-managed
                // The modelPath parameter is ignored for this implementation
                
                // Create generative model with safety settings
                generativeModel = GenerativeModel(
                    modelName = GEMINI_NANO_MODEL,
                    generationConfig = generationConfig {
                        temperature = 0.7f
                        topK = 40
                        topP = 0.9f
                        maxOutputTokens = 1024
                    },
                    safetySettings = listOf(
                        SafetySetting(HarmCategory.HARASSMENT, BlockThreshold.MEDIUM_AND_ABOVE),
                        SafetySetting(HarmCategory.HATE_SPEECH, BlockThreshold.MEDIUM_AND_ABOVE),
                        SafetySetting(HarmCategory.SEXUALLY_EXPLICIT, BlockThreshold.MEDIUM_AND_ABOVE),
                        SafetySetting(HarmCategory.DANGEROUS_CONTENT, BlockThreshold.MEDIUM_AND_ABOVE)
                    )
                )
                
                // Create model info
                modelInfo = ModelInfo(
                    name = "Gemini Nano",
                    sizeBytes = 0, // Size is system-managed
                    parameters = 3_250_000_000L, // Approximate parameter count
                    quantization = "INT4",
                    format = "Gemini",
                    framework = LLMFramework.GEMINI_NANO
                )
                
                Log.d(TAG, "Gemini Nano initialized successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize Gemini Nano", e)
                throw e
            }
        }
    }
    
    override suspend fun generate(prompt: String, options: GenerationOptions): String {
        return withContext(Dispatchers.Default) {
            val model = generativeModel ?: throw IllegalStateException("Service not initialized")
            
            try {
                // Update generation config based on options
                val updatedModel = GenerativeModel(
                    modelName = GEMINI_NANO_MODEL,
                    generationConfig = generationConfig {
                        temperature = options.temperature
                        topK = options.topK
                        topP = options.topP
                        maxOutputTokens = options.maxTokens
                        stopSequences = options.stopSequences
                    }
                )
                
                // Generate response
                val response = updatedModel.generateContent(prompt)
                response.text ?: throw RuntimeException("Empty response from Gemini Nano")
            } catch (e: Exception) {
                Log.e(TAG, "Generation failed", e)
                throw e
            }
        }
    }
    
    override fun generateStream(prompt: String, options: GenerationOptions): Flow<String> = flow {
        val model = generativeModel ?: throw IllegalStateException("Service not initialized")
        
        try {
            // Update generation config based on options
            val updatedModel = GenerativeModel(
                modelName = GEMINI_NANO_MODEL,
                generationConfig = generationConfig {
                    temperature = options.temperature
                    topK = options.topK
                    topP = options.topP
                    maxOutputTokens = options.maxTokens
                    stopSequences = options.stopSequences
                }
            )
            
            // Stream generation
            val responseFlow = updatedModel.generateContentStream(prompt)
            responseFlow.collect { chunk ->
                chunk.text?.let { emit(it) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Stream generation failed", e)
            throw e
        }
    }
    
    override fun getModelInfo(): ModelInfo? = modelInfo
    
    override fun release() {
        generativeModel = null
        modelInfo = null
        Log.d(TAG, "Gemini Nano resources released")
    }
    
    /**
     * Check if the current device supports Gemini Nano
     */
    private fun checkDeviceCompatibility(): Boolean {
        // Check Android version
        if (Build.VERSION.SDK_INT < MIN_API_LEVEL) {
            Log.w(TAG, "Device running Android ${Build.VERSION.SDK_INT}, requires $MIN_API_LEVEL+")
            return false
        }
        
        // Check device model
        val deviceModel = Build.MODEL
        val isSupported = SUPPORTED_DEVICES.any { deviceModel.contains(it, ignoreCase = true) }
        
        if (!isSupported) {
            Log.w(TAG, "Device model '$deviceModel' may not support Gemini Nano")
            // Don't hard fail - let the SDK determine actual compatibility
        }
        
        return true
    }
    
    /**
     * Check if Gemini Nano is available on the device
     * This would typically check with Google Play Services
     */
    fun isModelAvailable(): Boolean {
        return try {
            // In a real implementation, this would check with AI Core
            // For now, we rely on device compatibility
            checkDeviceCompatibility()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check model availability", e)
            false
        }
    }
}