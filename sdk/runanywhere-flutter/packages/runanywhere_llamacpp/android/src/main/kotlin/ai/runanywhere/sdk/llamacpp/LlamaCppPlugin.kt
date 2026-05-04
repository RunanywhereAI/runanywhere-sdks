package ai.runanywhere.sdk.llamacpp

import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * RunAnywhere LlamaCPP Flutter Plugin - Android Implementation
 *
 * This plugin provides the native bridge for the LlamaCPP backend on Android.
 * The actual LLM functionality is provided by RABackendLlamaCPP native libraries (.so files).
 */
class LlamaCppPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    companion object {
        private const val CHANNEL_NAME = "runanywhere_llamacpp"
        private const val BACKEND_VERSION = "0.1.4"
        private const val BACKEND_NAME = "LlamaCPP"

        private fun loadFirstAvailable(vararg names: String) {
            var lastError: UnsatisfiedLinkError? = null
            for (name in names) {
                try {
                    System.loadLibrary(name)
                    return
                } catch (e: UnsatisfiedLinkError) {
                    lastError = e
                }
            }
            if (lastError != null) {
                throw lastError
            }
        }

        init {
            // Load LlamaCPP backend native libraries
            try {
                loadFirstAvailable(
                    "rac_backend_llamacpp",
                    "rac_backend_llamacpp_jni",
                    "runanywhere_llamacpp",
                )
            } catch (e: UnsatisfiedLinkError) {
                // Library may not be available in all configurations
                android.util.Log.w("LlamaCpp", "Failed to load LlamaCpp backend libraries: ${e.message}")
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
