package com.runanywhere.sdk.capabilities.device.services

import com.runanywhere.sdk.capabilities.device.NeuralEngineCapabilities
import com.runanywhere.sdk.capabilities.device.NeuralEnginePrecision
import com.runanywhere.sdk.capabilities.device.NeuralEngineVersion
import com.runanywhere.sdk.capabilities.device.PlatformSystemInfo
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * JVM/Android shared implementation of NeuralEngineDetector
 *
 * Note: Neural Engine detection on pure JVM returns false.
 * Android-specific code can extend this to check for NNAPI availability.
 */
open class JvmAndroidNeuralEngineDetector : NeuralEngineDetector {

    override fun hasNeuralEngine(): Boolean {
        // Desktop JVM has no Neural Engine / NNAPI
        // Android can override with NNapi check (API 27+)
        return false
    }

    override fun getNeuralEngineCapabilities(): NeuralEngineCapabilities? {
        if (!hasNeuralEngine()) return null

        // If a subclass indicates Neural Engine is available, return capabilities
        return NeuralEngineCapabilities(
            version = detectNeuralEngineVersion(),
            operationsPerSecond = NeuralEngineCapabilities.estimatedOps(detectNeuralEngineVersion()),
            supportedPrecisions = listOf(NeuralEnginePrecision.INT8, NeuralEnginePrecision.FLOAT16),
            maxModelSize = NeuralEngineCapabilities.DEFAULT_MAX_MODEL_SIZE
        )
    }

    override fun isCompatible(format: ModelFormat): Boolean {
        if (!hasNeuralEngine()) return false

        // On Android with NNAPI, TFLite is the primary compatible format
        return when (format) {
            ModelFormat.TFLITE -> true
            ModelFormat.ONNX -> true // Some ONNX models can use NNAPI
            else -> false
        }
    }

    /**
     * Detect the Neural Engine version/generation
     * Subclasses can override for platform-specific detection
     */
    protected open fun detectNeuralEngineVersion(): NeuralEngineVersion {
        // Determine based on processor capabilities
        val coreCount = PlatformSystemInfo.getAvailableProcessors()

        return when {
            coreCount >= 10 -> NeuralEngineVersion.GENERATION_3
            coreCount >= 8 -> NeuralEngineVersion.GENERATION_2
            else -> NeuralEngineVersion.GENERATION_1
        }
    }
}

/**
 * Factory function for creating NeuralEngineDetector on JVM/Android
 */
actual fun createNeuralEngineDetector(): NeuralEngineDetector {
    return JvmAndroidNeuralEngineDetector()
}
