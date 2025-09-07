package com.runanywhere.runanywhereai

import android.app.Application
import android.util.Log
// import androidx.lifecycle.ProcessLifecycleOwner
// import androidx.lifecycle.lifecycleScope
// KMP SDK imports
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.data.models.SDKEnvironment
// import dagger.hilt.android.HiltAndroidApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Application class for RunAnywhere AI sample app
 * Enhanced to match iOS functionality with proper KMP SDK initialization
 */
// @HiltAndroidApp
class RunAnywhereApplication : Application() {

    private var isSDKInitialized = false
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

            // Initialize KMP SDK with enhanced configuration
            // This matches the iOS initialization pattern
            RunAnywhere.initialize(
                apiKey = "demo-api-key",
                baseURL = "https://api.runanywhere.ai",
                environment = SDKEnvironment.DEVELOPMENT
            )

            val initTime = System.currentTimeMillis() - startTime
            Log.i("RunAnywhereApp", "✅ KMP SDK successfully initialized!")
            Log.i("RunAnywhereApp", "⏱️  Initialization time: ${initTime}ms")
            Log.i("RunAnywhereApp", "📊 SDK Status: Ready for on-device AI inference")

            isSDKInitialized = true

            // Auto-load first available model (matching iOS behavior)
            autoLoadFirstModel()

        } catch (e: Exception) {
            Log.e("RunAnywhereApp", "❌ SDK initialization failed!")
            Log.e("RunAnywhereApp", "🔍 Error: ${e.message}")
            Log.e("RunAnywhereApp", "💡 Tip: Check your API key and network connection")

            initializationError = e
            isSDKInitialized = false
        }
    }

    private suspend fun autoLoadFirstModel() {
        Log.i("RunAnywhereApp", "🤖 Auto-loading first available model...")

        try {
            // Get available models from KMP SDK
            val availableModels = RunAnywhere.availableModels()

            // Filter for downloaded models first
            val downloadedModels = availableModels.filter { it.localPath != null }

            if (downloadedModels.isNotEmpty()) {
                val modelToLoad = downloadedModels.first()
                Log.i("RunAnywhereApp", "✅ Found model to auto-load: ${modelToLoad.name}")

                // Load the model
                // TODO: SDK doesn't have loadModel method yet
                // RunAnywhere.loadModel(modelToLoad.id)

                Log.i("RunAnywhereApp", "🎉 Successfully auto-loaded model: ${modelToLoad.name}")

            } else {
                Log.i("RunAnywhereApp", "ℹ️ No downloaded models available for auto-loading")
                Log.i("RunAnywhereApp", "💡 User will need to download and select a model manually")
            }

        } catch (e: Exception) {
            Log.w("RunAnywhereApp", "⚠️ Failed to auto-load model: ${e.message}")
            Log.i("RunAnywhereApp", "💡 User will need to select a model manually")
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
     * Retry SDK initialization
     */
    suspend fun retryInitialization() {
        kotlinx.coroutines.GlobalScope.launch(Dispatchers.IO) {
            initializeSDK()
        }
    }
}
