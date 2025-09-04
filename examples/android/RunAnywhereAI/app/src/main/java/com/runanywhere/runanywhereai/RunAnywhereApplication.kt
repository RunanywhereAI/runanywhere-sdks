package com.runanywhere.runanywhereai

import android.app.Application
import android.util.Log
import androidx.lifecycle.lifecycleScope
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.files.FileManager
import dagger.hilt.android.HiltAndroidApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Application class for RunAnywhere AI sample app
 * Handles SDK initialization and global configuration
 */
@HiltAndroidApp
class RunAnywhereApplication : Application() {

    override fun onCreate() {
        super.onCreate()

        // Initialize FileManager with application context
        FileManager.initialize(applicationContext)

        // Initialize SDK with framework adapters
        initializeSDK()

        // Setup logging and analytics
        setupLogging()
    }

    private fun initializeSDK() {
        // Note: Using the current SDK interface - TODO: Replace with enhanced SDK when available
        try {
            // Initialize SDK in development mode
            RunAnywhere.initialize(
                apiKey = "dev-api-key",
                environment = SDKEnvironment.DEVELOPMENT
            )

            Log.i("RunAnywhereApp", "SDK initialized successfully")

        } catch (e: Exception) {
            Log.e("RunAnywhereApp", "Failed to initialize SDK", e)
            // Handle initialization failure gracefully
        }

        // TODO: When SDK is enhanced, use this configuration:
        /*
        lifecycleScope.launch(Dispatchers.IO) {
            try {
                RunAnywhereSDK.initialize(
                    context = this@RunAnywhereApplication,
                    config = SDKInitializationConfig(
                        frameworkAdapters = listOf(
                            WhisperCppAdapter(
                                modelPath = getWhisperModelPath(),
                                options = WhisperOptions(
                                    language = "auto",
                                    translate = false,
                                    enableVAD = true
                                )
                            ),
                            LlamaCppAdapter(
                                modelPath = getLlamaModelPath(),
                                options = LlamaOptions(
                                    contextSize = 2048,
                                    threads = Runtime.getRuntime().availableProcessors()
                                )
                            ),
                            VoiceActivityDetector(
                                sensitivity = VADSensitivity.MEDIUM,
                                minSpeechDuration = 250,
                                minSilenceDuration = 500
                            ),
                            SpeakerDiarizationAdapter(
                                threshold = 0.45f,
                                maxSpeakers = 8
                            )
                        ),
                        enableAnalytics = true,
                        enableCrashReporting = !BuildConfig.DEBUG,
                        logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.INFO
                    )
                )

                Log.i("RunAnywhereApp", "Enhanced SDK initialized successfully")

            } catch (e: Exception) {
                Log.e("RunAnywhereApp", "Failed to initialize enhanced SDK", e)
            }
        }
        */
    }

    private fun setupLogging() {
        if (BuildConfig.DEBUG_MODE) {
            // TODO: Enable verbose logging for development when SDK supports it
            // RunAnywhereSDK.setLogLevel(LogLevel.VERBOSE)
            Log.d("RunAnywhereApp", "Debug mode enabled")
        }
    }
}
