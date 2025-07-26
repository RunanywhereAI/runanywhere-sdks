package com.runanywhere.runanywhereai.llm

import android.content.Context
import android.util.Log
import com.runanywhere.runanywhereai.llm.frameworks.MediaPipeService
import com.runanywhere.runanywhereai.llm.frameworks.ONNXRuntimeService
import com.runanywhere.runanywhereai.llm.frameworks.GeminiNanoService
import com.runanywhere.runanywhereai.llm.frameworks.TFLiteService
import com.runanywhere.runanywhereai.llm.frameworks.LlamaCppService
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

/**
 * Unified manager for all LLM services
 */
class UnifiedLLMManager(private val context: Context) {
    companion object {
        private const val TAG = "UnifiedLLMManager"
    }
    
    private val services = mutableMapOf<LLMFramework, LLMService>()
    private var currentService: LLMService? = null
    
    init {
        registerServices()
    }
    
    private fun registerServices() {
        // Register available services
        services[LLMFramework.MEDIAPIPE] = MediaPipeService(context)
        services[LLMFramework.ONNX_RUNTIME] = ONNXRuntimeService(context)
        services[LLMFramework.TFLITE] = TFLiteService(context)
        services[LLMFramework.LLAMA_CPP] = LlamaCppService(context)
        
        // Register Gemini Nano if available
        try {
            val geminiService = GeminiNanoService(context)
            if (geminiService.isModelAvailable()) {
                services[LLMFramework.GEMINI_NANO] = geminiService
            }
        } catch (e: Exception) {
            Log.w(TAG, "Gemini Nano not available on this device", e)
        }
        
        // Additional services can be registered here as they're implemented
    }
    
    /**
     * Get available frameworks
     */
    fun getAvailableFrameworks(): List<LLMFramework> {
        return services.keys.toList()
    }
    
    /**
     * Get current active framework
     */
    fun getCurrentFramework(): LLMFramework? {
        return services.entries.firstOrNull { it.value == currentService }?.key
    }
    
    /**
     * Select and initialize a framework with a model
     */
    suspend fun selectFramework(framework: LLMFramework, modelPath: String) {
        Log.d(TAG, "Selecting framework: $framework with model: $modelPath")
        
        // Release current service if any
        currentService?.release()
        
        // Get and initialize new service
        currentService = services[framework]?.apply {
            try {
                initialize(modelPath)
                Log.d(TAG, "Successfully initialized $framework")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize $framework", e)
                currentService = null
                throw e
            }
        } ?: throw IllegalArgumentException("Framework $framework not available")
    }
    
    /**
     * Generate text using the current service
     */
    suspend fun generate(prompt: String, options: GenerationOptions = GenerationOptions()): String {
        val service = currentService ?: throw IllegalStateException("No LLM service selected")
        return service.generate(prompt, options)
    }
    
    /**
     * Stream generation using the current service
     */
    fun generateStream(prompt: String, options: GenerationOptions = GenerationOptions()): Flow<String> {
        return currentService?.generateStream(prompt, options) ?: emptyFlow()
    }
    
    /**
     * Get information about the current model
     */
    fun getModelInfo(): ModelInfo? {
        return currentService?.getModelInfo()
    }
    
    /**
     * Check if a service is initialized
     */
    fun isInitialized(): Boolean {
        return currentService?.isInitialized == true
    }
    
    /**
     * Release all resources
     */
    fun release() {
        currentService?.release()
        currentService = null
    }
    
    /**
     * Get recommended framework for device
     */
    fun getRecommendedFramework(): LLMFramework {
        // Recommendation logic based on device capabilities
        return when {
            // Gemini Nano is highly optimized for supported devices
            services.containsKey(LLMFramework.GEMINI_NANO) -> LLMFramework.GEMINI_NANO
            // MediaPipe is generally well-optimized for mobile
            services.containsKey(LLMFramework.MEDIAPIPE) -> LLMFramework.MEDIAPIPE
            // ONNX Runtime as fallback
            services.containsKey(LLMFramework.ONNX_RUNTIME) -> LLMFramework.ONNX_RUNTIME
            // Default to first available
            else -> services.keys.first()
        }
    }
}