package ai.runanywhere.sdk

import android.os.Build
import android.util.Log
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
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
        private const val SDK_VERSION = "0.15.8"
        private const val COMMONS_VERSION = "0.1.4"

        init {
            // Installing the OkHttp transport is the one-time wire-up for the
            // RunAnywhere HTTP stack on Android. Routes `rac_http_request_*`
            // through OkHttp so consumers get the system CA trust store,
            // HTTP/2, proxies, and NetworkSecurityConfig instead of libcurl
            // (which was deleted in Stage 5). Idempotent on the C++ side.
            //
            // `RunAnywhereBridge`'s static initializer also runs
            // `System.loadLibrary("runanywhere_jni")`, which pulls in
            // `librac_commons.so` transitively.
            try {
                val rc = RunAnywhereBridge.racHttpTransportRegisterOkHttp()
                if (rc == 0) {
                    Log.i(TAG, "OkHttp HTTP transport registered")
                } else {
                    Log.w(TAG, "OkHttp HTTP transport registration returned rc=$rc")
                }
            } catch (t: Throwable) {
                // Link / load errors here indicate the bundled
                // librunanywhere_jni.so or librac_commons.so is missing or
                // predates rac_http_transport_register. The SDK can no
                // longer fall back to libcurl (Stage 5 deleted it), so HTTP
                // will error out until the native bundle is rebuilt.
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
