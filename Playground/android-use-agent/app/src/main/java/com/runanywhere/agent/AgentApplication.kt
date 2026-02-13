package com.runanywhere.agent

import android.app.Application
import android.util.Log
import com.runanywhere.sdk.storage.AndroidPlatformContext
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.SDKEnvironment
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.core.onnx.ONNX
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class AgentApplication : Application() {

    companion object {
        private const val TAG = "AgentApplication"

        // Available models
        val AVAILABLE_MODELS = listOf(
            ModelInfo(
                id = "smollm2-360m-instruct-q8_0",
                name = "SmolLM2 360M (Fast)",
                url = "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf",
                sizeBytes = 400_000_000L
            ),
            ModelInfo(
                id = "qwen2.5-1.5b-instruct-q4_k_m",
                name = "Qwen2.5 1.5B (Best)",
                url = "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
                sizeBytes = 1_200_000_000L
            ),
            ModelInfo(
                id = "lfm2.5-1.2b-instruct-q4_k_m",
                name = "LFM2.5 1.2B (Edge)",
                url = "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
                sizeBytes = 800_000_000L
            )
        )

        const val DEFAULT_MODEL = "qwen2.5-1.5b-instruct-q4_k_m"
        const val STT_MODEL_ID = "sherpa-onnx-whisper-tiny.en"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        initializeSDK()
    }

    private fun initializeSDK() {
        scope.launch {
            try {
                delay(100) // Allow app to initialize

                Log.i(TAG, "Initializing RunAnywhere SDK...")
                AndroidPlatformContext.initialize(applicationContext)
                RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)
                RunAnywhere.completeServicesInitialization()

                // Register backends
                LlamaCPP.register(priority = 100)
                ONNX.register(priority = 90)

                // Register STT model (Whisper Tiny English, ~75MB)
                RunAnywhere.registerModel(
                    id = STT_MODEL_ID,
                    name = "Whisper Tiny (English)",
                    url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
                    framework = InferenceFramework.ONNX,
                    modality = ModelCategory.SPEECH_RECOGNITION
                )
                Log.i(TAG, "Registered STT model: $STT_MODEL_ID")

                // Register available LLM models
                AVAILABLE_MODELS.forEach { model ->
                    RunAnywhere.registerModel(
                        id = model.id,
                        name = model.name,
                        url = model.url,
                        framework = InferenceFramework.LLAMA_CPP,
                        memoryRequirement = model.sizeBytes
                    )
                    Log.i(TAG, "Registered model: ${model.id}")
                }

                Log.i(TAG, "RunAnywhere SDK initialized successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize SDK: ${e.message}", e)
            }
        }
    }
}

data class ModelInfo(
    val id: String,
    val name: String,
    val url: String,
    val sizeBytes: Long
)
