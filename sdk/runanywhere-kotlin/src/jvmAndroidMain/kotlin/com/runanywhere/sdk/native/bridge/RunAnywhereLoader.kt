package com.runanywhere.sdk.native.bridge

import java.io.File

/**
 * RunAnywhere Library Loader
 *
 * This object provides functionality to load native libraries with RTLD_GLOBAL.
 * It uses a minimal native library (librunanywhere_loader.so) that has NO dependencies,
 * so it can always be loaded first.
 *
 * Purpose:
 * When loading ONNX libraries on Android, libsherpa-onnx-c-api.so needs OrtGetApiBase
 * from libonnxruntime.so. Android's System.loadLibrary() doesn't use RTLD_GLOBAL,
 * and uses a different linker namespace than native dlopen().
 *
 * This loader solves the problem by loading ALL libraries from native code using
 * dlopen() with RTLD_GLOBAL, ensuring they're in the same namespace and symbols
 * are globally visible.
 */
object RunAnywhereLoader {

    private const val TAG = "RunAnywhereLoader"
    private var isLoaded = false
    private var nativeLibDir: File? = null

    /**
     * Initialize the loader by loading the native library and setting the library directory.
     * @param libraryDir The native library directory (from context.applicationInfo.nativeLibraryDir)
     */
    @Synchronized
    fun initialize(libraryDir: String): Boolean {
        if (isLoaded) return true

        nativeLibDir = File(libraryDir)

        return try {
            System.loadLibrary("runanywhere_loader")
            nativeSetLibraryDir(libraryDir)
            isLoaded = true
            println("I/$TAG: Loader initialized with library dir: $libraryDir")
            true
        } catch (e: UnsatisfiedLinkError) {
            nativeLibDir = null
            println("E/$TAG: Failed to load loader library: ${e.message}")
            false
        }
    }

    /**
     * Check if the loader is initialized.
     */
    fun isInitialized(): Boolean = isLoaded

    /**
     * Get the currently configured native library directory.
     */
    fun getNativeLibraryDir(): String? = nativeLibDir?.absolutePath

    /**
     * Check if a native library exists inside the configured directory.
     */
    fun hasLibrary(libraryName: String): Boolean {
        val dir = nativeLibDir ?: return false
        return File(dir, "lib$libraryName.so").exists()
    }

    /**
     * Load a single native library with RTLD_GLOBAL flag.
     */
    fun loadLibraryGlobal(libraryName: String): Boolean {
        if (!isLoaded) {
            println("E/$TAG: Loader not initialized")
            return false
        }

        return try {
            val result = nativeLoadLibraryGlobal(libraryName)
            if (result) {
                println("I/$TAG: Loaded lib$libraryName.so with RTLD_GLOBAL")
            } else {
                println("E/$TAG: Failed to load lib$libraryName.so")
            }
            result
        } catch (e: Exception) {
            println("E/$TAG: Exception loading lib$libraryName.so: ${e.message}")
            false
        }
    }

    /**
     * Load all ONNX-related libraries in the correct order.
     * This loads: onnxruntime -> sherpa-onnx-c-api -> runanywhere_bridge -> runanywhere_jni
     */
    fun loadOnnxLibraries(): Boolean {
        if (!isLoaded) {
            println("E/$TAG: Loader not initialized")
            return false
        }

        return try {
            val result = nativeLoadOnnxLibraries()
            if (result) {
                println("I/$TAG: All ONNX libraries loaded successfully")
            } else {
                println("E/$TAG: Failed to load ONNX libraries")
            }
            result
        } catch (e: Exception) {
            println("E/$TAG: Exception loading ONNX libraries: ${e.message}")
            false
        }
    }

    // Native methods
    @JvmStatic
    private external fun nativeSetLibraryDir(libraryDir: String)

    @JvmStatic
    private external fun nativeLoadLibraryGlobal(libraryName: String): Boolean

    @JvmStatic
    private external fun nativeLoadOnnxLibraries(): Boolean
}
