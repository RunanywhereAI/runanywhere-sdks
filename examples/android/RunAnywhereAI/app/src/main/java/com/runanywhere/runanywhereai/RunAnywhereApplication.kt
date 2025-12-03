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
                SDKEnvironment.DEVELOPMENT
            } else {
                SDKEnvironment.PRODUCTION
            }
            Log.i("RunAnywhereApp", "🚀 Environment: $environment (DEBUG=${BuildConfig.DEBUG})")

            // Initialize SDK based on environment (matches iOS pattern)
            if (environment == SDKEnvironment.DEVELOPMENT) {
                // Development Mode - No API key needed!
                // In development mode, analytics are automatically sent to Supabase
                // for performance tracking and debugging. No user data is collected.
                RunAnywhere.initialize(
                    context = this@RunAnywhereApplication,
                    apiKey = "dev",
                    baseURL = "localhost",
                    environment = SDKEnvironment.DEVELOPMENT
                )
                Log.i("RunAnywhereApp", "✅ SDK initialized in DEVELOPMENT mode (dev analytics enabled)")

                // Register frameworks and models using iOS-matching pattern
                registerAdaptersForDevelopment()

            } else {
                // Production Mode - Real API key required
                // In production mode, analytics are sent to RunAnywhere backend
                // for telemetry and performance monitoring
                val apiKey = "talk_to_runanywhere_team"
                val baseURL = "talk_to_runanywhere_team"

                RunAnywhere.initialize(
                    context = this@RunAnywhereApplication,
                    apiKey = apiKey,
                    baseURL = baseURL,
                    environment = SDKEnvironment.PRODUCTION
                )
                Log.i("RunAnywhereApp", "✅ SDK initialized in PRODUCTION mode (production analytics enabled)")

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
        Log.i("RunAnywhereApp", "📦 Registering adapters with custom models for DEVELOPMENT mode")

        // =====================================================
        // 1. LlamaCPP Framework (TEXT_TO_TEXT modality)
        // Matches iOS: RunAnywhere.registerFramework(LlamaCPPCoreAdapter(), models: [...])
        // This provides native C++ llama.cpp performance
        // =====================================================
        Log.i("RunAnywhereApp", "📝 Registering LlamaCPP adapter with LLM models...")

        RunAnywhere.registerFramework(
            adapter = LlamaCppAdapter.shared,
            models = listOf(
                // Qwen 2.5 0.5B Instruct Q6_K - Small but capable (~600MB)
                // Matches iOS: qwen-2.5-0.5b-instruct-q6-k
                ModelRegistration(
                    id = "qwen-2.5-0.5b-instruct-q6-k",
                    name = "Qwen 2.5 0.5B Instruct Q6_K",
                    url = "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
                    framework = LLMFramework.LLAMA_CPP,
                    modality = FrameworkModality.TEXT_TO_TEXT,
                    format = ModelFormat.GGUF,
                    memoryRequirement = 600_000_000L
                ),
                // LiquidAI LFM2 350M Q4_K_M - Smallest and fastest (~250MB)
                // Matches iOS: lfm2-350m-q4-k-m
                ModelRegistration(
                    id = "lfm2-350m-q4-k-m",
                    name = "LiquidAI LFM2 350M Q4_K_M",
                    url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
                    framework = LLMFramework.LLAMA_CPP,
                    modality = FrameworkModality.TEXT_TO_TEXT,
                    format = ModelFormat.GGUF,
                    memoryRequirement = 250_000_000L
                ),
                // LiquidAI LFM2 350M Q8_0 - Highest quality small model (~400MB)
                // Matches iOS: lfm2-350m-q8-0
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
        Log.i("RunAnywhereApp", "✅ LlamaCPP Core registered (runanywhere-core backend)")

        // =====================================================
        // 2. ONNX Runtime Framework (VOICE_TO_TEXT, TEXT_TO_VOICE modalities)
        // Matches iOS: RunAnywhere.registerFramework(ONNXAdapter.shared, models: [...])
        // Note: WhisperKit models are iOS-only (CoreML), we use ONNX Sherpa models on Android
        // =====================================================
        Log.i("RunAnywhereApp", "🎤🔊 Registering ONNX adapter with STT and TTS models...")

        RunAnywhere.registerFramework(
            adapter = ONNXAdapter.shared,
            models = listOf(
                // STT Models (VOICE_TO_TEXT modality)
                // NOTE: tar.bz2 extraction is supported on Android via Commons Compress
                // Sherpa ONNX Whisper Tiny English (~75MB)
                // Matches iOS: sherpa-whisper-tiny-onnx
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
                // Matches iOS: sherpa-whisper-small-onnx
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
                // Using sherpa-onnx tar.bz2 packages (includes model, tokens, and espeak-ng-data)
                // Piper TTS - US English Lessac Medium (~65MB)
                // Matches iOS: piper-en-us-lessac-medium
                ModelRegistration(
                    id = "piper-en-us-lessac-medium",
                    name = "Piper TTS (US English - Medium)",
                    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2",
                    framework = LLMFramework.ONNX,
                    modality = FrameworkModality.TEXT_TO_VOICE,
                    format = ModelFormat.ONNX,
                    memoryRequirement = 65_000_000L
                ),
                // Piper TTS - British English Alba Medium (~65MB)
                // Matches iOS: piper-en-gb-alba-medium
                ModelRegistration(
                    id = "piper-en-gb-alba-medium",
                    name = "Piper TTS (British English)",
                    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2",
                    framework = LLMFramework.ONNX,
                    modality = FrameworkModality.TEXT_TO_VOICE,
                    format = ModelFormat.ONNX,
                    memoryRequirement = 65_000_000L
                )
            )
        )
        Log.i("RunAnywhereApp", "✅ ONNX Runtime registered (includes STT and TTS providers)")

        // Note: WhisperKit is iOS-only (uses CoreML), ONNX Sherpa serves the same purpose on Android
        // Note: FluidAudioDiarization is iOS-only, can be added when Android module is available
        // Note: FoundationModels requires iOS 26+ / macOS 26+, not applicable to Android

        // Scan file system for already downloaded models
        Log.i("RunAnywhereApp", "🔍 Scanning for previously downloaded models...")
        RunAnywhere.scanForDownloadedModels()
        Log.i("RunAnywhereApp", "✅ File system scan complete")

        Log.i("RunAnywhereApp", "🎉 All adapters registered for development")
    }

    /**
     * Register framework adapters with custom models for PRODUCTION mode.
     * Hardcoded models provide immediate user access, backend can add more dynamically.
     * Matches iOS registerAdaptersForProduction() pattern exactly.
     */
    private suspend fun registerAdaptersForProduction() {
        Log.i("RunAnywhereApp", "📦 Registering adapters with custom models for PRODUCTION mode")
        Log.i("RunAnywhereApp", "💡 Hardcoded models provide immediate user access, backend can add more dynamically")

        // =====================================================
        // 1. LlamaCPP Framework (TEXT_TO_TEXT modality)
        // Same models as development mode for consistent user experience
        // =====================================================
        Log.i("RunAnywhereApp", "📝 Registering LlamaCPP adapter with LLM models...")

        RunAnywhere.registerFramework(
            adapter = LlamaCppAdapter.shared,
            models = listOf(
                // Qwen 2.5 0.5B Instruct Q6_K - Small but capable (~600MB)
                ModelRegistration(
                    id = "qwen-2.5-0.5b-instruct-q6-k",
                    name = "Qwen 2.5 0.5B Instruct Q6_K",
                    url = "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
                    framework = LLMFramework.LLAMA_CPP,
                    modality = FrameworkModality.TEXT_TO_TEXT,
                    format = ModelFormat.GGUF,
                    memoryRequirement = 600_000_000L
                ),
                // LiquidAI LFM2 350M Q4_K_M - Smallest and fastest (~250MB)
                ModelRegistration(
                    id = "lfm2-350m-q4-k-m",
                    name = "LiquidAI LFM2 350M Q4_K_M",
                    url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
                    framework = LLMFramework.LLAMA_CPP,
                    modality = FrameworkModality.TEXT_TO_TEXT,
                    format = ModelFormat.GGUF,
                    memoryRequirement = 250_000_000L
                ),
                // LiquidAI LFM2 350M Q8_0 - Highest quality small model (~400MB)
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
        Log.i("RunAnywhereApp", "✅ LlamaCPP adapter registered with hardcoded models")

        // =====================================================
        // 2. ONNX Runtime Framework (VOICE_TO_TEXT, TEXT_TO_VOICE modalities)
        // Same models as development mode for consistent user experience
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
                    name = "Piper TTS (US English - Medium)",
                    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2",
                    framework = LLMFramework.ONNX,
                    modality = FrameworkModality.TEXT_TO_VOICE,
                    format = ModelFormat.ONNX,
                    memoryRequirement = 65_000_000L
                ),
                // Piper TTS - British English Alba Medium (~65MB)
                ModelRegistration(
                    id = "piper-en-gb-alba-medium",
                    name = "Piper TTS (British English)",
                    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2",
                    framework = LLMFramework.ONNX,
                    modality = FrameworkModality.TEXT_TO_VOICE,
                    format = ModelFormat.ONNX,
                    memoryRequirement = 65_000_000L
                )
            )
        )
        Log.i("RunAnywhereApp", "✅ ONNX adapter registered with hardcoded models")

        // Scan file system for already downloaded models
        // This allows models downloaded previously to be discovered
        Log.i("RunAnywhereApp", "🔍 Scanning for previously downloaded models...")
        RunAnywhere.scanForDownloadedModels()
        Log.i("RunAnywhereApp", "✅ File system scan complete")

        Log.i("RunAnywhereApp", "🎉 All adapters registered for production with hardcoded models")
        Log.i("RunAnywhereApp", "📡 Backend can dynamically add more models via console API")
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
