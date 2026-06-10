package com.runanywhere.runanywhereai

import ai.runanywhere.proto.v1.SDKEnvironment
import android.app.Application
import com.runanywhere.runanywhereai.data.ModelBootstrap
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkStore
import com.runanywhere.runanywhereai.data.cloud.CloudProviderRepository
import com.runanywhere.runanywhereai.data.conversation.ConversationRepository
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.tools.BuiltInTools
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.core.onnx.ONNX
import com.runanywhere.sdk.foundation.security.AndroidPlatformContext
import com.runanywhere.sdk.hybrid.AndroidDeviceStateProvider
import com.runanywhere.sdk.hybrid.HybridDeviceState
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

class RunAnywhereApplication : Application() {

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()

        GlobalState.warmUp()
        ConversationRepository.initialize(applicationContext)
        SettingsRepository.initialize(applicationContext)
        CloudProviderRepository.initialize(applicationContext)
        BenchmarkStore.initialize(applicationContext)
        appScope.launch(Dispatchers.IO) {
            ConversationRepository.refresh()
            runSdkSetup()
        }
    }

    fun retrySdkSetup() {
        GlobalState.clearInitError()
        appScope.launch(Dispatchers.IO) {
            runSdkSetup()
        }
    }

    private suspend fun runSdkSetup() {
        try {
            setupSDK()
            GlobalState.markReady()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            RACLog.e("SDK setup failed", e)
            GlobalState.markInitFailed(e.message ?: e.javaClass.simpleName)
        }
    }

    private suspend fun setupSDK() {
        RACLog.i("RAC SDK Setup initialization... Recording Time")
        val startTime = System.currentTimeMillis()

        //Starting Setup Work
        AndroidPlatformContext.initialize(this@RunAnywhereApplication)
        // Register backends with the C++ registry BEFORE initialize(): once initialize() runs,
        // a concurrent caller can hit loadModel() while only the platform backend is registered
        // and fail with -422 "No provider could handle the request" (same ordering as iOS).
        LlamaCPP.register()
        ONNX.register()
        RunAnywhere.initialize(environment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT)
        HybridDeviceState.setProvider(AndroidDeviceStateProvider(applicationContext))
        ModelBootstrap.setupModels()
        CloudProviderRepository.registerAll()
        BuiltInTools.register(applicationContext)
        val initTime = System.currentTimeMillis() - startTime
        RACLog.i("SDK setup completed in ${initTime}ms")
    }
}