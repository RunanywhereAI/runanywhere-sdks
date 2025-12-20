package com.runanywhere.sdk.features.vad

/**
 * Platform-specific VAD service creation for JVM
 * Now uses the simplified SimpleEnergyVAD matching iOS behavior exactly
 *
 * This replaces the complex multi-algorithm approach with a single energy-based RMS detection
 * that matches iOS SimpleEnergyVAD implementation with:
 * - Same energy threshold defaults (0.022f)
 * - Same hysteresis parameters (voiceStartThreshold=2, voiceEndThreshold=10)
 * - Same RMS energy calculation
 * - Same speech activity events (STARTED/ENDED)
 */
actual fun createPlatformVADService(): VADService = SimpleEnergyVAD()
