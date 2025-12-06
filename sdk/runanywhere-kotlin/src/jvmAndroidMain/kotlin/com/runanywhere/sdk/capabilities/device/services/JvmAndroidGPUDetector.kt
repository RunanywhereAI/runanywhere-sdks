package com.runanywhere.sdk.capabilities.device.services

import com.runanywhere.sdk.capabilities.device.GPUCapabilities
import com.runanywhere.sdk.capabilities.device.PlatformSystemInfo

/**
 * JVM/Android shared implementation of GPUDetector
 *
 * Note: GPU detection on pure JVM is limited without native bindings.
 * Android-specific code can extend this with OpenGL ES information.
 */
open class JvmAndroidGPUDetector : GPUDetector {

    override fun hasGPU(): Boolean {
        // Assume GPU is available on most modern systems
        // Android can override with actual EGL/OpenGL check
        return true
    }

    override fun getGPUCapabilities(): GPUCapabilities? {
        if (!hasGPU()) return null

        // Return basic capabilities
        // Android can override with actual OpenGL ES info
        return GPUCapabilities.basic(
            name = "Unknown GPU",
            family = getGPUFamily() ?: "Unknown"
        )
    }

    override fun getGPUFamily(): String? {
        // Determining GPU family requires native code or platform-specific APIs
        // Android can override with GLES info
        val arch = System.getProperty("os.arch") ?: ""

        return when {
            arch.contains("aarch64", ignoreCase = true) -> "Mobile GPU"
            arch.contains("x86_64", ignoreCase = true) -> "Desktop GPU"
            else -> null
        }
    }

    override fun supportsML(): Boolean {
        // Conservative: assume ML support on modern GPUs
        // Android can check for specific extensions
        return hasGPU()
    }

    override fun getGPUMemory(): Long {
        if (!hasGPU()) return 0L

        // On systems with unified memory (like ARM), GPU shares system memory
        // On discrete GPU systems, this would need native code to determine
        val arch = System.getProperty("os.arch") ?: ""

        return if (arch.contains("aarch64", ignoreCase = true) ||
                   arch.contains("arm", ignoreCase = true)) {
            // Unified memory - return a portion of system memory
            PlatformSystemInfo.getMaxMemory() / 2
        } else {
            // Discrete GPU - return conservative estimate (2GB)
            2_000_000_000L
        }
    }
}

/**
 * Factory function for creating GPUDetector on JVM/Android
 */
actual fun createGPUDetector(): GPUDetector {
    return JvmAndroidGPUDetector()
}
