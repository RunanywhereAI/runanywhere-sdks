package com.runanywhere.sdk.capabilities.device.services

import com.runanywhere.sdk.capabilities.device.ProcessorEfficiency
import com.runanywhere.sdk.capabilities.device.ProcessorFeature
import com.runanywhere.sdk.capabilities.device.ProcessorInfo

/**
 * Detects processor information and capabilities
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/ProcessorDetector.swift
 *
 * Platform-specific implementations:
 * - Android: Uses Build.HARDWARE, Build.SUPPORTED_ABIS
 * - JVM: Uses Runtime and system properties
 */
interface ProcessorDetector {
    /**
     * Detect processor information
     *
     * @return ProcessorInfo with detailed CPU information
     */
    fun detectProcessorInfo(): ProcessorInfo

    /**
     * Get processor efficiency rating
     *
     * @return ProcessorEfficiency tier (HIGH, MEDIUM, LOW)
     */
    fun getProcessorEfficiency(): ProcessorEfficiency

    /**
     * Get supported processor features
     *
     * @return List of supported ProcessorFeature capabilities
     */
    fun getSupportedFeatures(): List<ProcessorFeature>
}

/**
 * Factory for creating platform-specific ProcessorDetector instances
 */
expect fun createProcessorDetector(): ProcessorDetector
