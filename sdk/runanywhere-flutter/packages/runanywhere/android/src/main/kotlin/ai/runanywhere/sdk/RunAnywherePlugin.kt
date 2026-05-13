package ai.runanywhere.sdk

import android.os.Build
import android.util.Log
import com.runanywhere.sdk.httptransport.OkHttpHttpTransport
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * RunAnywhere Flutter Plugin - Android Implementation
 *
 * This plugin provides the native bridge for the RunAnywhere SDK on Android.
 * The actual AI functionality is provided by RACommons native libraries (.so files).
 */
class RunAnywherePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    companion object {
        private const val TAG = "RunAnywherePlugin"
        private const val CHANNEL_NAME = "runanywhere"
        private const val SDK_VERSION = "0.19.13"
        private const val COMMONS_VERSION = "0.19.13"

        init {
            // Install the OkHttp transport via the canonical Kotlin-SDK-aligned
            // adapter at `com.runanywhere.sdk.httptransport.OkHttpHttpTransport`.
            // The JNI shim (sdk/runanywhere-commons/src/jni/okhttp_transport_adapter.cpp:557)
            // does FindClass against that exact FQN — if this fails with
            // ClassNotFound, every rac_http_request_* call returns -801.
            //
            // `OkHttpHttpTransport.register()` is idempotent and matches the
            // Swift `URLSessionHttpTransport.register()` contract.
            //
            // `RunAnywhereBridge`'s static initializer also runs
            // `System.loadLibrary("runanywhere_jni")`, which pulls in
            // `librac_commons.so` transitively.
            try {
                val ok = OkHttpHttpTransport.register()
                if (!ok) {
                    Log.w(TAG, "OkHttp HTTP transport registration failed; HTTP will error out")
                }
            } catch (t: Throwable) {
                Log.e(TAG, "OkHttp HTTP transport unavailable: ${t.message}", t)
            }
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${Build.VERSION.RELEASE}")
            }
            "getSDKVersion" -> {
                result.success(SDK_VERSION)
            }
            "getCommonsVersion" -> {
                result.success(COMMONS_VERSION)
            }
            "getSocModel" -> {
                result.success(getSocModel())
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    /**
     * Get the SoC model string for NPU chip detection.
     * Uses Build.SOC_MODEL (API 31+) with Build.HARDWARE fallback.
     */
    private fun getSocModel(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val socModel = Build.SOC_MODEL
            if (!socModel.isNullOrEmpty() && socModel != "unknown") {
                return socModel
            }
        }
        return Build.HARDWARE ?: ""
    }
}
