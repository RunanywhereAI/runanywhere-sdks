package ai.runanywhere.sdk.genie

import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * RunAnywhere Genie Flutter Plugin - Android Implementation
 *
 * This experimental plugin provides the native shell bridge for Genie on Android.
 * Functional LLM routing is disabled by default and requires RABackendGenie
 * native ops built with the Qualcomm Genie SDK; missing or shell-only libraries
 * keep the backend unavailable.
 */
class GeniePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    companion object {
        private const val CHANNEL_NAME = "runanywhere_genie"
        private const val BACKEND_VERSION = "0.1.6"
        private const val BACKEND_NAME = "Genie"

        init {
            // Load the experimental Genie backend shell when present.
            try {
                System.loadLibrary("rac_backend_genie_jni")
            } catch (e: UnsatisfiedLinkError) {
                // Library may not be available in all configurations
                android.util.Log.w("Genie", "Failed to load rac_backend_genie_jni: ${e.message}")
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
            "getBackendVersion" -> {
                result.success(BACKEND_VERSION)
            }
            "getBackendName" -> {
                result.success(BACKEND_NAME)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
