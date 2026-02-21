package com.runanywhere.run_anywhere_lora

import android.app.Application
import android.util.Log
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.SDKEnvironment
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

sealed class SDKInitState {
    data object Loading : SDKInitState()
    data object Ready : SDKInitState()
    data class Error(val error: Throwable) : SDKInitState()
}

class LoraApplication : Application() {

    companion object {
        private const val TAG = "LoraApp"
    }

    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val _initializationState = MutableStateFlow<SDKInitState>(SDKInitState.Loading)
    val initializationState: StateFlow<SDKInitState> = _initializationState.asStateFlow()

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "App launched, initializing SDK...")
        applicationScope.launch(Dispatchers.IO) {
            delay(200)
            initializeSDK()
        }
    }

    override fun onTerminate() {
        applicationScope.cancel()
        super.onTerminate()
    }

    private suspend fun initializeSDK() {
        try {
            AndroidPlatformContext.initialize(this@LoraApplication)

            RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)
            Log.i(TAG, "SDK initialized in DEVELOPMENT mode")

            kotlinx.coroutines.runBlocking {
                RunAnywhere.completeServicesInitialization()
            }
            Log.i(TAG, "SDK services initialization complete")

            LlamaCPP.register(priority = 100)
            Log.i(TAG, "LlamaCPP backend registered")

            _initializationState.value = SDKInitState.Ready
            Log.i(TAG, "SDK ready")
        } catch (e: Exception) {
            Log.e(TAG, "SDK initialization failed: ${e.message}", e)
            _initializationState.value = SDKInitState.Error(e)
        }
    }
}
