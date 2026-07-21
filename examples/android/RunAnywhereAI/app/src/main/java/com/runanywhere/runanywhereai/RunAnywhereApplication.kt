package com.runanywhere.runanywhereai

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.SDKEnvironment
import android.app.Application
import com.runanywhere.runanywhereai.data.BackendAvailability
import com.runanywhere.runanywhereai.data.ModelBootstrap
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkStore
import com.runanywhere.runanywhereai.data.cloud.CloudProviderRepository
import com.runanywhere.runanywhereai.data.conversation.ConversationRepository
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.tools.BuiltInTools
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.runanywhereai.util.RACLogTelemetry
import com.runanywhere.sdk.core.onnx.ONNX
import com.runanywhere.sdk.hybrid.AndroidDeviceStateProvider
import com.runanywhere.sdk.hybrid.HybridDeviceState
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.npu.qhexrt.QHexRT
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.setDebugMode
import com.runanywhere.sdk.public.extensions.setLocalLoggingEnabled
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.cancellation.CancellationException

class RunAnywhereApplication : Application() {

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val setupInProgress = AtomicBoolean(false)

    override fun onCreate() {
        super.onCreate()

        RACLogTelemetry.install()
        GlobalState.warmUp()
        ConversationRepository.initialize(applicationContext)
        SettingsRepository.initialize(applicationContext)
        CloudProviderRepository.initialize(applicationContext)
        BenchmarkStore.initialize(applicationContext)
        appScope.launch(Dispatchers.IO) { ConversationRepository.refresh() }
        // Match iOS startup: initialize immediately with the full diagnostics
        // tier when a production control-plane configuration is available.
        appScope.launch(Dispatchers.IO) { runSdkSetup() }
    }

    fun retrySdkSetup() {
        GlobalState.clearInitError()
        appScope.launch(Dispatchers.IO) {
            runSdkSetup()
        }
    }

    private suspend fun runSdkSetup() {
        if (GlobalState.ready || !setupInProgress.compareAndSet(false, true)) return
        try {
            setupSDK()
            GlobalState.markReady()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            RACLog.e("SDK setup failed", e)
            GlobalState.markInitFailed(e.message ?: e.javaClass.simpleName)
        } finally {
            setupInProgress.set(false)
        }
    }

    private suspend fun setupSDK() {
        RACLog.i("RAC SDK Setup initialization... Recording Time")
        val startTime = System.currentTimeMillis()

        // Note: ADSP_LIBRARY_PATH (Hexagon DSP skel discovery for QHexRT/QNN) is set
        // automatically by the engine before its first runtime create — no app glue needed.
        // Register the CPU backends with the C++ registry before initialize(): once initialize()
        // runs, a concurrent caller can hit loadModel() while only the platform backend is
        // registered and fail with -422 "No provider could handle the request" (same ordering
        // as iOS). QHexRT is registered below because its skel installer needs the application
        // Context installed by the public RunAnywhere.initialize(context = ...) overload.
        // Optional CPU/ONNX backends: tolerate a missing native lib (e.g. an NPU-only build) so SDK
        // setup doesn't abort, and report availability so the model pickers hide rows whose backend
        // can't serve (BackendAvailability / A10). QHexRT is proven separately via its device probe.
        try {
            LlamaCPP.register()
            BackendAvailability.reportRegistration(InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP, true)
        } catch (t: Throwable) {
            RACLog.w("LlamaCPP backend unavailable (native lib absent); continuing without CPU backend", t)
            BackendAvailability.reportRegistration(InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP, false)
        }
        try {
            ONNX.register()
            BackendAvailability.reportRegistration(InferenceFramework.INFERENCE_FRAMEWORK_ONNX, true)
            BackendAvailability.reportRegistration(InferenceFramework.INFERENCE_FRAMEWORK_SHERPA, true)
        } catch (t: Throwable) {
            RACLog.w("ONNX/Sherpa backend unavailable (native lib absent); continuing without ONNX/ASR backend", t)
            BackendAvailability.reportRegistration(InferenceFramework.INFERENCE_FRAMEWORK_ONNX, false)
            BackendAvailability.reportRegistration(InferenceFramework.INFERENCE_FRAMEWORK_SHERPA, false)
        }
        val hasBackendConfig =
            BuildConfig.RUNANYWHERE_API_KEY.isNotBlank() &&
                BuildConfig.RUNANYWHERE_BASE_URL.isNotBlank()
        val environment = if (hasBackendConfig) {
            SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION
        } else {
            SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT
        }
        RunAnywhere.initialize(
            context = this@RunAnywhereApplication,
            apiKey = BuildConfig.RUNANYWHERE_API_KEY.takeIf {
                environment == SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION
            },
            baseURL = BuildConfig.RUNANYWHERE_BASE_URL.takeIf {
                environment == SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION
            },
            // Configured app builds always use the full production diagnostics tier.
            // Unconfigured local builds retain the SDK development fallback.
            environment = environment,
        )
        // QHexRT (Qualcomm Hexagon NPU). Registration is rejected internally on parts outside
        // the device-validated V75/V79/V81 set. RunAnywhere initialization must happen first so
        // the module can extract its DSP skels through the SDK-owned application Context.
        QHexRT.register()
        RACLogTelemetry.markSDKInitialized()
        // Production env disables SDK console logging entirely; without this
        // debug builds emit zero SDK logs to logcat, which makes on-device
        // issues (voice/STT/VLM) undiagnosable.
        if (BuildConfig.DEBUG) {
            RunAnywhere.setDebugMode(true)
        } else {
            // Release diagnostics are sent through the configured control
            // plane; user/device metadata must not also be written to logcat.
            RunAnywhere.setLocalLoggingEnabled(false)
        }
        HybridDeviceState.setProvider(AndroidDeviceStateProvider(applicationContext))
        // Re-apply the persisted HuggingFace token (Settings screen) so private
        // model repos (e.g. gated NPU bundles) download across app restarts. Falls back to
        // BuildConfig.HF_TOKEN (from gitignored local.properties `hf.token`) for local testing.
        (SettingsRepository.settings.hfToken.takeIf { it.isNotBlank() }
            ?: BuildConfig.HF_TOKEN.takeIf { it.isNotBlank() })?.let { RunAnywhere.setHfToken(it) }
        ModelBootstrap.setupModels()
        CloudProviderRepository.registerAll()
        BuiltInTools.register(applicationContext)
        val initTime = System.currentTimeMillis() - startTime
        RACLog.i("SDK setup completed in ${initTime}ms")
    }
}
