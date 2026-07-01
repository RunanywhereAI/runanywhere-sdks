package ai.runanywhere.sdk.qhexrt

import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * RunAnywhere QHexRT Flutter plugin (Android). Loads the private QHexRT engine
 * shell into the process so the Dart FFI bindings can resolve its symbols. The
 * backend is Snapdragon v79/v81 only; on other devices the load fails softly and
 * the Dart layer reports the NPU as unsupported.
 */
class QhexrtPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    companion object {
        private const val CHANNEL_NAME = "runanywhere_qhexrt"
        private const val BACKEND_VERSION = "0.1.5"
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
        configureQnnDspLibraryPath(binding.applicationContext)
    }

    /**
     * QHexRT (QNN) loads the per-arch Hexagon DSP skel (e.g. libQnnHtpV81Skel.so)
     * over fastRPC; the DSP only finds it when ADSP_LIBRARY_PATH includes the dir
     * it ships in. The skel is bundled in the app's native lib dir, so point the
     * DSP loader there (plus the standard vendor search paths) before any backend
     * creates a QNN context. Mirrors the Kotlin example app's setup so Flutter
     * apps need no app-level workaround.
     */
    private fun configureQnnDspLibraryPath(context: Context) {
        runCatching {
            val nativeLibDir = context.applicationInfo.nativeLibraryDir ?: return
            val existing = System.getenv("ADSP_LIBRARY_PATH").orEmpty()
            val path =
                listOf(nativeLibDir, existing, "/vendor/dsp/cdsp", "/vendor/lib/rfsa/adsp")
                    .filter { it.isNotBlank() }
                    .joinToString(";")
            android.system.Os.setenv("ADSP_LIBRARY_PATH", path, true)
            android.util.Log.i("QHexRT", "ADSP_LIBRARY_PATH set to $path")
        }.onFailure {
            android.util.Log.e("QHexRT", "Failed to set ADSP_LIBRARY_PATH", it)
        }
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
