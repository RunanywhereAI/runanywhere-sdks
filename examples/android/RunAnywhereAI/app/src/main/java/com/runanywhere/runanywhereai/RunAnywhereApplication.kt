package com.runanywhere.runanywhereai

import android.app.Application
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.public.RunAnywhere
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

        // Log adapter status (adapters are registered automatically by the SDK)
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
}
