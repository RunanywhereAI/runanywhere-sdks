package com.runanywhere.agent

import android.app.Application
import android.util.Log
import com.runanywhere.sdk.storage.AndroidPlatformContext
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.SDKEnvironment
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.extensions.registerMultiFileModel
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelFileDescriptor
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.core.onnx.ONNX
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelPaths
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class AgentApplication : Application() {

    companion object {
        private const val TAG = "AgentApplication"

        // Available LLM models — ordered by recommended usage on Galaxy S24 (8GB RAM).
        val AVAILABLE_MODELS = listOf(
            ModelInfo(
                id = "qwen3-4b-q4_k_m",
                name = "Qwen3 4B (Recommended)",
                url = "https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf",
                sizeBytes = 2_500_000_000L
            ),
            ModelInfo(
                id = "lfm2.5-1.2b-instruct-q4_k_m",
                name = "LFM2.5 1.2B Instruct",
                url = "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
                sizeBytes = 731_000_000L
            ),
            ModelInfo(
                id = "lfm2-8b-a1b-q4_k_m",
                name = "LFM2 8B-A1B MoE (5GB)",
                url = "https://huggingface.co/LiquidAI/LFM2-8B-A1B-GGUF/resolve/main/LFM2-8B-A1B-Q4_K_M.gguf",
                sizeBytes = 5_040_000_000L
            ),
            ModelInfo(
                id = "ds-r1-qwen3-8b-q4_k_m",
                name = "DS-R1 Qwen3 8B (Reasoning, 5GB)",
                url = "https://huggingface.co/unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF/resolve/main/DeepSeek-R1-0528-Qwen3-8B-Q4_K_M.gguf",
                sizeBytes = 5_030_000_000L
            ),
            ModelInfo(
                id = "lfm2-350m-q4_k_m",
                name = "LFM2 350M (Base, lightweight)",
                url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
                sizeBytes = 229_000_000L
            )
        )

        const val DEFAULT_MODEL = "qwen3-4b-q4_k_m"
        const val STT_MODEL_ID = "sherpa-onnx-whisper-tiny.en"
        const val VLM_MODEL_ID = "lfm2-vl-450m"
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

                // Set base directory for model storage (required for Maven SDK)
                val runanywherePath = java.io.File(filesDir, "runanywhere").absolutePath
                CppBridgeModelPaths.setBaseDirectory(runanywherePath)

                RunAnywhere.completeServicesInitialization()

                // Register backends
                try {
                    LlamaCPP.register(priority = 100) // For LLM + VLM (GGUF models)
                } catch (e: Throwable) {
                    Log.w(TAG, "LlamaCPP.register partial failure (VLM may be unavailable): ${e.message}")
                }
                ONNX.register(priority = 90) // For STT/TTS (ONNX models)

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
                    Log.i(TAG, "Registered LLM model: ${model.id}")
                }

                // Register VLM model (LFM2-VL-450M — Liquid AI, multi-file: Q4_0 main + Q8_0 mmproj)
                RunAnywhere.registerMultiFileModel(
                    id = VLM_MODEL_ID,
                    name = "LFM2-VL 450M (Q4)",
                    files = listOf(
                        ModelFileDescriptor(
                            url = "https://huggingface.co/LiquidAI/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q4_0.gguf",
                            filename = "LFM2-VL-450M-Q4_0.gguf"
                        ),
                        ModelFileDescriptor(
                            url = "https://huggingface.co/LiquidAI/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf",
                            filename = "mmproj-LFM2-VL-450M-Q8_0.gguf"
                        ),
                    ),
                    framework = InferenceFramework.LLAMA_CPP,
                    modality = ModelCategory.MULTIMODAL,
                    memoryRequirement = 323_000_000
                )
                Log.i(TAG, "Registered VLM model: $VLM_MODEL_ID")

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
