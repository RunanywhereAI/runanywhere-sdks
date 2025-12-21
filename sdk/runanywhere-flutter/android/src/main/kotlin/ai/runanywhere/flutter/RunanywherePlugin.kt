package ai.runanywhere.flutter

import android.content.Context
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * RunAnywhere Flutter Plugin for Android
 *
 * This plugin provides the bridge between Flutter and the RunAnywhere native library.
 * The main functionality is exposed via FFI (Dart's Foreign Function Interface),
 * so this plugin class is minimal - it handles registration and native library loading.
 *
 * Architecture:
 * - FFI-based: Core functionality accessed via dart:ffi (similar to iOS)
 * - Method Channels: Only for platform-specific utilities
 * - Native Library Loading: Ensures symbols are available for Dart FFI
 *
 * Parity with iOS:
 * - iOS uses RunAnywhereBridge.forceSymbolLoading() to ensure symbols are available
 * - Android uses System.loadLibrary() in correct dependency order for symbol visibility
 * - Both platforms provide minimal method channel handlers for diagnostics
 */
class RunanywherePlugin: FlutterPlugin, MethodCallHandler {
    companion object {
        private const val TAG = "RunAnywhere"
        private const val CHANNEL = "ai.runanywhere.flutter/plugin"
        private const val VERSION = "0.15.8"

        // Track if native libraries are loaded
        private var nativeLibrariesLoaded = false
        private var nativeLoadError: String? = null
        private val loadedLibraries = mutableListOf<String>()

        /**
         * Load native libraries in the correct order.
         * This is called early to ensure symbols are available for FFI.
         *
         * Symbol Loading Strategy (Android):
         * 1. Load dependencies first (base libs → backends → bridge)
         * 2. Track all loaded libraries for diagnostics
         * 3. Ensure proper symbol visibility for FFI lookups
         *
         * Equivalent to iOS RunAnywhereBridge.forceSymbolLoading()
         */
        fun loadNativeLibraries() {
            if (nativeLibrariesLoaded) {
                Log.d(TAG, "Native libraries already loaded")
                return
            }

            try {
                Log.i(TAG, "Loading native libraries...")

                // Load dependencies in correct order for Android symbol visibility
                // Order matters: base libs first, then backends, then bridge

                // 1. Load C++ standard library (required by all native libs)
                tryLoadLibrary("c++_shared")

                // 2. Load OpenMP (required by LlamaCpp and some ONNX operations)
                tryLoadLibrary("omp")

                // 3. Load ONNX Runtime (required by ONNX backend and Sherpa-ONNX)
                tryLoadLibrary("onnxruntime")

                // 4. Load Sherpa-ONNX libraries (for STT/TTS/VAD)
                tryLoadLibrary("sherpa-onnx-cxx-api")
                tryLoadLibrary("sherpa-onnx-c-api")
                tryLoadLibrary("sherpa-onnx-jni")

                // 5. Load backend-specific libraries
                tryLoadLibrary("runanywhere_onnx")
                tryLoadLibrary("runanywhere_llamacpp")

                // 6. Load the RunAnywhere loader (provides global symbol loading)
                tryLoadLibrary("runanywhere_loader")

                // 7. Finally load the main bridge library (must be last)
                loadLibraryRequired("runanywhere_bridge")

                nativeLibrariesLoaded = true
                Log.i(TAG, "✅ Native libraries loaded successfully")
                Log.d(TAG, "Loaded libraries: ${loadedLibraries.joinToString(", ")}")

                // Force symbol loading by calling a native function
                // This ensures all symbols are linked and available for FFI
                forceSymbolLoading()

            } catch (e: UnsatisfiedLinkError) {
                nativeLoadError = e.message
                nativeLibrariesLoaded = false
                Log.e(TAG, "❌ Failed to load native libraries: ${e.message}", e)
                throw e
            } catch (e: Exception) {
                nativeLoadError = e.message
                nativeLibrariesLoaded = false
                Log.e(TAG, "❌ Unexpected error loading native libraries: ${e.message}", e)
                throw e
            }
        }

        /**
         * Try to load a library, logging success or failure.
         * Does not throw if library is not present (optional dependency).
         */
        private fun tryLoadLibrary(name: String) {
            try {
                System.loadLibrary(name)
                loadedLibraries.add(name)
                Log.d(TAG, "  ✓ Loaded library: $name")
            } catch (e: UnsatisfiedLinkError) {
                // Library may not be present or already loaded
                Log.d(TAG, "  - Could not load $name (may be optional): ${e.message}")
            }
        }

        /**
         * Load a required library, throwing if it fails.
         */
        private fun loadLibraryRequired(name: String) {
            try {
                System.loadLibrary(name)
                loadedLibraries.add(name)
                Log.i(TAG, "  ✓ Loaded required library: $name")
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "  ✗ Failed to load required library: $name", e)
                throw UnsatisfiedLinkError(
                    "Required library '$name' could not be loaded. " +
                    "Error: ${e.message}\n\n" +
                    "This may indicate:\n" +
                    "  1. Missing .so file in jniLibs/\n" +
                    "  2. Incorrect ABI architecture\n" +
                    "  3. Missing dependencies\n\n" +
                    "Successfully loaded: ${loadedLibraries.joinToString(", ")}"
                )
            }
        }

        /**
         * Force symbol loading by calling a native function.
         * This ensures all symbols are linked and available for Dart FFI.
         *
         * Equivalent to iOS RunAnywhereBridge.forceSymbolLoading()
         * which calls ra_get_available_backends() to force linking.
         */
        private fun forceSymbolLoading() {
            try {
                // Call a native function to force symbol loading
                // This is similar to iOS calling ra_get_available_backends()
                nativeForceSymbolLoading()
                Log.d(TAG, "  ✓ Forced symbol loading via native call")
            } catch (e: UnsatisfiedLinkError) {
                Log.w(TAG, "  - Could not force symbol loading (may not be required): ${e.message}")
            }
        }

        /**
         * Force symbol loading using RunAnywhereBridge.
         * Equivalent to iOS RunAnywhereBridge.forceSymbolLoading()
         */
        private fun nativeForceSymbolLoading() {
            // Use the bridge to force symbol loading
            RunAnywhereBridge.forceSymbolLoading()
        }

        /**
         * Check if native libraries are loaded.
         */
        fun isNativeLibraryLoaded(): Boolean = nativeLibrariesLoaded

        /**
         * Get the last load error, if any.
         */
        fun getNativeLoadError(): String? = nativeLoadError

        /**
         * Get list of successfully loaded libraries.
         */
        fun getLoadedLibraries(): List<String> = loadedLibraries.toList()
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    /**
     * Called when the plugin is attached to the Flutter engine.
     * This is where we initialize the plugin and load native libraries.
     */
    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)

        // Load native libraries when plugin attaches
        // This ensures symbols are available before any FFI calls
        try {
            loadNativeLibraries()
            Log.i(TAG, "Android plugin attached successfully (v$VERSION)")
        } catch (e: Exception) {
            Log.e(TAG, "Android plugin attached with errors: ${e.message}", e)
        }
    }

    /**
     * Handle method channel calls from Flutter.
     *
     * Available methods (for parity with iOS):
     *
     * Platform Information:
     * - getPlatformVersion: Get Android OS version (e.g., "Android 14")
     * - getPluginVersion: Get plugin version
     * - getDeviceInfo: Get device manufacturer and model
     * - getCurrentAbi: Get current ABI (e.g., "arm64-v8a")
     * - getSupportedAbis: Get all supported ABIs
     *
     * Native Library Status:
     * - isNativeLibraryAvailable: Check if native libraries loaded successfully
     * - getNativeLoadError: Get error message if loading failed
     * - getLoadedLibraries: Get list of loaded native libraries
     * - testNativeLibrary: Test if native library is accessible
     * - forceSymbolLoading: Force symbol loading (for debugging)
     *
     * Native Library Information:
     * - getAvailableBackends: Get available backends from native library
     * - getNativeVersion: Get native library version
     *
     * Storage Paths:
     * - getApplicationFilesDir: Get app files directory path
     * - getCacheDir: Get cache directory path
     * - getExternalFilesDir: Get external files directory path (may be null)
     * - getNativeLibraryDir: Get native library directory path
     *
     * Diagnostics:
     * - getDiagnostics: Get comprehensive platform diagnostics (for debugging)
     */
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                // Return Android version (e.g., "Android 14")
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }

            "isNativeLibraryAvailable" -> {
                // Check if native libraries loaded successfully
                result.success(nativeLibrariesLoaded)
            }

            "getNativeLoadError" -> {
                // Get error message if loading failed
                result.success(nativeLoadError)
            }

            "getApplicationFilesDir" -> {
                // Get application files directory for storing models/data
                result.success(context.filesDir.absolutePath)
            }

            "getLoadedLibraries" -> {
                // Get list of successfully loaded libraries (for diagnostics)
                result.success(loadedLibraries.toList())
            }

            "getPluginVersion" -> {
                // Get plugin version
                result.success(VERSION)
            }

            "getCacheDir" -> {
                // Get cache directory path
                result.success(context.cacheDir.absolutePath)
            }

            "getExternalFilesDir" -> {
                // Get external files directory (for larger files)
                val externalFilesDir = context.getExternalFilesDir(null)
                result.success(externalFilesDir?.absolutePath)
            }

            "forceSymbolLoading" -> {
                // Force symbol loading (for debugging)
                try {
                    forceSymbolLoading()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("FORCE_SYMBOL_ERROR", e.message, e.toString())
                }
            }

            "getDiagnostics" -> {
                // Get platform diagnostics (for debugging)
                try {
                    val diagnostics = PlatformUtils.getDiagnostics(context)
                    result.success(diagnostics)
                } catch (e: Exception) {
                    result.error("DIAGNOSTICS_ERROR", e.message, e.toString())
                }
            }

            "getCurrentAbi" -> {
                // Get current ABI
                result.success(PlatformUtils.getCurrentAbi())
            }

            "getSupportedAbis" -> {
                // Get all supported ABIs
                result.success(PlatformUtils.getSupportedAbis())
            }

            "getDeviceInfo" -> {
                // Get device manufacturer and model
                result.success(PlatformUtils.getDeviceInfo())
            }

            "getNativeLibraryDir" -> {
                // Get native library directory
                result.success(PlatformUtils.getNativeLibraryDir(context))
            }

            "getAvailableBackends" -> {
                // Get available backends from native library
                try {
                    val backends = RunAnywhereBridge.getAvailableBackends()
                    result.success(backends.toList())
                } catch (e: Exception) {
                    result.error("BACKENDS_ERROR", e.message, e.toString())
                }
            }

            "getNativeVersion" -> {
                // Get native library version
                try {
                    val version = RunAnywhereBridge.getNativeVersion()
                    result.success(version)
                } catch (e: Exception) {
                    result.error("VERSION_ERROR", e.message, e.toString())
                }
            }

            "testNativeLibrary" -> {
                // Test if native library is accessible
                result.success(RunAnywhereBridge.testNativeLibrary())
            }

            else -> {
                // Method not implemented
                result.notImplemented()
            }
        }
    }

    /**
     * Called when the plugin is detached from the Flutter engine.
     * Cleanup resources here.
     */
    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        Log.i(TAG, "Android plugin detached")
    }
}
