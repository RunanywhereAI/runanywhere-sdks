package com.runanywhere.runanywhereai

import android.app.Application
import android.util.Log
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.public.extensions.addModelFromURL
import com.runanywhere.sdk.public.extensions.listAvailableModels
import com.runanywhere.sdk.public.extensions.loadModelWithInfo
import com.runanywhere.sdk.llm.llamacpp.LlamaCppServiceProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Application class for RunAnywhere AI sample app
 * Matches iOS RunAnywhereAIApp.swift initialization pattern
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
                    apiKey = "dev",  // Any string works in dev mode
                    baseURL = "localhost",  // Not used in dev mode
                    environment = SDKEnvironment.DEVELOPMENT
                )
                Log.i("RunAnywhereApp", "✅ SDK initialized in DEVELOPMENT mode")

                // STEP 1: Register Service Providers (matches iOS pattern)
                val providersRegistered = registerServiceProvidersForDevelopment()
                if (!providersRegistered) {
                    throw IllegalStateException("Failed to register service providers")
                }

                // STEP 2: Register models for development
                val modelsRegistered = registerModelsForDevelopment()
                if (!modelsRegistered) {
                    throw IllegalStateException("Failed to register models")
                }

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
     * Register Service Providers (matches iOS LLMSwiftServiceProvider.register())
     * This is Step 1 of the two-tier registration pattern:
     * 1. Register service providers with ModuleRegistry
     * 2. Register models with their framework associations
     */
    private fun registerServiceProvidersForDevelopment(): Boolean {
        Log.i("RunAnywhereApp", "🔧 Registering Service Providers for DEVELOPMENT mode")

        return try {
            // Register Llama.cpp service provider from SDK module
            LlamaCppServiceProvider.register()
            Log.i("RunAnywhereApp", "✅ Registered LlamaCppServiceProvider")

            // TODO: Register WhisperKit/STT provider when available
            // TODO: Register TTS provider when available

            Log.i("RunAnywhereApp", "🎉 All service providers registered successfully")
            true
        } catch (e: Exception) {
            Log.e("RunAnywhereApp", "❌ Failed to register service providers: ${e.message}")
            false
        }
    }

    /**
     * Register models for development mode (matches iOS registerAdaptersForDevelopment)
     * This is Step 2 - models are associated with frameworks via compatibleFrameworks field
     */
    private suspend fun registerModelsForDevelopment(): Boolean {
        Log.i("RunAnywhereApp", "📦 Registering models for DEVELOPMENT mode")

        return try {
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


            // Llama 3.2 1B - good quality
            addModelFromURL(
                url = "https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF/resolve/main/qwen2-0_5b-instruct-q4_0.gguf",
                name = "QWEN 2 0.5B Q4_0 Instruct",
                type = "LLM"
            )
            Log.i("RunAnywhereApp", "✅ Registered: QWEN 2 0.5B Instruct Q6_K Q4_0")

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

            // Scan file system for already downloaded models
            Log.i("RunAnywhereApp", "🔍 Scanning for previously downloaded models...")
            RunAnywhere.scanForDownloadedModels()
            Log.i("RunAnywhereApp", "✅ File system scan complete")

            // Note: In Kotlin SDK, we don't register STT/TTS adapters during app initialization
            // They are registered when needed by the SDK's service container
            // WhisperKit and other framework adapters are handled internally by the SDK

            true
        } catch (e: Exception) {
            Log.e("RunAnywhereApp", "❌ Failed to register models: ${e.message}")
            false
        }
    }

    /**
     * Retrieves API key from secure storage.
     * In production, this should:
     * 1. Read from Android EncryptedSharedPreferences or Keystore
     * 2. Or read from BuildConfig (populated from environment variables in CI/CD)
     * 3. Never hard-code the key in source code
     *
     * For development/demo purposes, we use BuildConfig which can be set via:
     * - gradle.properties (not committed to version control)
     * - Environment variables in CI/CD
     * - Or throw an error to force proper configuration
     */
    private fun getSecureApiKey(): String {
        // TODO: Implement secure API key retrieval before production deployment
        // Option 1: Read from EncryptedSharedPreferences
        // Option 2: Read from Android Keystore
        // Option 3: Read from BuildConfig (populated from environment variables)
        // Example: return BuildConfig.RUNANYWHERE_API_KEY

        // For now, return a placeholder to allow development/testing
        // WARNING: This must be replaced with actual secure key retrieval before production
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
