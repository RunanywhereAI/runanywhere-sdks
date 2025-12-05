package com.runanywhere.sdk.capabilities.device.services

import com.runanywhere.sdk.capabilities.device.PlatformSystemInfo
import com.runanywhere.sdk.capabilities.device.PerformanceTier
import com.runanywhere.sdk.capabilities.device.ProcessorEfficiency
import com.runanywhere.sdk.capabilities.device.ProcessorFeature
import com.runanywhere.sdk.capabilities.device.ProcessorInfo

/**
 * JVM/Android shared implementation of ProcessorDetector
 *
 * Uses JVM Runtime and system properties for processor detection.
 * Android-specific code can extend this with Build.HARDWARE, Build.SUPPORTED_ABIS, etc.
 */
open class JvmAndroidProcessorDetector : ProcessorDetector {

    override fun detectProcessorInfo(): ProcessorInfo {
        val coreCount = PlatformSystemInfo.getAvailableProcessors()

        // Estimate performance/efficiency cores based on total count
        val performanceCores = maxOf(1, coreCount / 2)
        val efficiencyCores = coreCount - performanceCores

        val architecture = detectArchitecture()

        return ProcessorInfo(
            chipName = getProcessorName(),
            coreCount = coreCount,
            performanceCores = performanceCores,
            efficiencyCores = efficiencyCores,
            architecture = architecture,
            hasARM64E = architecture.contains("aarch64", ignoreCase = true),
            clockFrequency = 0.0, // Not easily available on JVM
            neuralEngineCores = 0, // No Neural Engine on standard JVM
            estimatedTops = 0f
        )
    }

    override fun getProcessorEfficiency(): ProcessorEfficiency {
        val coreCount = PlatformSystemInfo.getAvailableProcessors()

        return when {
            coreCount >= 8 -> ProcessorEfficiency.HIGH
            coreCount >= 4 -> ProcessorEfficiency.MEDIUM
            else -> ProcessorEfficiency.LOW
        }
    }

    override fun getSupportedFeatures(): List<ProcessorFeature> {
        val features = mutableListOf<ProcessorFeature>()
        val arch = detectArchitecture()

        when {
            arch.contains("aarch64", ignoreCase = true) ||
            arch.contains("arm64", ignoreCase = true) -> {
                features.add(ProcessorFeature.NEON)
                features.add(ProcessorFeature.VECTOR_UNIT)
            }
            arch.contains("x86_64", ignoreCase = true) ||
            arch.contains("amd64", ignoreCase = true) -> {
                features.add(ProcessorFeature.SSE)
                // AVX detection would require native code or CPUID
                // Conservative: assume AVX available on x86_64
                features.add(ProcessorFeature.AVX)
            }
        }

        return features
    }

    private fun detectArchitecture(): String {
        return PlatformSystemInfo.getArchitecture()
    }

    private fun getProcessorName(): String {
        // On JVM, getting processor name requires native code or /proc/cpuinfo on Linux
        val osName = PlatformSystemInfo.getOSName()
        val arch = detectArchitecture()
        return "$osName $arch Processor"
    }
}

/**
 * Factory function for creating ProcessorDetector on JVM/Android
 */
actual fun createProcessorDetector(): ProcessorDetector {
    return JvmAndroidProcessorDetector()
}
