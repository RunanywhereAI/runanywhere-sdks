package com.runanywhere.runanywhereai

import android.app.Application
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.runanywhere.runanywhereai.config.AppModelRegistry
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.public.extensions.registerFramework
import com.runanywhere.sdk.llm.llamacpp.LlamaCppAdapter
import com.runanywhere.sdk.core.onnx.ONNXAdapter
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
 * Application class for RunAnywhere AI sample app
 * Matches iOS RunAnywhereAIApp.swift initialization pattern exactly.
 *
 * Uses strongly-typed enums for all framework and modality parameters:
 * - LLMFramework enum for framework specification
 * - FrameworkModality enum for modality specification
 * - ModelFormat enum for format specification
 * - ModelRegistration data class for model registration
 */
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
        fun getInstance(): RunAnywhereApplication =
            instance ?: throw IllegalStateException("Application not initialized")
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
        val environment = if (BuildConfig.DEBUG_MODE) {
            SDKEnvironment.DEVELOPMENT
        } else {
            SDKEnvironment.PRODUCTION
        }
        Log.w("RunAnywhereApp", "🚀 SELECTED ENVIRONMENT: $environment (based on BuildConfig.DEBUG_MODE=${BuildConfig.DEBUG_MODE})")

        // Try to initialize SDK - log failures but continue regardless
        try {
            if (environment == SDKEnvironment.DEVELOPMENT) {
                RunAnywhere.initialize(
                    context = this@RunAnywhereApplication,
                    apiKey = "dev",
                    baseURL = "localhost",
                    environment = SDKEnvironment.DEVELOPMENT
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
                    context = this@RunAnywhereApplication,
                    apiKey = apiKey,
                    baseURL = baseURL,
                    environment = SDKEnvironment.PRODUCTION
                )
                Log.w("RunAnywhereApp", "✅ SDK initialized in PRODUCTION mode - analytics SHOULD be enabled")
            }
        } catch (e: Exception) {
            // Log the failure but continue - we'll still register adapters for local model usage
            Log.w("RunAnywhereApp", "⚠️ SDK initialization failed (backend may be unavailable): ${e.message}")
            initializationError = e

            // Fall back to development mode so adapters can still be registered
            try {
                RunAnywhere.initialize(
                    context = this@RunAnywhereApplication,
                    apiKey = "offline",
                    baseURL = "localhost",
                    environment = SDKEnvironment.DEVELOPMENT
                )
                Log.i("RunAnywhereApp", "✅ SDK initialized in OFFLINE mode (local models only)")
            } catch (fallbackError: Exception) {
                Log.e("RunAnywhereApp", "❌ Fallback initialization also failed: ${fallbackError.message}")
            }
        }

        // ALWAYS register adapters regardless of initialization success
        // This ensures local models are available even when backend is down
        try {
            if (BuildConfig.DEBUG_MODE) {
                registerAdaptersForDevelopment()
            } else {
                registerAdaptersForProduction()
            }
            Log.i("RunAnywhereApp", "✅ Adapters registered successfully")
        } catch (e: Exception) {
            Log.e("RunAnywhereApp", "❌ Failed to register adapters: ${e.message}", e)
        }

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
     * Register framework adapters with models.
     *
     * Uses the same hardcoded models for both DEVELOPMENT and PRODUCTION modes
     * to ensure consistent user experience across environments.
     *
     * Matches iOS RunAnywhereAIApp.swift registerAdaptersForDevelopment/Production() pattern exactly.
     *
     * All parameters use strongly-typed enums:
     * - LLMFramework.LLAMA_CPP, LLMFramework.ONNX
     * - FrameworkModality.TEXT_TO_TEXT, VOICE_TO_TEXT, TEXT_TO_VOICE
     * - ModelFormat.GGUF, ModelFormat.ONNX
     *
     * @param mode The environment mode (DEVELOPMENT or PRODUCTION)
     */
    private suspend fun registerAdapters(mode: String) {
        require(mode in setOf("DEVELOPMENT", "PRODUCTION")) { "Invalid mode: $mode" }

        Log.i("RunAnywhereApp", "📦 Registering adapters with custom models for $mode mode")

        if (mode == "PRODUCTION") {
            Log.i("RunAnywhereApp", "💡 Hardcoded models provide immediate user access, backend can add more dynamically")
        }

        // =====================================================
        // 1. LlamaCPP Framework (TEXT_TO_TEXT modality)
        // Matches iOS: RunAnywhere.registerFramework(LlamaCPPCoreAdapter(), models: [...])
        // This provides native C++ llama.cpp performance
        // Models are the same across Dev/Prod for consistent user experience
        // =====================================================
        Log.i("RunAnywhereApp", "📝 Registering LlamaCPP adapter with LLM models...")

        RunAnywhere.registerFramework(
            adapter = LlamaCppAdapter.shared,
            models = AppModelRegistry.getLlamaCppModels()
        )
        Log.i("RunAnywhereApp", "✅ LlamaCPP adapter registered")

        // =====================================================
        // 2. ONNX Runtime Framework (VOICE_TO_TEXT, TEXT_TO_VOICE modalities)
        // Matches iOS: RunAnywhere.registerFramework(ONNXAdapter.shared, models: [...])
        // Note: WhisperKit models are iOS-only (CoreML), we use ONNX Sherpa models on Android
        // Models are the same across Dev/Prod for consistent user experience
        // =====================================================
        Log.i("RunAnywhereApp", "🎤🔊 Registering ONNX adapter with STT and TTS models...")

        RunAnywhere.registerFramework(
            adapter = ONNXAdapter.shared,
            models = AppModelRegistry.getOnnxModels()
        )
        Log.i("RunAnywhereApp", "✅ ONNX adapter registered (includes STT and TTS providers)")

        // Note: WhisperKit is iOS-only (uses CoreML), ONNX Sherpa serves the same purpose on Android
        // Note: FluidAudioDiarization is iOS-only, can be added when Android module is available
        // Note: FoundationModels requires iOS 26+ / macOS 26+, not applicable to Android

        // Scan file system for already downloaded models
        // This allows models downloaded previously to be discovered
        Log.i("RunAnywhereApp", "🔍 Scanning for previously downloaded models...")
        RunAnywhere.scanForDownloadedModels()
        Log.i("RunAnywhereApp", "✅ File system scan complete")

        Log.i("RunAnywhereApp", "🎉 All adapters registered for $mode")

        if (mode == "PRODUCTION") {
            Log.i("RunAnywhereApp", "📡 Backend can dynamically add more models via console API")
        }
    }

    /**
     * Register framework adapters with models for DEVELOPMENT mode.
     * Delegates to registerAdapters() with mode parameter.
     */
    private suspend fun registerAdaptersForDevelopment() = registerAdapters("DEVELOPMENT")

    /**
     * Register framework adapters with models for PRODUCTION mode.
     * Delegates to registerAdapters() with mode parameter.
     */
    private suspend fun registerAdaptersForProduction() = registerAdapters("PRODUCTION")

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
     * Retry SDK initialization - matches iOS retryInitialization() pattern
     */
    suspend fun retryInitialization() {
        _initializationState.value = SDKInitializationState.Loading
        withContext(Dispatchers.IO) {
            initializeSDK()
        }
    }
}
