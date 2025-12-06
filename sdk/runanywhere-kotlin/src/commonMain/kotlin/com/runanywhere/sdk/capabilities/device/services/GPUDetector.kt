package com.runanywhere.sdk.capabilities.device.services

import com.runanywhere.sdk.capabilities.device.GPUCapabilities

/**
 * Detects GPU capabilities
 *
 * Matches iOS: Capabilities/DeviceCapability/Services/GPUDetector.swift
 *
 * Platform-specific implementations:
 * - Android: Uses OpenGL ES information
 * - JVM: May use OpenGL or return null
 */
interface GPUDetector {
    /**
     * Check if GPU is available
     *
     * @return true if GPU is available, false otherwise
     */
    fun hasGPU(): Boolean

    /**
     * Get GPU capabilities
     *
     * @return GPUCapabilities if available, null otherwise
     */
    fun getGPUCapabilities(): GPUCapabilities?

    /**
     * Get GPU family name
     *
     * @return GPU family string if available, null otherwise
     */
    fun getGPUFamily(): String?

    /**
     * Check if GPU supports machine learning operations
     *
     * @return true if GPU supports ML ops, false otherwise
     */
    fun supportsML(): Boolean

    /**
     * Get estimated GPU memory in bytes
     *
     * @return GPU memory estimate, 0 if unknown
     */
    fun getGPUMemory(): Long
}

/**
 * Factory for creating platform-specific GPUDetector instances
 */
expect fun createGPUDetector(): GPUDetector
