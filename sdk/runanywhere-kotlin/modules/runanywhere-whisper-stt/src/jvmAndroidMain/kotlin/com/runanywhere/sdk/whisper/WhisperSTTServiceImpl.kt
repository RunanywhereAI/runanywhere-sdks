package com.runanywhere.sdk.whisper

import com.runanywhere.sdk.components.stt.WhisperSTTService

/**
 * Platform-specific implementation that delegates to the actual WhisperSTTService
 * This allows the provider to be in commonMain while the actual implementation is platform-specific
 */
actual class WhisperSTTServiceImpl : WhisperSTTService()
