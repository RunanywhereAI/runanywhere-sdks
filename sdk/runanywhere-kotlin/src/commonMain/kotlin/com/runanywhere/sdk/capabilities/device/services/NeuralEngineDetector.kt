package com.runanywhere.sdk.capabilities.device.services

import com.runanywhere.sdk.capabilities.device.NeuralEngineCapabilities
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * Detects Neural Engine / hardware ML accelerator capabilities
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/NeuralEngineDetector.swift
 *
 * Platform-specific implementations:
 * - Android: Checks for NNAPI availability
 * - JVM: Returns false (no Neural Engine on desktop)
 */
interface NeuralEngineDetector {
    /**
     * Check if Neural Engine / hardware ML accelerator is available
     *
     * On Android, this checks for NNAPI support.
     * On iOS, this checks for Apple Neural Engine.
     * On JVM desktop, always returns false.
     *
     * @return true if ML accelerator is available, false otherwise
     */
    fun hasNeuralEngine(): Boolean

    /**
     * Get Neural Engine capabilities
     *
     * @return NeuralEngineCapabilities if available, null otherwise
     */
    fun getNeuralEngineCapabilities(): NeuralEngineCapabilities?

    /**
     * Check if model format is compatible with Neural Engine
     *
     * @param format The model format to check
     * @return true if compatible, false otherwise
     */
    fun isCompatible(format: ModelFormat): Boolean
}

/**
 * Factory for creating platform-specific NeuralEngineDetector instances
 */
expect fun createNeuralEngineDetector(): NeuralEngineDetector
