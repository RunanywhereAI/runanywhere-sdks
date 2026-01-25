package com.runanywhere.runanywhereai

import android.app.Application
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.runanywhere.runanywhereai.presentation.settings.SettingsViewModel
import com.runanywhere.sdk.core.onnx.ONNX
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.SDKEnvironment
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.registerModel
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

        // Check for custom API configuration (stored via Settings screen)
        val customApiKey = SettingsViewModel.getStoredApiKey(this@RunAnywhereApplication)
        val customBaseURL = SettingsViewModel.getStoredBaseURL(this@RunAnywhereApplication)
        val hasCustomConfig = customApiKey != null && customBaseURL != null

        if (hasCustomConfig) {
            Log.i("RunAnywhereApp", "🔧 Found custom API configuration")
            Log.i("RunAnywhereApp", "   Base URL: $customBaseURL")
        }

        // Determine environment based on DEBUG_MODE (NOT BuildConfig.DEBUG!)
        // BuildConfig.DEBUG is tied to isDebuggable flag, which we set to true for release builds
        // to allow logging. BuildConfig.DEBUG_MODE correctly reflects debug vs release build type.
        val defaultEnvironment =
            if (BuildConfig.DEBUG_MODE) {
                SDKEnvironment.DEVELOPMENT
            } else {
                SDKEnvironment.PRODUCTION
            }

        // If custom config is set, use production environment to enable the custom backend
        val environment = if (hasCustomConfig) SDKEnvironment.PRODUCTION else defaultEnvironment

        // Initialize platform context first
        AndroidPlatformContext.initialize(this@RunAnywhereApplication)

        // Try to initialize SDK - log failures but continue regardless
        try {
            if (hasCustomConfig) {
                // Custom configuration mode - use stored API key and base URL
                RunAnywhere.initialize(
                    apiKey = customApiKey!!,
                    baseURL = customBaseURL!!,
                    environment = environment,
                )
                Log.i("RunAnywhereApp", "✅ SDK initialized with CUSTOM configuration (${environment.name.lowercase()})")
            } else if (environment == SDKEnvironment.DEVELOPMENT) {
                // DEVELOPMENT mode: Don't pass baseURL - SDK uses Supabase URL from C++ dev config
                RunAnywhere.initialize(
                    environment = SDKEnvironment.DEVELOPMENT,
                )
                Log.i("RunAnywhereApp", "✅ SDK initialized in DEVELOPMENT mode (using Supabase from dev config)")
            } else {
                // PRODUCTION mode - requires API key and base URL
                // Configure these via Settings screen or set environment variables
                val apiKey = "YOUR_API_KEY_HERE"
                val baseURL = "YOUR_BASE_URL_HERE"

                // Detect placeholder credentials and abort production initialization
                if (apiKey.startsWith("YOUR_") || baseURL.startsWith("YOUR_")) {
                    Log.e(
                        "RunAnywhereApp",
                        "❌ RunAnywhere.initialize with SDKEnvironment.PRODUCTION failed: " +
                            "placeholder credentials detected. Configure via Settings screen or replace placeholders.",
                    )
                    // Fall back to development mode
                    RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)
                    Log.i("RunAnywhereApp", "✅ SDK initialized in DEVELOPMENT mode (production credentials not configured)")
                } else {
                    RunAnywhere.initialize(
                        apiKey = apiKey,
                        baseURL = baseURL,
                        environment = SDKEnvironment.PRODUCTION,
                    )
                    Log.i("RunAnywhereApp", "✅ SDK initialized in PRODUCTION mode")
                }
            }

            // Phase 2: Complete services initialization (device registration, etc.)
            // This triggers device registration with the backend
            kotlinx.coroutines.runBlocking {
                RunAnywhere.completeServicesInitialization()
            }
            Log.i("RunAnywhereApp", "✅ SDK services initialization complete (device registered)")
        } catch (e: Exception) {
            // Log the failure but continue
            Log.w("RunAnywhereApp", "⚠️ SDK initialization failed (backend may be unavailable): ${e.message}")
            initializationError = e

            // Fall back to development mode
            try {
                // Don't pass baseURL - SDK uses Supabase URL from C++ dev config
                RunAnywhere.initialize(
                    environment = SDKEnvironment.DEVELOPMENT,
                )
                Log.i("RunAnywhereApp", "✅ SDK initialized in OFFLINE mode (local models only)")

                // Still try Phase 2 in offline mode
                kotlinx.coroutines.runBlocking {
                    RunAnywhere.completeServicesInitialization()
                }
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
     * Register modules with their associated models.
     * Each module explicitly owns its models - the framework is determined by the module.
     *
     * Mirrors iOS RunAnywhereAIApp.registerModulesAndModels() exactly.
     *
     * Backend registration MUST happen before model registration.
     * This follows the same pattern as iOS where backends are registered first.
     */
    @Suppress("LongMethod")
    private fun registerModulesAndModels() {
        Log.i("RunAnywhereApp", "📦 Registering backends and models...")

        // Register backends first (matching iOS pattern)
        // These call the C++ rac_backend_xxx_register() functions via JNI
        Log.i("RunAnywhereApp", "🔧 Registering LlamaCPP backend...")
        LlamaCPP.register(priority = 100)

        Log.i("RunAnywhereApp", "🔧 Registering ONNX backend...")
        ONNX.register(priority = 100)

        Log.i("RunAnywhereApp", "✅ Backends registered, now registering models...")

        // Register LLM models using the new RunAnywhere.registerModel API
        // Using explicit IDs ensures models are recognized after download across app restarts
        RunAnywhere.registerModel(
            id = "smollm2-360m-q8_0",
            name = "SmolLM2 360M Q8_0",
            url = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
            framework = InferenceFramework.LLAMA_CPP,
            memoryRequirement = 500_000_000,
        )
        RunAnywhere.registerModel(
            id = "llama-2-7b-chat-q4_k_m",
            name = "Llama 2 7B Chat Q4_K_M",
            url = "https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf",
            framework = InferenceFramework.LLAMA_CPP,
            memoryRequirement = 4_000_000_000,
        )
        RunAnywhere.registerModel(
            id = "mistral-7b-instruct-q4_k_m",
            name = "Mistral 7B Instruct Q4_K_M",
            url = "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf",
            framework = InferenceFramework.LLAMA_CPP,
            memoryRequirement = 4_000_000_000,
        )
        RunAnywhere.registerModel(
            id = "qwen2.5-0.5b-instruct-q6_k",
            name = "Qwen 2.5 0.5B Instruct Q6_K",
            url = "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
            framework = InferenceFramework.LLAMA_CPP,
            memoryRequirement = 600_000_000,
        )
        RunAnywhere.registerModel(
            id = "lfm2-350m-q4_k_m",
            name = "LiquidAI LFM2 350M Q4_K_M",
            url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
            framework = InferenceFramework.LLAMA_CPP,
            memoryRequirement = 250_000_000,
        )
        RunAnywhere.registerModel(
            id = "lfm2-350m-q8_0",
            name = "LiquidAI LFM2 350M Q8_0",
            url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
            framework = InferenceFramework.LLAMA_CPP,
            memoryRequirement = 400_000_000,
        )
        Log.i("RunAnywhereApp", "✅ LLM models registered")

        // Register ONNX STT and TTS models
        // Using tar.gz format hosted on RunanywhereAI/sherpa-onnx for fast native extraction
        RunAnywhere.registerModel(
            id = "sherpa-onnx-whisper-tiny.en",
            name = "Sherpa Whisper Tiny (ONNX)",
            url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
            framework = InferenceFramework.ONNX,
            modality = ModelCategory.SPEECH_RECOGNITION,
            memoryRequirement = 75_000_000,
        )
        RunAnywhere.registerModel(
            id = "vits-piper-en_US-lessac-medium",
            name = "Piper TTS (US English - Medium)",
            url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
            framework = InferenceFramework.ONNX,
            modality = ModelCategory.SPEECH_SYNTHESIS,
            memoryRequirement = 65_000_000,
        )
        RunAnywhere.registerModel(
            id = "vits-piper-en_GB-alba-medium",
            name = "Piper TTS (British English)",
            url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz",
            framework = InferenceFramework.ONNX,
            modality = ModelCategory.SPEECH_SYNTHESIS,
            memoryRequirement = 65_000_000,
        )
        Log.i("RunAnywhereApp", "✅ ONNX STT/TTS models registered")

        Log.i("RunAnywhereApp", "🎉 All modules and models registered")
    }
}
