package com.runanywhere.whisperkit.service

/**
 * JVM-specific actual implementation of WhisperKitFactory
 */
actual object WhisperKitFactory {
    actual fun createService(): WhisperKitService {
        return JvmWhisperKitService()
    }
}
