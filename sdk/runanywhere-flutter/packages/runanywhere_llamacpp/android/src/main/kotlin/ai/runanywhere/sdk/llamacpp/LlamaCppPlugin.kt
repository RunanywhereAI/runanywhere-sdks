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
        private const val TAG = "LlamaCpp"
        private const val CHANNEL_NAME = "runanywhere_llamacpp"
        private const val BACKEND_VERSION = "0.19.13"
        private const val BACKEND_NAME = "LlamaCPP"

        init {
            // Load LlamaCPP backend native libraries.
            //
            // Mirror OnnxPlugin.kt: load each library with an individual
            // `System.loadLibrary` so we surface a precise diagnostic instead of
            // swallowing the intermediate `UnsatisfiedLinkError` chain that
            // `loadFirstAvailable` produced. The previous helper hid the real
            // failing dependency, which made debugging Android linker failures
            // significantly harder.
            //
            // Load order matches the JNI dependency graph:
            //   1. `librac_backend_llamacpp.so`     — core llama.cpp engine + RAC vtable.
            //   2. `librac_backend_llamacpp_jni.so` — Android JNI shim that registers
            //      the engine and the VLM plugin with the C++ registry.
            // Either may be absent depending on how the engines CMake was built
            // (RAC_BUILD_SHARED gates the JNI suffix), so each load failure is
            // logged independently but is never fatal — `Llamacpp.register()` on
            // the Dart side falls back to FFI-only registration if needed.
            try {
                System.loadLibrary("rac_backend_llamacpp")
            } catch (e: UnsatisfiedLinkError) {
                android.util.Log.w(TAG, "librac_backend_llamacpp.so unavailable: ${e.message}")
            }
            try {
                System.loadLibrary("rac_backend_llamacpp_jni")
            } catch (e: UnsatisfiedLinkError) {
                android.util.Log.w(TAG, "librac_backend_llamacpp_jni.so unavailable: ${e.message}")
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
