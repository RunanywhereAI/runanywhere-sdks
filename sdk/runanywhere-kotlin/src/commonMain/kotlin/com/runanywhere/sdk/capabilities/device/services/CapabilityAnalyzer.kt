package com.runanywhere.sdk.capabilities.device.services

import com.runanywhere.sdk.capabilities.device.DeviceCapabilities
import com.runanywhere.sdk.capabilities.device.HardwareAcceleration
import com.runanywhere.sdk.capabilities.device.HardwareConfiguration
import com.runanywhere.sdk.capabilities.device.MemoryMode
import com.runanywhere.sdk.capabilities.device.OperatingSystemVersion
import com.runanywhere.sdk.capabilities.device.PlatformSystemInfo
import com.runanywhere.sdk.capabilities.device.ProcessorType
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.device.DeviceInfoService
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * Analyzes hardware capabilities and makes optimization recommendations
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/CapabilityAnalyzer.swift
 */
class CapabilityAnalyzer(
    private val processorDetector: ProcessorDetector = createProcessorDetector(),
    private val neuralEngineDetector: NeuralEngineDetector = createNeuralEngineDetector(),
    private val gpuDetector: GPUDetector = createGPUDetector()
) {
    private val logger = SDKLogger("CapabilityAnalyzer")
    private val deviceInfoService = DeviceInfoService()

    /**
     * Analyze complete device capabilities
     */
    fun analyzeCapabilities(): DeviceCapabilities {
        logger.debug("Analyzing device capabilities")

        val processorInfo = processorDetector.detectProcessorInfo()
        val hasNeuralEngine = neuralEngineDetector.hasNeuralEngine()
        val hasGPU = gpuDetector.hasGPU()

        val totalMemory = getTotalMemory()
        val availableMemory = getAvailableMemory()

        val supportedAccelerators = determineSupportedAccelerators(
            hasNeuralEngine = hasNeuralEngine,
            hasGPU = hasGPU
        )

        val capabilities = DeviceCapabilities(
            totalMemory = totalMemory,
            availableMemory = availableMemory,
            hasNeuralEngine = hasNeuralEngine,
            hasGPU = hasGPU,
            processorCount = processorInfo.coreCount,
            processorType = mapToProcessorType(processorInfo),
            supportedAccelerators = supportedAccelerators,
            osVersion = getOSVersion(),
            modelIdentifier = getDeviceIdentifier()
        )

        logger.info("Device capabilities: ${processorInfo.coreCount} cores, ${if (hasNeuralEngine) "Neural Engine" else "No Neural Engine"}, ${if (hasGPU) "GPU" else "No GPU"}")

        return capabilities
    }

    /**
     * Get optimal hardware configuration for a model
     */
    fun getOptimalConfiguration(model: ModelInfo): HardwareConfiguration {
        val capabilities = analyzeCapabilities()

        val primaryAccelerator = selectPrimaryAccelerator(model, capabilities)
        val memoryMode = selectMemoryMode(model, capabilities)
        val threadCount = selectThreadCount(model, capabilities)

        return HardwareConfiguration(
            primaryAccelerator = primaryAccelerator,
            memoryMode = memoryMode,
            threadCount = threadCount
        )
    }

    // MARK: - Private Methods

    private fun getTotalMemory(): Long {
        return PlatformSystemInfo.getMaxMemory()
    }

    private fun getAvailableMemory(): Long {
        return PlatformSystemInfo.getFreeMemory()
    }

    private fun determineSupportedAccelerators(
        hasNeuralEngine: Boolean,
        hasGPU: Boolean
    ): List<HardwareAcceleration> {
        val accelerators = mutableListOf(HardwareAcceleration.CPU)

        if (hasGPU) {
            accelerators.add(HardwareAcceleration.GPU)
            accelerators.add(HardwareAcceleration.METAL)
        }

        if (hasNeuralEngine) {
            accelerators.add(HardwareAcceleration.NEURAL_ENGINE)
            accelerators.add(HardwareAcceleration.CORE_ML)
        }

        return accelerators
    }

    private fun mapToProcessorType(processorInfo: com.runanywhere.sdk.capabilities.device.ProcessorInfo): ProcessorType {
        return when {
            processorInfo.architecture.contains("ARM", ignoreCase = true) ||
            processorInfo.architecture.contains("arm", ignoreCase = true) -> ProcessorType.ARM
            processorInfo.architecture.contains("x86", ignoreCase = true) -> ProcessorType.INTEL
            else -> ProcessorType.UNKNOWN
        }
    }

    private fun getDeviceIdentifier(): String {
        val model = deviceInfoService.getDeviceModel()
        val osVersion = deviceInfoService.getOSVersion()
        return "$model-$osVersion"
    }

    private fun getOSVersion(): OperatingSystemVersion {
        val versionString = deviceInfoService.getOSVersion()
        return OperatingSystemVersion.parse(versionString)
    }

    private fun selectPrimaryAccelerator(
        model: ModelInfo,
        capabilities: DeviceCapabilities
    ): HardwareAcceleration {
        val memoryRequired = model.memoryRequired ?: 0L

        // Large models with Neural Engine support
        if (memoryRequired > 3_000_000_000L && capabilities.hasNeuralEngine) {
            if (model.format == ModelFormat.MLMODEL || model.format == ModelFormat.MLPACKAGE) {
                return HardwareAcceleration.NEURAL_ENGINE
            }
        }

        // GPU for medium to large models
        if (capabilities.hasGPU && memoryRequired > 1_000_000_000L) {
            return HardwareAcceleration.GPU
        }

        // Check framework preferences
        model.preferredFramework?.let { preferred ->
            when (preferred) {
                LLMFramework.CORE_ML -> if (capabilities.hasNeuralEngine) {
                    return HardwareAcceleration.NEURAL_ENGINE
                }
                LLMFramework.TENSOR_FLOW_LITE -> if (capabilities.hasGPU) {
                    return HardwareAcceleration.GPU
                }
                LLMFramework.MLX -> if (capabilities.hasGPU) {
                    return HardwareAcceleration.METAL
                }
                else -> { /* fallthrough */ }
            }
        }

        return HardwareAcceleration.AUTO
    }

    private fun selectMemoryMode(
        model: ModelInfo,
        capabilities: DeviceCapabilities
    ): MemoryMode {
        val availableMemory = capabilities.availableMemory
        val modelMemory = model.memoryRequired ?: 0L

        return when {
            availableMemory < modelMemory * 2 -> MemoryMode.CONSERVATIVE
            availableMemory > modelMemory * 4 && capabilities.totalMemory > 8_000_000_000L ->
                MemoryMode.AGGRESSIVE
            else -> MemoryMode.BALANCED
        }
    }

    private fun selectThreadCount(
        model: ModelInfo,
        capabilities: DeviceCapabilities
    ): Int {
        val processorCount = capabilities.processorCount
        val memoryRequired = model.memoryRequired ?: 0L

        return when {
            memoryRequired > 2_000_000_000L -> processorCount
            memoryRequired < 500_000_000L -> maxOf(1, processorCount / 2)
            else -> maxOf(1, (processorCount * 0.75).toInt())
        }
    }
}
