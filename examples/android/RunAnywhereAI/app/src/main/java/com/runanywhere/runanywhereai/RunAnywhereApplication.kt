package com.runanywhere.runanywhereai

import android.app.Application
import android.util.Log
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.public.extensions.registerFramework
import com.runanywhere.sdk.public.models.ModelRegistration
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.FrameworkModality
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.llm.llamacpp.LlamaCppAdapter
import com.runanywhere.sdk.core.onnx.ONNXAdapter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Application class for RunAnywhere AI sample app
 * Matches iOS RunAnywhereAIApp.swift initialization pattern exactly.
 *
 * Uses strongly-typed enums for all framework and modality parameters:
 * - LLMFramework enum for framework specification
 * - FrameworkModality enum for modality specification
 * - ModelFormat enum for format specification
 * - ModelRegistration data class for model registration
 */
class RunAnywhereApplication : Application() {

    @Volatile
    private var isSDKInitialized = false

    @Volatile
    private var initializationError: Throwable? = null

    override fun onCreate() {
        super.onCreate()

        Log.i("RunAnywhereApp", "🏁 App launched, initializing SDK...")

        // Initialize SDK asynchronously to match iOS pattern
        kotlinx.coroutines.GlobalScope.launch(Dispatchers.IO) {
            initializeSDK()
        }
    }

    private suspend fun initializeSDK() {
        try {
            initializationError = null
            Log.i("RunAnywhereApp", "🎯 Starting SDK initialization...")

            val startTime = System.currentTimeMillis()

            // Determine environment (matches iOS pattern)
            val environment = if (BuildConfig.DEBUG) {
                Log.i("RunAnywhereApp", "🛠️ Using DEVELOPMENT mode - No API key required!")
                SDKEnvironment.DEVELOPMENT
            } else {
                Log.i("RunAnywhereApp", "🚀 Using PRODUCTION mode")
                SDKEnvironment.PRODUCTION
            }

            // Initialize SDK based on environment (matches iOS pattern)
            if (environment == SDKEnvironment.DEVELOPMENT) {
                // Development Mode - No API key needed!
                RunAnywhere.initialize(
                    context = this@RunAnywhereApplication,
                    apiKey = "dev",
                    baseURL = "localhost",
                    environment = SDKEnvironment.DEVELOPMENT
                )
                Log.i("RunAnywhereApp", "✅ SDK initialized in DEVELOPMENT mode")

                // Register frameworks and models using iOS-matching pattern
                registerAdaptersForDevelopment()

            } else {
                // Production Mode - Real API key required
                val apiKey = getSecureApiKey()
                val baseURL = "https://api.runanywhere.ai"

                RunAnywhere.initialize(
                    context = this@RunAnywhereApplication,
                    apiKey = apiKey,
                    baseURL = baseURL,
                    environment = SDKEnvironment.PRODUCTION
                )
                Log.i("RunAnywhereApp", "✅ SDK initialized in PRODUCTION mode")

                // In production, register adapters only (models come from backend)
                registerAdaptersForProduction()
            }

            val initTime = System.currentTimeMillis() - startTime
            Log.i("RunAnywhereApp", "✅ SDK successfully initialized in ${initTime}ms")
            Log.i("RunAnywhereApp", "🎯 SDK Status: Active=${RunAnywhere.isInitialized}")

            isSDKInitialized = true

        } catch (e: Exception) {
            Log.e("RunAnywhereApp", "❌ SDK initialization failed: ${e.message}")
            e.printStackTrace()
            initializationError = e
            isSDKInitialized = false
        }
    }

    /**
     * Register framework adapters with models for DEVELOPMENT mode.
     * Matches iOS RunAnywhereAIApp.swift registerAdaptersForDevelopment() exactly.
     *
     * All parameters use strongly-typed enums:
     * - LLMFramework.LLAMA_CPP, LLMFramework.ONNX
     * - FrameworkModality.TEXT_TO_TEXT, VOICE_TO_TEXT, TEXT_TO_VOICE
     * - ModelFormat.GGUF, ModelFormat.ONNX
     */
    private suspend fun registerAdaptersForDevelopment() {
        Log.i("RunAnywhereApp", "🔧 Registering Framework Adapters for DEVELOPMENT mode")

        // =====================================================
        // 1. LlamaCPP Framework (TEXT_TO_TEXT modality)
        // Matches iOS: RunAnywhere.registerFramework(LlamaCPPCoreAdapter(), models: [...])
        // =====================================================
        Log.i("RunAnywhereApp", "📝 Registering LlamaCPP adapter with LLM models...")

        RunAnywhere.registerFramework(
            adapter = LlamaCppAdapter.shared,
            models = listOf(
                // SmolLM2 360M - smallest and fastest (~500MB)
                ModelRegistration(
                    id = "smollm2-360m-q8-0",
                    name = "SmolLM2 360M Q8_0",
                    url = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
                    framework = LLMFramework.LLAMA_CPP,
                    modality = FrameworkModality.TEXT_TO_TEXT,
                    format = ModelFormat.GGUF,
                    memoryRequirement = 500_000_000L
                ),
                // Qwen 2.5 0.5B - small but capable (~600MB)
                ModelRegistration(
                    id = "qwen-2.5-0.5b-instruct-q6-k",
                    name = "Qwen 2.5 0.5B Instruct Q6_K",
                    url = "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
                    framework = LLMFramework.LLAMA_CPP,
                    modality = FrameworkModality.TEXT_TO_TEXT,
                    format = ModelFormat.GGUF,
                    memoryRequirement = 600_000_000L
                ),
                // Llama 3.2 1B - good quality
                ModelRegistration(
                    id = "llama-3.2-1b-instruct-q6-k",
                    name = "Llama 3.2 1B Instruct Q6_K",
                    url = "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K.gguf",
                    framework = LLMFramework.LLAMA_CPP,
                    modality = FrameworkModality.TEXT_TO_TEXT,
                    format = ModelFormat.GGUF,
                    memoryRequirement = 1_000_000_000L
                ),
                // QWEN 2 0.5B - compact model
                ModelRegistration(
                    id = "qwen2-0.5b-instruct-q4-0",
                    name = "QWEN 2 0.5B Q4_0 Instruct",
                    url = "https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF/resolve/main/qwen2-0_5b-instruct-q4_0.gguf",
                    framework = LLMFramework.LLAMA_CPP,
                    modality = FrameworkModality.TEXT_TO_TEXT,
                    format = ModelFormat.GGUF,
                    memoryRequirement = 400_000_000L
                ),
                // SmolLM2 1.7B - larger but capable
                ModelRegistration(
                    id = "smollm2-1.7b-instruct-q6-k-l",
                    name = "SmolLM2 1.7B Instruct Q6_K_L",
                    url = "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q6_K_L.gguf",
                    framework = LLMFramework.LLAMA_CPP,
                    modality = FrameworkModality.TEXT_TO_TEXT,
                    format = ModelFormat.GGUF,
                    memoryRequirement = 1_700_000_000L
                ),
                // Qwen 2.5 1.5B - good for longer context
                ModelRegistration(
                    id = "qwen-2.5-1.5b-instruct-q6-k",
                    name = "Qwen 2.5 1.5B Instruct Q6_K",
                    url = "https://huggingface.co/ZeroWw/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct.q6_k.gguf",
                    framework = LLMFramework.LLAMA_CPP,
                    modality = FrameworkModality.TEXT_TO_TEXT,
                    format = ModelFormat.GGUF,
                    memoryRequirement = 1_500_000_000L
                ),
                // LiquidAI LFM2 350M Q4_K_M - smallest and fastest (~250MB)
                ModelRegistration(
                    id = "lfm2-350m-q4-k-m",
                    name = "LiquidAI LFM2 350M Q4_K_M",
                    url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
                    framework = LLMFramework.LLAMA_CPP,
                    modality = FrameworkModality.TEXT_TO_TEXT,
                    format = ModelFormat.GGUF,
                    memoryRequirement = 250_000_000L
                ),
                // LiquidAI LFM2 350M Q8_0 - highest quality (~400MB)
                ModelRegistration(
                    id = "lfm2-350m-q8-0",
                    name = "LiquidAI LFM2 350M Q8_0",
                    url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
                    framework = LLMFramework.LLAMA_CPP,
                    modality = FrameworkModality.TEXT_TO_TEXT,
                    format = ModelFormat.GGUF,
                    memoryRequirement = 400_000_000L
                )
            )
        )
        Log.i("RunAnywhereApp", "✅ Registered LlamaCPP adapter with 8 LLM models")

        // =====================================================
        // 2. ONNX Runtime Framework (VOICE_TO_TEXT, TEXT_TO_VOICE modalities)
        // Matches iOS: RunAnywhere.registerFramework(ONNXAdapter.shared, models: [...])
        // Note: On Android we use ONNX Sherpa models (WhisperKit is iOS-only CoreML)
        // =====================================================
        Log.i("RunAnywhereApp", "🎤🔊 Registering ONNX adapter with STT and TTS models...")

        RunAnywhere.registerFramework(
            adapter = ONNXAdapter.shared,
            models = listOf(
                // STT Models (VOICE_TO_TEXT modality)
                // Sherpa ONNX Whisper Tiny English (~75MB)
                ModelRegistration(
                    id = "sherpa-whisper-tiny-onnx",
                    name = "Sherpa Whisper Tiny (ONNX)",
                    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2",
                    framework = LLMFramework.ONNX,
                    modality = FrameworkModality.VOICE_TO_TEXT,
                    format = ModelFormat.ONNX,
                    memoryRequirement = 75_000_000L
                ),
                // Sherpa ONNX Whisper Small (~250MB)
                ModelRegistration(
                    id = "sherpa-whisper-small-onnx",
                    name = "Sherpa Whisper Small (ONNX)",
                    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2",
                    framework = LLMFramework.ONNX,
                    modality = FrameworkModality.VOICE_TO_TEXT,
                    format = ModelFormat.ONNX,
                    memoryRequirement = 250_000_000L
                ),

                // TTS Models (TEXT_TO_VOICE modality)
                // Piper TTS - US English Lessac Medium (~65MB)
                ModelRegistration(
                    id = "piper-en-us-lessac-medium",
                    name = "Piper TTS US English Medium",
                    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2",
                    framework = LLMFramework.ONNX,
                    modality = FrameworkModality.TEXT_TO_VOICE,
                    format = ModelFormat.ONNX,
                    memoryRequirement = 65_000_000L
                ),
                // Piper TTS - British English Alba Medium (~65MB)
                ModelRegistration(
                    id = "piper-en-gb-alba-medium",
                    name = "Piper TTS British English Medium",
                    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2",
                    framework = LLMFramework.ONNX,
                    modality = FrameworkModality.TEXT_TO_VOICE,
                    format = ModelFormat.ONNX,
                    memoryRequirement = 65_000_000L
                )
            )
        )
        Log.i("RunAnywhereApp", "✅ Registered ONNX adapter with 2 STT + 2 TTS models")

        // Note: WhisperKit is iOS-only (uses CoreML), ONNX serves the same purpose on Android
        // Note: FluidAudioDiarization registration can be added when the module is available
        // Note: FoundationModels is iOS 26+ only, not applicable to Android

        // Scan file system for already downloaded models
        Log.i("RunAnywhereApp", "🔍 Scanning for previously downloaded models...")
        RunAnywhere.scanForDownloadedModels()
        Log.i("RunAnywhereApp", "✅ File system scan complete")

        Log.i("RunAnywhereApp", "🎉 All frameworks registered for development:")
        Log.i("RunAnywhereApp", "   📝 LLM: 8 models (LLAMA_CPP, TEXT_TO_TEXT)")
        Log.i("RunAnywhereApp", "   🎤 STT: 2 models (ONNX, VOICE_TO_TEXT)")
        Log.i("RunAnywhereApp", "   🔊 TTS: 2 models (ONNX, TEXT_TO_VOICE)")
        Log.i("RunAnywhereApp", "   📦 Total: 12 models")
    }

    /**
     * Register framework adapters only for PRODUCTION mode.
     * Models will be fetched from backend console.
     * Matches iOS registerAdaptersForProduction() pattern.
     */
    private suspend fun registerAdaptersForProduction() {
        Log.i("RunAnywhereApp", "🔧 Registering Framework Adapters for PRODUCTION mode")

        // Register adapters without hardcoded models (models come from backend)
        RunAnywhere.registerFramework(adapter = LlamaCppAdapter.shared)
        Log.i("RunAnywhereApp", "✅ Registered LlamaCPP adapter")

        RunAnywhere.registerFramework(adapter = ONNXAdapter.shared)
        Log.i("RunAnywhereApp", "✅ Registered ONNX adapter")

        Log.i("RunAnywhereApp", "📡 Models will be fetched from backend console via API")
    }

    /**
     * Retrieves API key from secure storage.
     */
    private fun getSecureApiKey(): String {
        // TODO: Implement secure API key retrieval before production deployment
        return "dev-placeholder-key"
    }

    /**
     * Get SDK initialization status
     */
    fun isSDKReady(): Boolean = isSDKInitialized

    /**
     * Get initialization error if any
     */
    fun getInitializationError(): Throwable? = initializationError

    /**
     * Retry SDK initialization
     */
    suspend fun retryInitialization() {
        withContext(Dispatchers.IO) {
            initializeSDK()
        }
    }
}
