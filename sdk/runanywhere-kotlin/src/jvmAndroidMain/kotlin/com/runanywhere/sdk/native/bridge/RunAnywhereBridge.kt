package com.runanywhere.sdk.native.bridge

private const val TAG = "RunAnywhereBridge"

// Simple logging that works on both JVM and Android (println shows in logcat on Android)
private fun logI(tag: String, msg: String) = println("I/$tag: $msg")
private fun logD(tag: String, msg: String) = println("D/$tag: $msg")
private fun logE(tag: String, msg: String) = println("E/$tag: $msg")

/**
 * Unified RunAnywhere Native Bridge
 *
 * This object provides JNI bindings to the RunAnywhere Core C API (runanywhere_bridge.h).
 * It works with ALL backends (ONNX, LlamaCPP, TFLite, etc.) through a unified interface.
 *
 * The package name MUST be `com.runanywhere.sdk.native.bridge` to match the JNI function
 * registration in the native library (Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_*).
 *
 * Thread Safety:
 * - All methods are thread-safe at the C API level
 * - Handles are opaque pointers managed by native code
 * - Stream handles must be destroyed on the same thread they were created (recommended)
 *
 * Usage:
 * 1. Call loadLibrary() or loadLibraryWithBackend() before any other methods
 * 2. Create a backend handle with nativeCreateBackend("onnx") or nativeCreateBackend("llamacpp")
 * 3. Use the handle to call capability-specific methods
 * 4. Destroy the handle when done with nativeDestroy()
 */
object RunAnywhereBridge {

    private var isLibraryLoaded = false
    private val loadedBackends = mutableSetOf<String>()
    private var loaderInitialized = false
    private var nativeLibraryDir: String? = null

    /**
     * Set the native library directory. Must be called before loadLibrary() on Android.
     * This is required for the RunAnywhereLoader to find libraries with full paths.
     *
     * @param libraryDir The native library directory (from context.applicationInfo.nativeLibraryDir)
     */
    @Synchronized
    fun setNativeLibraryDir(libraryDir: String) {
        nativeLibraryDir = libraryDir
        logD(TAG, "Native library directory set to: $libraryDir")
    }

    /**
     * Load the core JNI bridge library. Must be called before any other methods.
     * This is idempotent - calling it multiple times is safe.
     *
     * IMPORTANT: On Android, when ONNX libraries are bundled with the app, we must
     * pre-load libonnxruntime.so with RTLD_GLOBAL flag BEFORE loading the JNI library.
     * This is because libsherpa-onnx-c-api.so (which is a transitive dependency of
     * librunanywhere_jni.so) requires OrtGetApiBase and other symbols from onnxruntime.
     * System.loadLibrary() doesn't make symbols globally visible, but dlopen with
     * RTLD_GLOBAL does.
     */
    @Synchronized
    fun loadLibrary() {
        if (isLibraryLoaded) return

        try {
            // Step 1: Try to initialize the loader first (has NO dependencies)
            // This allows us to load ONNX libraries with RTLD_GLOBAL
            val loaderLoaded = tryInitializeLoader()

            // Step 2: If loader is available and ONNX libraries exist, pre-load them
            // with RTLD_GLOBAL so their symbols are visible to dependent libraries
            if (loaderLoaded) {
                preloadOnnxLibrariesWithGlobal()
            }

            // Step 3: Now load the JNI library - dependencies should resolve correctly
            logI(TAG, "Loading librunanywhere_jni.so...")
            System.loadLibrary("runanywhere_jni")
            isLibraryLoaded = true
            logI(TAG, "Successfully loaded librunanywhere_jni.so")
        } catch (e: UnsatisfiedLinkError) {
            logE(TAG, "Failed to load RunAnywhere JNI native library: ${e.message}")
            throw RuntimeException("Failed to load RunAnywhere JNI native library", e)
        }
    }

    /**
     * Try to initialize the RunAnywhereLoader (minimal library with no dependencies).
     * @return true if loader was initialized successfully
     */
    private fun tryInitializeLoader(): Boolean {
        if (loaderInitialized) return true

        // Try to load the loader library (it has NO dependencies)
        return try {
            System.loadLibrary("runanywhere_loader")
            logI(TAG, "Loaded librunanywhere_loader.so")

            // Set the native library directory if available
            val libDir = nativeLibraryDir
            if (libDir != null) {
                RunAnywhereLoader.initialize(libDir)
                loaderInitialized = true
                logI(TAG, "Loader initialized with library dir: $libDir")
                true
            } else {
                logD(TAG, "Native library directory not set - loader cannot use full paths")
                false
            }
        } catch (e: UnsatisfiedLinkError) {
            // Loader not available - this is OK for builds without it
            logD(TAG, "librunanywhere_loader.so not available: ${e.message}")
            false
        }
    }

    /**
     * Pre-load ONNX libraries with RTLD_GLOBAL flag.
     * This makes symbols like OrtGetApiBase globally visible so that
     * libsherpa-onnx-c-api.so can find them when loaded as a transitive dependency.
     */
    private fun preloadOnnxLibrariesWithGlobal() {
        if (!loaderInitialized) return

        // Check if ONNX libraries are bundled
        if (!RunAnywhereLoader.hasLibrary("onnxruntime")) {
            logD(TAG, "libonnxruntime.so not found - skipping ONNX pre-load")
            return
        }

        logI(TAG, "Pre-loading ONNX libraries with RTLD_GLOBAL...")

        // Load onnxruntime with RTLD_GLOBAL - this is the critical step!
        // RTLD_GLOBAL makes OrtGetApiBase and other symbols available to
        // subsequently loaded libraries like libsherpa-onnx-c-api.so
        val onnxLoaded = RunAnywhereLoader.loadLibraryGlobal("onnxruntime")
        if (onnxLoaded) {
            logI(TAG, "Successfully loaded libonnxruntime.so with RTLD_GLOBAL")
        } else {
            logE(TAG, "Failed to load libonnxruntime.so with RTLD_GLOBAL")
        }

        // Load sherpa-onnx-c-api if present (needs onnxruntime symbols)
        if (RunAnywhereLoader.hasLibrary("sherpa-onnx-c-api")) {
            val sherpaLoaded = RunAnywhereLoader.loadLibraryGlobal("sherpa-onnx-c-api")
            if (sherpaLoaded) {
                logI(TAG, "Successfully loaded libsherpa-onnx-c-api.so with RTLD_GLOBAL")
            } else {
                logE(TAG, "Failed to load libsherpa-onnx-c-api.so with RTLD_GLOBAL")
            }
        }
    }

    /**
     * Load a specific backend's native libraries.
     *
     * @param backend The backend name: "onnx", "llamacpp", "tflite"
     */
    @Synchronized
    fun loadBackend(backend: String) {
        // Ensure JNI is loaded first
        loadLibrary()

        if (loadedBackends.contains(backend)) return

        when (backend.lowercase()) {
            "onnx" -> {
                // ONNX has a strict dependency chain that must be loaded in order:
                // 1. onnxruntime (exports OrtGetApiBase)
                // 2. sherpa-onnx-c-api (requires OrtGetApiBase from onnxruntime)
                // 3. runanywhere_onnx (requires sherpa-onnx-c-api)
                //
                // Due to Android linker namespace isolation, we must load each library
                // explicitly in order. If any prerequisite fails, the chain breaks.
                logI(TAG, "Loading ONNX backend libraries in dependency order...")

                // Load onnxruntime first - this MUST succeed
                val onnxLoaded = loadLibraryWithLogging("onnxruntime", useGlobalSymbols = true)
                if (!onnxLoaded) {
                    logE(TAG, "Failed to load libonnxruntime.so - ONNX backend will not work")
                }

                // Load sherpa-onnx-c-api second - requires onnxruntime
                val sherpaLoaded = loadLibraryWithLogging("sherpa-onnx-c-api")
                if (!sherpaLoaded) {
                    logE(TAG, "Failed to load libsherpa-onnx-c-api.so - ONNX backend will not work")
                }

                // Load runanywhere_onnx third - requires sherpa-onnx-c-api
                val raOnnxLoaded = loadLibraryWithLogging("runanywhere_onnx")
                if (!raOnnxLoaded) {
                    logE(TAG, "Failed to load librunanywhere_onnx.so - ONNX backend will not work")
                }

                if (onnxLoaded && sherpaLoaded && raOnnxLoaded) {
                    logI(TAG, "ONNX backend libraries loaded successfully")
                } else {
                    logE(TAG, "ONNX backend failed to load completely. onnx=$onnxLoaded, sherpa=$sherpaLoaded, ra_onnx=$raOnnxLoaded")
                }
            }
            "llamacpp" -> {
                loadLibraryWithLogging("omp")
                loadLibraryWithLogging("ggml")
                loadLibraryWithLogging("llama")
                loadLibraryWithLogging("runanywhere_llamacpp")
            }
            "tflite" -> {
                loadLibraryWithLogging("runanywhere_tflite")
            }
            else -> {
                throw IllegalArgumentException("Unknown backend: $backend")
            }
        }

        loadedBackends.add(backend.lowercase())
    }

    /**
     * Try to load a native library with logging.
     * @param name Library name without "lib" prefix and ".so" suffix
     * @param useGlobalSymbols If true, load with RTLD_GLOBAL flag to make symbols globally visible
     * @return true if loaded successfully, false otherwise
     */
    private fun loadLibraryWithLogging(name: String, useGlobalSymbols: Boolean = false): Boolean {
        return try {
            logD(TAG, "Loading library: lib$name.so${if (useGlobalSymbols) " (with RTLD_GLOBAL)" else ""}")

            if (useGlobalSymbols) {
                // Prefer using RunAnywhereLoader (uses full path for Android compatibility)
                if (loaderInitialized && RunAnywhereLoader.isInitialized()) {
                    val loaded = RunAnywhereLoader.loadLibraryGlobal(name)
                    if (loaded) {
                        logI(TAG, "Successfully loaded: lib$name.so with RTLD_GLOBAL via Loader")
                    } else {
                        logE(TAG, "Failed to load lib$name.so with RTLD_GLOBAL via Loader")
                    }
                    return loaded
                }

                // Fallback to JNI native function (may not work on Android due to path issues)
                val loaded = nativeLoadLibraryWithGlobal(name)
                if (loaded) {
                    logI(TAG, "Successfully loaded: lib$name.so with RTLD_GLOBAL")
                } else {
                    logE(TAG, "Failed to load lib$name.so with RTLD_GLOBAL")
                }
                loaded
            } else {
                System.loadLibrary(name)
                logI(TAG, "Successfully loaded: lib$name.so")
                true
            }
        } catch (e: UnsatisfiedLinkError) {
            logE(TAG, "Failed to load lib$name.so: ${e.message}")
            // Check if it's already loaded (different error message)
            if (e.message?.contains("already loaded") == true) {
                logI(TAG, "Library lib$name.so was already loaded")
                true
            } else {
                false
            }
        }
    }

    /**
     * Check if the core JNI library is loaded.
     */
    fun isLoaded(): Boolean = isLibraryLoaded

    /**
     * Check if a specific backend is loaded.
     * Thread-safe via @Synchronized to match loadBackend().
     */
    @Synchronized
    fun isBackendLoaded(backend: String): Boolean = loadedBackends.contains(backend.lowercase())

    // =============================================================================
    // Backend Lifecycle
    // =============================================================================

    @JvmStatic
    external fun nativeGetAvailableBackends(): Array<String>

    @JvmStatic
    external fun nativeCreateBackend(backendName: String): Long

    @JvmStatic
    external fun nativeInitialize(handle: Long, configJson: String?): Int

    @JvmStatic
    external fun nativeIsInitialized(handle: Long): Boolean

    @JvmStatic
    external fun nativeDestroy(handle: Long)

    @JvmStatic
    external fun nativeGetBackendInfo(handle: Long): String

    @JvmStatic
    external fun nativeSupportsCapability(handle: Long, capability: Int): Boolean

    @JvmStatic
    external fun nativeGetCapabilities(handle: Long): IntArray

    @JvmStatic
    external fun nativeGetDevice(handle: Long): Int

    @JvmStatic
    external fun nativeGetMemoryUsage(handle: Long): Long

    // =============================================================================
    // Text Generation
    // =============================================================================

    @JvmStatic
    external fun nativeTextLoadModel(handle: Long, modelPath: String, configJson: String?): Int

    @JvmStatic
    external fun nativeTextIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeTextUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeTextGenerate(
        handle: Long,
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Float
    ): String?

    @JvmStatic
    external fun nativeTextCancel(handle: Long)

    // =============================================================================
    // Speech-to-Text (STT)
    // =============================================================================

    @JvmStatic
    external fun nativeSTTLoadModel(
        handle: Long,
        modelPath: String,
        modelType: String,
        configJson: String?
    ): Int

    @JvmStatic
    external fun nativeSTTIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeSTTUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeSTTTranscribe(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int,
        language: String?
    ): String?

    @JvmStatic
    external fun nativeSTTSupportsStreaming(handle: Long): Boolean

    @JvmStatic
    external fun nativeSTTCreateStream(handle: Long, configJson: String?): Long

    @JvmStatic
    external fun nativeSTTFeedAudio(
        handle: Long,
        streamHandle: Long,
        audioSamples: FloatArray,
        sampleRate: Int
    ): Int

    @JvmStatic
    external fun nativeSTTIsReady(handle: Long, streamHandle: Long): Boolean

    @JvmStatic
    external fun nativeSTTDecode(handle: Long, streamHandle: Long): String

    @JvmStatic
    external fun nativeSTTIsEndpoint(handle: Long, streamHandle: Long): Boolean

    @JvmStatic
    external fun nativeSTTInputFinished(handle: Long, streamHandle: Long)

    @JvmStatic
    external fun nativeSTTResetStream(handle: Long, streamHandle: Long)

    @JvmStatic
    external fun nativeSTTDestroyStream(handle: Long, streamHandle: Long)

    @JvmStatic
    external fun nativeSTTCancel(handle: Long)

    // =============================================================================
    // Text-to-Speech (TTS)
    // =============================================================================

    @JvmStatic
    external fun nativeTTSLoadModel(
        handle: Long,
        modelPath: String,
        modelType: String,
        configJson: String?
    ): Int

    @JvmStatic
    external fun nativeTTSIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeTTSUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeTTSSynthesize(
        handle: Long,
        text: String,
        voiceId: String?,
        speedRate: Float,
        pitchShift: Float
    ): NativeTTSSynthesisResult?

    @JvmStatic
    external fun nativeTTSSupportsStreaming(handle: Long): Boolean

    @JvmStatic
    external fun nativeTTSGetVoices(handle: Long): String

    @JvmStatic
    external fun nativeTTSCancel(handle: Long)

    // =============================================================================
    // Voice Activity Detection (VAD)
    // =============================================================================

    @JvmStatic
    external fun nativeVADLoadModel(handle: Long, modelPath: String?, configJson: String?): Int

    @JvmStatic
    external fun nativeVADIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeVADUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeVADProcess(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int
    ): NativeVADResult?

    @JvmStatic
    external fun nativeVADDetectSegments(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int
    ): String?

    @JvmStatic
    external fun nativeVADReset(handle: Long)

    // =============================================================================
    // Embeddings
    // =============================================================================

    @JvmStatic
    external fun nativeEmbedLoadModel(handle: Long, modelPath: String, configJson: String?): Int

    @JvmStatic
    external fun nativeEmbedIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeEmbedUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeEmbedText(handle: Long, text: String): FloatArray?

    @JvmStatic
    external fun nativeEmbedGetDimensions(handle: Long): Int

    // =============================================================================
    // Speaker Diarization
    // =============================================================================

    @JvmStatic
    external fun nativeDiarizeLoadModel(handle: Long, modelPath: String, configJson: String?): Int

    @JvmStatic
    external fun nativeDiarizeIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeDiarizeUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeDiarize(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int,
        minSpeakers: Int,
        maxSpeakers: Int
    ): String?

    @JvmStatic
    external fun nativeDiarizeCancel(handle: Long)

    // =============================================================================
    // Utility
    // =============================================================================

    @JvmStatic
    external fun nativeGetLastError(): String

    @JvmStatic
    external fun nativeGetVersion(): String

    @JvmStatic
    external fun nativeExtractArchive(archivePath: String, destDir: String): Int

    // =============================================================================
    // Library Loading with RTLD_GLOBAL
    // =============================================================================

    /**
     * Load a native library with RTLD_GLOBAL flag to make symbols globally visible.
     * This is required for ONNX Runtime so that dependent libraries can find its symbols.
     *
     * @param libraryName The library name without "lib" prefix and ".so" suffix
     * @return true if loaded successfully, false otherwise
     */
    @JvmStatic
    private external fun nativeLoadLibraryWithGlobal(libraryName: String): Boolean
}
