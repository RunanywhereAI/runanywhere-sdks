package com.runanywhere.sdk.whisper

import com.runanywhere.sdk.components.stt.STTService

/**
 * Whisper STT service implementation
 * Platform-specific implementations provide the actual service
 */
expect class WhisperSTTServiceImpl() : STTService
