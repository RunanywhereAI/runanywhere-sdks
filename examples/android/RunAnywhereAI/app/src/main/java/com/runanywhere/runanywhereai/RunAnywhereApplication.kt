package com.runanywhere.runanywhereai

import android.app.Application
import android.util.Log
import com.runanywhere.runanywhereai.data.ModelList
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.SDKEnvironment
import com.runanywhere.sdk.storage.AndroidPlatformContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Observable SDK initialization state. */
sealed interface SDKInitState {
    data object Loading : SDKInitState
    data object Ready : SDKInitState
    data class Error(val message: String) : SDKInitState
}

class RunAnywhereApplication : Application() {

    companion object {
        private const val TAG = "RunAnywhereApp"
    }

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val _sdkState = MutableStateFlow<SDKInitState>(SDKInitState.Loading)
    val sdkState: StateFlow<SDKInitState> = _sdkState.asStateFlow()

    override fun onCreate() {
        super.onCreate()
        AndroidPlatformContext.initialize(this)
        appScope.launch(Dispatchers.IO) { initializeSDK() }
    }

    private suspend fun initializeSDK() {
        try {
            val environment = if (BuildConfig.DEBUG) {
                SDKEnvironment.DEVELOPMENT
            } else {
                SDKEnvironment.PRODUCTION
            }

            Log.i(TAG, "Initializing SDK in ${environment.name} mode...")

            // Phase 1: Fast synchronous init (config, native bridge)
            RunAnywhere.initialize(environment = environment)

            // Phase 2: Async services (device registration, telemetry)
            RunAnywhere.completeServicesInitialization()

            // Register all models and LoRA adapters
            ModelList.setupModels()

            Log.i(TAG, "SDK initialized successfully")
            _sdkState.value = SDKInitState.Ready
        } catch (e: Exception) {
            Log.e(TAG, "SDK initialization failed: ${e.message}", e)
            _sdkState.value = SDKInitState.Error(e.message ?: "Unknown error")
        }
    }

    /** Retry SDK initialization after a failure. */
    fun retryInitialization() {
        _sdkState.value = SDKInitState.Loading
        appScope.launch(Dispatchers.IO) { initializeSDK() }
    }
}
