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
import com.runanywhere.sdk.foundation.security.AndroidPlatformContext
import com.runanywhere.sdk.hybrid.AndroidDeviceStateProvider
import com.runanywhere.sdk.hybrid.HybridDeviceState
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.setDebugMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

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
            setupSDK()
        }
    }

    private suspend fun setupSDK() {
        RACLog.i("RAC SDK Setup initialization... Recording Time")
        val startTime = System.currentTimeMillis()

        //Starting Setup Work
        AndroidPlatformContext.initialize(this@RunAnywhereApplication)
        RunAnywhere.initialize(
            apiKey = BuildConfig.RUNANYWHERE_API_KEY,
            baseURL = BuildConfig.RUNANYWHERE_BASE_URL,
            environment = SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
        )
        // Production env disables SDK console logging entirely; without this
        // debug builds emit zero SDK logs to logcat, which makes on-device
        // issues (voice/STT/VLM) undiagnosable.
        if (BuildConfig.DEBUG) RunAnywhere.setDebugMode(true)
        HybridDeviceState.setProvider(AndroidDeviceStateProvider(applicationContext))
        ModelBootstrap.setupModels()
        CloudProviderRepository.registerAll()
        BuiltInTools.register(applicationContext)
        GlobalState.markReady()
        val initTime = System.currentTimeMillis() - startTime
        RACLog.i("SDK setup completed in ${initTime}ms")
    }
}