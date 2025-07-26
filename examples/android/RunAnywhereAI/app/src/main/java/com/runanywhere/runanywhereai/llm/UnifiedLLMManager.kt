package com.runanywhere.runanywhereai.llm

import android.content.Context
import android.util.Log
import com.runanywhere.runanywhereai.llm.frameworks.MediaPipeService
import com.runanywhere.runanywhereai.llm.frameworks.ONNXRuntimeService
import com.runanywhere.runanywhereai.llm.frameworks.GeminiNanoService
import com.runanywhere.runanywhereai.llm.frameworks.TFLiteService
import com.runanywhere.runanywhereai.llm.frameworks.LlamaCppService
import com.runanywhere.runanywhereai.llm.frameworks.ExecuTorchService
import com.runanywhere.runanywhereai.llm.frameworks.MLCLLMService
import com.runanywhere.runanywhereai.llm.frameworks.AICoreLLMService
import com.runanywhere.runanywhereai.llm.frameworks.PicoLLMService
import android.os.Build
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
    
    private fun tryRegisterService(framework: LLMFramework, serviceProvider: () -> LLMService) {
        try {
            val service = serviceProvider()
            services[framework] = service
            Log.d(TAG, "Successfully registered service: $framework")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register service $framework - native dependencies may be missing", e)
        }
    }
    
    private fun registerServices() {
        // Register available services
        tryRegisterService(LLMFramework.MEDIAPIPE) { MediaPipeService(context) }
        tryRegisterService(LLMFramework.ONNX_RUNTIME) { ONNXRuntimeService(context) }
        tryRegisterService(LLMFramework.TFLITE) { TFLiteService(context) }
        tryRegisterService(LLMFramework.LLAMA_CPP) { LlamaCppService(context) }
        tryRegisterService(LLMFramework.EXECUTORCH) { ExecuTorchService(context) }
        tryRegisterService(LLMFramework.MLC_LLM) { MLCLLMService(context) }
        
        // Register Gemini Nano if available
        try {
            val geminiService = GeminiNanoService(context)
            if (geminiService.isModelAvailable()) {
                services[LLMFramework.GEMINI_NANO] = geminiService
            }
        } catch (e: Exception) {
            Log.w(TAG, "Gemini Nano not available on this device", e)
        }
        
        // Register AI Core if available (Android 14+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                services[LLMFramework.AI_CORE] = AICoreLLMService(context)
            } catch (e: Exception) {
                Log.w(TAG, "AI Core not available on this device", e)
            }
        }
        
        // Register picoLLM (requires access key)
        // Note: In production, the access key should be stored securely
        val picoAccessKey = "" // TODO: Add Picovoice access key
        if (picoAccessKey.isNotEmpty()) {
            tryRegisterService(LLMFramework.PICOLLM) { PicoLLMService(context, picoAccessKey) }
        }
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
    suspend fun generate(prompt: String, options: GenerationOptions = GenerationOptions()): GenerationResult {
        val service = currentService ?: throw IllegalStateException("No LLM service selected")
        return service.generate(prompt, options)
    }
    
    /**
     * Stream generation using the current service
     */
    fun generateStream(prompt: String, options: GenerationOptions = GenerationOptions()): Flow<GenerationResult> {
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
    suspend fun release() {
        currentService?.release()
        currentService = null
    }
    
    /**
     * Get recommended framework for device
     */
    fun getRecommendedFramework(): LLMFramework {
        // Recommendation logic based on device capabilities
        return when {
            // AI Core is the newest and most optimized for Android 14+
            services.containsKey(LLMFramework.AI_CORE) -> LLMFramework.AI_CORE
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