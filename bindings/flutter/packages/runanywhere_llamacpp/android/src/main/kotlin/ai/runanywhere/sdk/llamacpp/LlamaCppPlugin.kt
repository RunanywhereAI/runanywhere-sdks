package ai.runanywhere.sdk.llamacpp

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * RunAnywhere LlamaCPP Flutter Plugin - Android Implementation
 *
 * This plugin only participates in Flutter plugin registration and native
 * library loading. Dart talks to the backend through FFI registration symbols.
 */
class LlamaCppPlugin : FlutterPlugin {
    companion object {
        private const val TAG = "LlamaCpp"

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

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) = Unit

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit
}
