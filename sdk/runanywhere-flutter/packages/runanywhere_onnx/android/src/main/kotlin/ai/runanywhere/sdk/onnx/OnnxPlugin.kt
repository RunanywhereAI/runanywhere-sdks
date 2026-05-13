package ai.runanywhere.sdk.onnx

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * RunAnywhere ONNX Flutter Plugin - Android Implementation
 *
 * This plugin only participates in Flutter plugin registration and native
 * library loading. Dart talks to the backend through FFI registration symbols.
 */
class OnnxPlugin : FlutterPlugin {
    companion object {
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

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) = Unit

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit
}
