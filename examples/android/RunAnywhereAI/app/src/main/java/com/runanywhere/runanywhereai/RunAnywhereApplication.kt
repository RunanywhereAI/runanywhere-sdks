package com.runanywhere.runanywhereai

import android.app.Application
import android.util.Log
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.public.extensions.addModelFromURL
import com.runanywhere.sdk.public.extensions.listAvailableModels
import com.runanywhere.sdk.public.extensions.loadModelWithInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Application class for RunAnywhere AI sample app
 * Matches iOS RunAnywhereAIApp.swift initialization pattern
 */
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
                    apiKey = "dev",  // Any string works in dev mode
                    baseURL = "localhost",  // Not used in dev mode
                    environment = SDKEnvironment.DEVELOPMENT
                )
                Log.i("RunAnywhereApp", "✅ SDK initialized in DEVELOPMENT mode")

                // Register models for development (matches iOS pattern)
                registerModelsForDevelopment()

            } else {
                // Production Mode - Real API key required
                val apiKey = "testing_api_key"  // TODO: Get from secure storage
                val baseURL = "https://api.runanywhere.ai"

                RunAnywhere.initialize(
                    context = this@RunAnywhereApplication,
                    apiKey = apiKey,
                    baseURL = baseURL,
                    environment = SDKEnvironment.PRODUCTION
                )
                Log.i("RunAnywhereApp", "✅ SDK initialized in PRODUCTION mode")

                // In production, models come from backend console
                Log.i("RunAnywhereApp", "📡 Models will be fetched from backend console via API")
            }

            val initTime = System.currentTimeMillis() - startTime
            Log.i("RunAnywhereApp", "✅ SDK successfully initialized!")
            Log.i("RunAnywhereApp", "⏱️  Initialization time: ${initTime}ms")
            Log.i("RunAnywhereApp", "🎯 SDK Status: Active=${RunAnywhere.isInitialized}")
            Log.i("RunAnywhereApp", "🔧 Environment: ${environment.name}")
            Log.i(
                "RunAnywhereApp",
                "📱 Device registration: Will happen on first API call (lazy loading)"
            )
            Log.i(
                "RunAnywhereApp",
                "🚀 Ready for on-device AI inference with lazy device registration!"
            )

            isSDKInitialized = true

            // Note: Models registered, user can now download and select models
            Log.i("RunAnywhereApp", "💡 Models registered, user can now download and select models")

        } catch (e: Exception) {
            Log.e("RunAnywhereApp", "❌ SDK initialization failed!")
            Log.e("RunAnywhereApp", "🔍 Error: ${e.message}")
            Log.e("RunAnywhereApp", "💡 Tip: Check your API key and network connection")

            initializationError = e
            isSDKInitialized = false
        }
    }

    /**
     * Register models for development mode (matches iOS registerAdaptersForDevelopment)
     * In Kotlin SDK, we don't have framework adapters, so we directly register models
     */
    private suspend fun registerModelsForDevelopment() {
        Log.i("RunAnywhereApp", "📦 Registering models for DEVELOPMENT mode")

        try {
            // Register LLM models (matches iOS LLMSwift models)
            // Note: In Kotlin SDK, addModelFromURL automatically registers the model

            // SmolLM2 360M - smallest and fastest
            addModelFromURL(
                url = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
                name = "SmolLM2 360M Q8_0",
                type = "LLM"
            )
            Log.i("RunAnywhereApp", "✅ Registered: SmolLM2 360M Q8_0")

            // Qwen 2.5 0.5B - small but capable
            addModelFromURL(
                url = "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
                name = "Qwen 2.5 0.5B Instruct Q6_K",
                type = "LLM"
            )
            Log.i("RunAnywhereApp", "✅ Registered: Qwen 2.5 0.5B Instruct Q6_K")

            // Llama 3.2 1B - good quality
            addModelFromURL(
                url = "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K.gguf",
                name = "Llama 3.2 1B Instruct Q6_K",
                type = "LLM"
            )
            Log.i("RunAnywhereApp", "✅ Registered: Llama 3.2 1B Instruct Q6_K")

            // SmolLM2 1.7B - larger but capable
            addModelFromURL(
                url = "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q6_K_L.gguf",
                name = "SmolLM2 1.7B Instruct Q6_K_L",
                type = "LLM"
            )
            Log.i("RunAnywhereApp", "✅ Registered: SmolLM2 1.7B Instruct Q6_K_L")

            // Qwen 2.5 1.5B - good for longer context
            addModelFromURL(
                url = "https://huggingface.co/ZeroWw/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct.q6_k.gguf",
                name = "Qwen 2.5 1.5B Instruct Q6_K",
                type = "LLM"
            )
            Log.i("RunAnywhereApp", "✅ Registered: Qwen 2.5 1.5B Instruct Q6_K")

            // LiquidAI LFM2 350M Q4_K_M - smallest and fastest
            addModelFromURL(
                url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
                name = "LiquidAI LFM2 350M Q4_K_M",
                type = "LLM"
            )
            Log.i("RunAnywhereApp", "✅ Registered: LiquidAI LFM2 350M Q4_K_M")

            // LiquidAI LFM2 350M Q8_0 - highest quality
            addModelFromURL(
                url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
                name = "LiquidAI LFM2 350M Q8_0",
                type = "LLM"
            )
            Log.i("RunAnywhereApp", "✅ Registered: LiquidAI LFM2 350M Q8_0")

            Log.i(
                "RunAnywhereApp",
                "🎉 All models registered for development (lazy loading enabled)"
            )

            // Note: In Kotlin SDK, we don't register STT/TTS adapters during app initialization
            // They are registered when needed by the SDK's service container
            // WhisperKit and other framework adapters are handled internally by the SDK

        } catch (e: Exception) {
            Log.e("RunAnywhereApp", "❌ Failed to register models: ${e.message}")
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
