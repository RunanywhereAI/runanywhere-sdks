package com.runanywhere.sdk.features.tts

/**
 * Typed errors for Text-to-Speech operations.
 * Mirrors iOS TTSError enum exactly.
 */
sealed class TTSError : Exception() {

    // MARK: - Initialization Errors

    /** Service not initialized before use */
    data object NotInitialized : TTSError() {
        private fun readResolve(): Any = NotInitialized
        override val message: String = "TTS service not initialized. Call initialize() first."
    }

    /** Service failed to initialize */
    data class InitializationFailed(val underlying: Throwable) : TTSError() {
        override val message: String = "TTS initialization failed: ${underlying.message}"
        override val cause: Throwable = underlying
    }

    /** No provider found for the requested voice/model */
    data class NoProviderFound(val voiceId: String) : TTSError() {
        override val message: String = "No TTS provider found for voice: $voiceId"
    }

    /** Model/voice file not found at path */
    data class ModelNotFound(val path: String) : TTSError() {
        override val message: String = "TTS model not found at: $path"
    }

    // MARK: - Configuration Errors

    /** Invalid configuration provided */
    data class InvalidConfiguration(val reason: String) : TTSError() {
        override val message: String = "Invalid TTS configuration: $reason"
    }

    /** Invalid speaking rate (must be 0.5-2.0) */
    data class InvalidSpeakingRate(val value: Float) : TTSError() {
        override val message: String = "Invalid speaking rate: $value. Must be between 0.5 and 2.0."
    }

    /** Invalid pitch (must be 0.5-2.0) */
    data class InvalidPitch(val value: Float) : TTSError() {
        override val message: String = "Invalid pitch: $value. Must be between 0.5 and 2.0."
    }

    /** Invalid volume (must be 0.0-1.0) */
    data class InvalidVolume(val value: Float) : TTSError() {
        override val message: String = "Invalid volume: $value. Must be between 0.0 and 1.0."
    }

    // MARK: - Input Errors

    /** Empty text provided for synthesis */
    data object EmptyText : TTSError() {
        private fun readResolve(): Any = EmptyText
        override val message: String = "Cannot synthesize empty text."
    }

    /** Text too long for synthesis */
    data class TextTooLong(val maxCharacters: Int, val received: Int) : TTSError() {
        override val message: String = "Text too long. Maximum $maxCharacters characters allowed, received $received."
    }

    /** Invalid SSML markup */
    data class InvalidSSML(val reason: String) : TTSError() {
        override val message: String = "Invalid SSML markup: $reason"
    }

    // MARK: - Runtime Errors

    /** Synthesis failed */
    data class SynthesisFailed(val reason: String) : TTSError() {
        override val message: String = "TTS synthesis failed: $reason"
    }

    /** Voice not available */
    data class VoiceNotAvailable(val voiceId: String) : TTSError() {
        override val message: String = "Voice not available: $voiceId"
    }

    /** Language not supported */
    data class LanguageNotSupported(val language: String) : TTSError() {
        override val message: String = "Language not supported: $language"
    }

    /** Audio format not supported */
    data class AudioFormatNotSupported(val format: String) : TTSError() {
        override val message: String = "Audio format not supported: $format"
    }

    // MARK: - Resource Errors

    /** Insufficient memory for synthesis */
    data class InsufficientMemory(val required: Long, val available: Long) : TTSError() {
        override val message: String = "Insufficient memory. Required: $required bytes, Available: $available bytes"
    }

    /** Operation cancelled */
    data object Cancelled : TTSError() {
        private fun readResolve(): Any = Cancelled
        override val message: String = "TTS operation was cancelled"
    }

    /** Service is busy with another operation */
    data object Busy : TTSError() {
        private fun readResolve(): Any = Busy
        override val message: String = "TTS service is busy with another operation"
    }
}
