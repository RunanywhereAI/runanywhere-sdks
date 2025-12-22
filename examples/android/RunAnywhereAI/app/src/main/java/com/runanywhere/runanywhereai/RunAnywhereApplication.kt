package com.runanywhere.runanywhereai

import android.app.Application
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.runanywhere.sdk.core.addModel
import com.runanywhere.sdk.core.onnx.ONNX
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.models.enums.ModelArtifactType
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.`public`.RunAnywhere
import com.runanywhere.sdk.storage.AndroidPlatformContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Represents the SDK initialization state.
 * Matches iOS pattern: isSDKInitialized + initializationError conditional rendering.
 */
sealed class SDKInitializationState {
    /** SDK is currently initializing */
    data object Loading : SDKInitializationState()

    /** SDK initialized successfully */
    data object Ready : SDKInitializationState()

    /** SDK initialization failed */
    data class Error(val error: Throwable) : SDKInitializationState()
}

class RunAnywhereApplication : Application() {
    companion object {
        private var instance: RunAnywhereApplication? = null

        /** Get the application instance */
        fun getInstance(): RunAnywhereApplication = instance ?: throw IllegalStateException("Application not initialized")
    }

    /**
     * Application-scoped CoroutineScope for SDK initialization and background work.
     * Uses SupervisorJob to prevent failures in one coroutine from affecting others.
     * This replaces GlobalScope to ensure proper lifecycle management.
     */
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    @Volatile
    private var isSDKInitialized = false

    @Volatile
    private var initializationError: Throwable? = null

    /** Observable SDK initialization state for Compose UI - matches iOS pattern */
    private val _initializationState = MutableStateFlow<SDKInitializationState>(SDKInitializationState.Loading)
    val initializationState: StateFlow<SDKInitializationState> = _initializationState.asStateFlow()

    override fun onCreate() {
        super.onCreate()
        instance = this

        Log.i("RunAnywhereApp", "🏁 App launched, initializing SDK...")

        // Post initialization to main thread's message queue to ensure system is ready
        // This prevents crashes on devices where device-encrypted storage hasn't mounted yet
        Handler(Looper.getMainLooper()).postDelayed({
            // Initialize SDK asynchronously using application-scoped coroutine
            applicationScope.launch(Dispatchers.IO) {
                try {
                    // Additional small delay to ensure storage is mounted
                    delay(200)
                    initializeSDK()
                } catch (e: Exception) {
                    Log.e("RunAnywhereApp", "❌ Fatal error during SDK initialization: ${e.message}", e)
                    // Don't crash the app - let it continue without SDK
                }
            }
        }, 100) // 100ms delay to let system mount storage
    }

    override fun onTerminate() {
        // Cancel all coroutines when app terminates
        applicationScope.cancel()
        super.onTerminate()
    }

    private suspend fun initializeSDK() {
        initializationError = null
        Log.i("RunAnywhereApp", "🎯 Starting SDK initialization...")
        Log.w("RunAnywhereApp", "=======================================================")
        Log.w("RunAnywhereApp", "🔍 BUILD INFO - CHECK THIS FOR ANALYTICS DEBUGGING:")
        Log.w("RunAnywhereApp", "   BuildConfig.DEBUG = ${BuildConfig.DEBUG}")
        Log.w("RunAnywhereApp", "   BuildConfig.DEBUG_MODE = ${BuildConfig.DEBUG_MODE}")
        Log.w("RunAnywhereApp", "   BuildConfig.BUILD_TYPE = ${BuildConfig.BUILD_TYPE}")
        Log.w("RunAnywhereApp", "   Package name = ${applicationContext.packageName}")
        Log.w("RunAnywhereApp", "=======================================================")

        val startTime = System.currentTimeMillis()

        // Determine environment based on DEBUG_MODE (NOT BuildConfig.DEBUG!)
        // BuildConfig.DEBUG is tied to isDebuggable flag, which we set to true for release builds
        // to allow logging. BuildConfig.DEBUG_MODE correctly reflects debug vs release build type.
        val environment =
            if (BuildConfig.DEBUG_MODE) {
                SDKEnvironment.DEVELOPMENT
            } else {
                SDKEnvironment.PRODUCTION
            }
        Log.w("RunAnywhereApp", "🚀 SELECTED ENVIRONMENT: $environment (based on BuildConfig.DEBUG_MODE=${BuildConfig.DEBUG_MODE})")

        // Initialize platform context first
        AndroidPlatformContext.initialize(this@RunAnywhereApplication)

        // Try to initialize SDK - log failures but continue regardless
        try {
            if (environment == SDKEnvironment.DEVELOPMENT) {
                RunAnywhere.initialize(
                    apiKey = "dev",
                    baseURL = "localhost",
                    environment = SDKEnvironment.DEVELOPMENT,
                )
                Log.i("RunAnywhereApp", "✅ SDK initialized in DEVELOPMENT mode")
            } else {
                val apiKey = "talk_to_runanywhere_team"
                val baseURL = "talk_to_runanywhere_team"

                Log.w("RunAnywhereApp", "🔐 PRODUCTION INIT PARAMS:")
                Log.w("RunAnywhereApp", "   apiKey = [REDACTED]")
                Log.w("RunAnywhereApp", "   baseURL = $baseURL")
                Log.w("RunAnywhereApp", "   environment = PRODUCTION")

                RunAnywhere.initialize(
                    apiKey = apiKey,
                    baseURL = baseURL,
                    environment = SDKEnvironment.PRODUCTION,
                )
                Log.w("RunAnywhereApp", "✅ SDK initialized in PRODUCTION mode - analytics SHOULD be enabled")
            }
        } catch (e: Exception) {
            // Log the failure but continue
            Log.w("RunAnywhereApp", "⚠️ SDK initialization failed (backend may be unavailable): ${e.message}")
            initializationError = e

            // Fall back to development mode
            try {
                RunAnywhere.initialize(
                    apiKey = "offline",
                    baseURL = "localhost",
                    environment = SDKEnvironment.DEVELOPMENT,
                )
                Log.i("RunAnywhereApp", "✅ SDK initialized in OFFLINE mode (local models only)")
            } catch (fallbackError: Exception) {
                Log.e("RunAnywhereApp", "❌ Fallback initialization also failed: ${fallbackError.message}")
            }
        }

        // Register modules and models (matching iOS registerModulesAndModels pattern)
        registerModulesAndModels()
        Log.i("RunAnywhereApp", "✅ SDK initialization complete")

        val initTime = System.currentTimeMillis() - startTime
        Log.i("RunAnywhereApp", "✅ SDK setup completed in ${initTime}ms")
        Log.i("RunAnywhereApp", "🎯 SDK Status: Active=${RunAnywhere.isInitialized}")

        isSDKInitialized = RunAnywhere.isInitialized

        // Update observable state for Compose UI - matches iOS conditional rendering
        if (isSDKInitialized) {
            _initializationState.value = SDKInitializationState.Ready
            Log.i("RunAnywhereApp", "🎉 App is ready to use!")
        } else if (initializationError != null) {
            _initializationState.value = SDKInitializationState.Error(initializationError!!)
        } else {
            // SDK reported not initialized but no error - treat as ready for offline mode
            _initializationState.value = SDKInitializationState.Ready
            Log.i("RunAnywhereApp", "🎉 App is ready to use (offline mode)!")
        }
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
     * Retry SDK initialization - matches iOS retryInitialization() pattern
     */
    suspend fun retryInitialization() {
        _initializationState.value = SDKInitializationState.Loading
        withContext(Dispatchers.IO) {
            initializeSDK()
        }
    }

    /**
     * Register modules with their associated models
     * Each module explicitly owns its models - the framework is determined by the module
     * Matches iOS registerModulesAndModels() pattern exactly
     *
     * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift
     */
    private fun registerModulesAndModels() {
        Log.i("RunAnywhereApp", "📦 Registering modules with their models...")

        // LlamaCPP module with LLM models
        // Using explicit IDs ensures models are recognized after download across app restarts
        LlamaCPP.register()
        LlamaCPP.addModel(
            id = "smollm2-360m-q8_0",
            name = "SmolLM2 360M Q8_0",
            url = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
            memoryRequirement = 500_000_000L,
        )
        LlamaCPP.addModel(
            id = "llama-2-7b-chat-q4_k_m",
            name = "Llama 2 7B Chat Q4_K_M",
            url = "https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf",
            memoryRequirement = 4_000_000_000L,
        )
        LlamaCPP.addModel(
            id = "mistral-7b-instruct-q4_k_m",
            name = "Mistral 7B Instruct Q4_K_M",
            url = "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf",
            memoryRequirement = 4_000_000_000L,
        )
        LlamaCPP.addModel(
            id = "qwen2.5-0.5b-instruct-q6_k",
            name = "Qwen 2.5 0.5B Instruct Q6_K",
            url = "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
            memoryRequirement = 600_000_000L,
        )
        LlamaCPP.addModel(
            id = "lfm2-350m-q4_k_m",
            name = "LiquidAI LFM2 350M Q4_K_M",
            url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
            memoryRequirement = 250_000_000L,
        )
        LlamaCPP.addModel(
            id = "lfm2-350m-q8_0",
            name = "LiquidAI LFM2 350M Q8_0",
            url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
            memoryRequirement = 400_000_000L,
        )
        Log.i("RunAnywhereApp", "✅ LlamaCPP module registered with LLM models")

        // ONNX module with STT and TTS models
        // Using tar.gz format hosted on RunanywhereAI/sherpa-onnx for fast native extraction
        // Using explicit IDs ensures models are recognized after download across app restarts
        ONNX.register()

        // STT Models (Sherpa-ONNX Whisper)
        ONNX.addModel(
            id = "sherpa-onnx-whisper-tiny.en",
            name = "Sherpa Whisper Tiny (ONNX)",
            url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
            modality = ModelCategory.SPEECH_RECOGNITION,
            artifactType = ModelArtifactType.TarGzArchive(ModelArtifactType.ArchiveStructure.NESTED_DIRECTORY),
            memoryRequirement = 75_000_000L,
        )
        ONNX.addModel(
            id = "sherpa-onnx-whisper-small.en",
            name = "Sherpa Whisper Small (ONNX)",
            url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2",
            modality = ModelCategory.SPEECH_RECOGNITION,
            artifactType = ModelArtifactType.TarBz2Archive(ModelArtifactType.ArchiveStructure.NESTED_DIRECTORY),
            memoryRequirement = 250_000_000L,
        )

        // TTS Models (Piper VITS)
        ONNX.addModel(
            id = "vits-piper-en_US-lessac-medium",
            name = "Piper TTS (US English - Medium)",
            url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
            modality = ModelCategory.SPEECH_SYNTHESIS,
            artifactType = ModelArtifactType.TarGzArchive(ModelArtifactType.ArchiveStructure.NESTED_DIRECTORY),
            memoryRequirement = 65_000_000L,
        )
        ONNX.addModel(
            id = "vits-piper-en_GB-alba-medium",
            name = "Piper TTS (British English)",
            url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz",
            modality = ModelCategory.SPEECH_SYNTHESIS,
            artifactType = ModelArtifactType.TarGzArchive(ModelArtifactType.ArchiveStructure.NESTED_DIRECTORY),
            memoryRequirement = 65_000_000L,
        )
        Log.i("RunAnywhereApp", "✅ ONNX module registered with STT/TTS models")

        Log.i("RunAnywhereApp", "🎉 All modules and models registered")
    }
}
