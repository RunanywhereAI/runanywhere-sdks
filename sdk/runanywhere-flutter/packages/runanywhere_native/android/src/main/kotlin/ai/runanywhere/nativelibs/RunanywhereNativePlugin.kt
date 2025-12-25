package ai.runanywhere.nativelibs

import android.content.Context
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * RunAnywhere Native Plugin for Android
 *
 * This plugin provides native library loading for RunAnywhere.
 * The main functionality is exposed via FFI (Dart's Foreign Function Interface),
 * so this plugin class handles library loading and basic platform queries.
 */
class RunanywhereNativePlugin: FlutterPlugin, MethodCallHandler {
    companion object {
        private const val TAG = "RunAnywhereNative"
        private const val CHANNEL = "ai.runanywhere.nativelibs/plugin"

        // Track if native libraries are loaded
        private var nativeLibrariesLoaded = false
        private var nativeLoadError: String? = null

        /**
         * Load native libraries in the correct order.
         * This is called early to ensure symbols are available for FFI.
         */
        fun loadNativeLibraries() {
            if (nativeLibrariesLoaded) return

            try {
                // Load dependencies first (order matters for symbol resolution)
                tryLoadLibrary("c++_shared")
                tryLoadLibrary("omp")
                tryLoadLibrary("onnxruntime")
                tryLoadLibrary("sherpa-onnx-cxx-api")
                tryLoadLibrary("sherpa-onnx-c-api")
                tryLoadLibrary("sherpa-onnx-jni")

                // Load backend-specific libraries
                tryLoadLibrary("runanywhere_onnx")
                tryLoadLibrary("runanywhere_llamacpp")

                // Load the loader (provides global symbol loading)
                tryLoadLibrary("runanywhere_loader")

                // Load the main bridge library
                System.loadLibrary("runanywhere_bridge")

                nativeLibrariesLoaded = true
                Log.i(TAG, "Native libraries loaded successfully")
            } catch (e: UnsatisfiedLinkError) {
                nativeLoadError = e.message
                Log.e(TAG, "Failed to load native libraries: ${e.message}")
            }
        }

        private fun tryLoadLibrary(name: String) {
            try {
                System.loadLibrary(name)
                Log.d(TAG, "Loaded library: $name")
            } catch (e: UnsatisfiedLinkError) {
                // Library may not be present or already loaded
                Log.d(TAG, "Could not load $name: ${e.message}")
            }
        }
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)

        // Load native libraries when plugin attaches
        loadNativeLibraries()

        Log.i(TAG, "Native plugin attached")
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "isNativeLibraryAvailable" -> {
                result.success(nativeLibrariesLoaded)
            }
            "getNativeLoadError" -> {
                result.success(nativeLoadError)
            }
            "getApplicationFilesDir" -> {
                result.success(context.filesDir.absolutePath)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        Log.i(TAG, "Native plugin detached")
    }
}
