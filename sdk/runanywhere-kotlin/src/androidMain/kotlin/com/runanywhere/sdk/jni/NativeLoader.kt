package com.runanywhere.sdk.jni

import java.io.File

/**
 * Native library loader for platform-specific libraries
 * Shared between JVM and Android
 */
object NativeLoader {
    private val loadedLibraries = mutableSetOf<String>()

    /**
     * Load a native library from resources
     */
    fun loadLibrary(libName: String) {
        if (libName in loadedLibraries) return

        val os = System.getProperty("os.name").lowercase()
        val arch = System.getProperty("os.arch").lowercase()

        val libFileName = when {
            os.contains("win") -> "$libName.dll"
            os.contains("mac") -> "lib$libName.dylib"
            else -> "lib$libName.so"
        }

        val platformDir = when {
            os.contains("win") -> "win"
            os.contains("mac") -> "mac"
            else -> "linux"
        }

        val resourcePath = "/native/$platformDir/$libFileName"

        try {
            // Try to load from resources
            val resource = NativeLoader::class.java.getResourceAsStream(resourcePath)

            if (resource != null) {
                val tempFile = File.createTempFile(libName, libFileName)
                tempFile.deleteOnExit()

                resource.use { input ->
                    tempFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }

                System.load(tempFile.absolutePath)
                loadedLibraries.add(libName)
            } else {
                // Fallback to system library
                System.loadLibrary(libName)
                loadedLibraries.add(libName)
            }
        } catch (e: Exception) {
            throw UnsatisfiedLinkError("Failed to load native library $libName: ${e.message}")
        }
    }

    /**
     * Check if a library is already loaded
     */
    fun isLibraryLoaded(libName: String): Boolean {
        return libName in loadedLibraries
    }
}
