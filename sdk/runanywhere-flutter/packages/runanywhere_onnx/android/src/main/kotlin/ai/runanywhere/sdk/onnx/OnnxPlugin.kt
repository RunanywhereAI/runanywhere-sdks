package ai.runanywhere.sdk.onnx

import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * RunAnywhere ONNX Flutter Plugin - Android Implementation
 *
 * This plugin provides the native bridge for the ONNX backend on Android.
 * The actual STT/TTS/VAD functionality is provided by RABackendONNX native libraries (.so files).
 */
class OnnxPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    companion object {
        private const val CHANNEL_NAME = "runanywhere_onnx"
        private const val BACKEND_VERSION = "0.1.4"
        private const val BACKEND_NAME = "ONNX"

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
            // Load ONNX backend native libraries
            try {
                System.loadLibrary("onnxruntime")
                System.loadLibrary("sherpa-onnx-c-api")
                loadFirstAvailable(
                    "rac_backend_onnx",
                    "rac_backend_onnx_jni",
                    "runanywhere_onnx",
                )
                // B-FL-10-001 / B-RN-10-001: explicitly load the Sherpa engine lib so its
                // ELF __attribute__((constructor)) auto-registers STT/TTS/VAD with the
                // unified plugin registry. Without this, rac_plugin_route returns -423 for
                // every Sherpa-backed model load. The autoregister wraps rac_plugin_register
                // which is idempotent, so re-loads are safe.
                try {
                    System.loadLibrary("rac_backend_sherpa")
                } catch (e: UnsatisfiedLinkError) {
                    android.util.Log.w("ONNX", "rac_backend_sherpa not available: ${e.message}")
                }
            } catch (e: UnsatisfiedLinkError) {
                // Library may not be available in all configurations
                android.util.Log.w("ONNX", "Failed to load ONNX libraries: ${e.message}")
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
            "getCapabilities" -> {
                result.success(listOf("stt", "tts", "vad"))
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
