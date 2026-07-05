package ai.runanywhere.sdk.qhexrt

import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * RunAnywhere QHexRT Flutter plugin (Android). Loads the private QHexRT engine
 * shell into the process so the Dart FFI bindings can resolve its symbols. The
 * backend is Snapdragon v75+ only; on other devices the load fails softly and
 * the Dart layer reports the NPU as unsupported.
 */
class QhexrtPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    companion object {
        private const val CHANNEL_NAME = "runanywhere_qhexrt"
        private const val BACKEND_VERSION = "0.19.13"
        private const val BACKEND_NAME = "QHexRT"

        @JvmStatic
        var isNativeLibAvailable: Boolean = false
            private set

        init {
            try {
                System.loadLibrary("rac_backend_qhexrt")
                isNativeLibAvailable = true
            } catch (t: Throwable) {
                isNativeLibAvailable = false
                android.util.Log.w(
                    "QHexRT",
                    "librac_backend_qhexrt unavailable on this device — QHexRT disabled: ${t.message}",
                )
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        // Note: ADSP_LIBRARY_PATH (Hexagon DSP skel discovery) is set by the QHexRT
        // engine itself before its first runtime create — no plugin glue needed.
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
            "getBackendVersion" -> result.success(BACKEND_VERSION)
            "getBackendName" -> result.success(BACKEND_NAME)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
