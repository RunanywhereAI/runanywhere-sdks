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

        /**
         * Whether the Genie backend shell library is loaded and Genie features
         * may be advertised to Dart. Devices without the .so (e.g. non-Snapdragon)
         * keep this false; the plugin still answers method-channel pings but
         * Dart code should treat Genie as unavailable.
         */
        @JvmStatic
        var isNativeLibAvailable: Boolean = false
            private set

        init {
            // Load the experimental Genie backend shell when present.
            // Catch broadly so a bad .so or a Throwable from a transitive
            // load never aborts plugin init (B-FL-1-001).
            try {
                System.loadLibrary("rac_backend_genie_jni")
                isNativeLibAvailable = true
            } catch (t: Throwable) {
                isNativeLibAvailable = false
                android.util.Log.w(
                    "Genie",
                    "rac_backend_genie_jni unavailable on this device — Genie features disabled: ${t.message}",
                )
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
