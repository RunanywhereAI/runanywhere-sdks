package com.runanywhere.sdk.features.tts

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.runanywhere.sdk.data.models.ModelInfo
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Android Text-to-Speech service implementation
 * Matches iOS TTSService functionality and implements the common TTSService interface
 *
 * Features:
 * - Full parity with iOS SystemTTSService
 * - Structured TTSOptions support
 * - Voice management with TTSVoice objects
 * - Flow-based streaming synthesis
 * - Comprehensive error handling
 * - Audio file generation support
 */
class AndroidTTSService(
    private val context: Context,
) : TTSService {
    private val logger = SDKLogger("AndroidTTSService")
    private var textToSpeech: TextToSpeech? = null
    private var isInitialized = false
    private var _isSynthesizing = false
    private val availableTTSVoices = mutableListOf<TTSVoice>()

    override val inferenceFramework: String = "android-tts"
    private val synthesisLock = Mutex()

    /**
     * Initialize the TTS engine (iOS equivalent)
     */
    override suspend fun initialize() =
        suspendCancellableCoroutine { cont ->
            logger.info("Initializing Android TTS service")

            textToSpeech =
                TextToSpeech(context) { status ->
                    if (status == TextToSpeech.SUCCESS) {
                        try {
                            // Set language to US English by default
                            val result = textToSpeech?.setLanguage(Locale.US)

                            isInitialized = result != TextToSpeech.LANG_MISSING_DATA &&
                                result != TextToSpeech.LANG_NOT_SUPPORTED

                            if (!isInitialized) {
                                cont.resumeWithException(SDKError.ComponentFailure("Language not supported"))
                                return@TextToSpeech
                            }

                            // Configure TTS parameters
                            textToSpeech?.apply {
                                setSpeechRate(1.0f) // Normal speed
                                setPitch(1.0f) // Normal pitch
                            }

                            // Load available voices
                            loadAvailableVoices()

                            logger.info("Android TTS service initialized with ${availableTTSVoices.size} voices")
                            cont.resume(Unit)
                        } catch (e: Exception) {
                            isInitialized = false
                            logger.error("Failed to initialize TTS", e)
                            cont.resumeWithException(e)
                        }
                    } else {
                        isInitialized = false
                        logger.error("TTS initialization failed with status: $status")
                        cont.resumeWithException(SDKError.ComponentFailure("TTS initialization failed"))
                    }
                }

            cont.invokeOnCancellation {
                textToSpeech?.shutdown()
            }
        }

    /**
     * iOS-style synthesize method with TTSOptions
     * Matches: func synthesize(text: String, options: TTSOptions) async throws -> Data
     */
    override suspend fun synthesize(
        text: String,
        options: TTSOptions,
    ): ByteArray {
        if (!isInitialized) {
            throw SDKError.ComponentNotReady("TTS service not initialized")
        }

        return synthesisLock.withLock {
            _isSynthesizing = true
            try {
                withContext(Dispatchers.IO) {
                    synthesizeToByteArray(text, options)
                }
            } finally {
                _isSynthesizing = false
            }
        }
    }

    /**
     * Streaming synthesis using Flow
     */
    override fun synthesizeStream(
        text: String,
        options: TTSOptions,
    ): Flow<ByteArray> =
        flow {
            if (!isInitialized) {
                throw SDKError.ComponentNotReady("TTS service not initialized")
            }

            _isSynthesizing = true
            try {
                logger.debug("Starting Flow-based streaming synthesis")

                // Split text into sentences and synthesize each
                val sentences = text.split(Regex("[.!?]+")).filter { it.trim().isNotEmpty() }

                for (sentence in sentences) {
                    val audioData = synthesize(sentence.trim(), options)
                    if (audioData.isNotEmpty()) {
                        emit(audioData)
                    }
                    delay(100)
                }
            } finally {
                _isSynthesizing = false
            }
        }

    /**
     * Stop current synthesis (iOS equivalent)
     */
    override fun stop() {
        textToSpeech?.stop()
        _isSynthesizing = false
        logger.debug("TTS synthesis stopped")
    }

    /**
     * Get available voices (iOS-style string identifiers)
     */
    override val availableVoices: List<String>
        get() = availableTTSVoices.map { it.id }

    /**
     * Get available voice IDs
     */
    fun getAllVoices(): List<TTSVoice> = availableTTSVoices.toList()

    /**
     * Check if currently synthesizing
     */
    override val isSynthesizing: Boolean
        get() = _isSynthesizing

    /**
     * Cleanup resources
     */
    override suspend fun cleanup() {
        withContext(Dispatchers.Main) {
            textToSpeech?.stop()
            textToSpeech?.shutdown()
            textToSpeech = null
            isInitialized = false
            _isSynthesizing = false
            availableTTSVoices.clear()
            logger.info("Android TTS service cleaned up")
        }
    }

    // MARK: - Private Helper Methods

    /**
     * Load available voices from Android TTS engine
     */
    private fun loadAvailableVoices() {
        availableTTSVoices.clear()

        textToSpeech?.voices?.forEach { voice ->
            // Only include local voices (not network-dependent)
            if (!voice.isNetworkConnectionRequired) {
                val ttsVoice =
                    TTSVoice(
                        id = voice.name,
                        name = voice.name,
                        language = voice.locale.toString(),
                        gender =
                            when {
                                voice.name.contains("female", ignoreCase = true) -> TTSGender.FEMALE
                                voice.name.contains("male", ignoreCase = true) -> TTSGender.MALE
                                else -> TTSGender.NEUTRAL
                            },
                    )
                availableTTSVoices.add(ttsVoice)
            }
        }

        // Add default voice if none found
        if (availableTTSVoices.isEmpty()) {
            availableTTSVoices.add(TTSVoice.DEFAULT)
        }

        logger.debug("Loaded ${availableTTSVoices.size} TTS voices")
    }

    /**
     * Configure TTS engine with options
     */
    private fun configureTTSEngine(options: TTSOptions) {
        textToSpeech?.apply {
            // Set speech rate (0.5 to 2.0)
            setSpeechRate(options.rate.coerceIn(0.5f, 2.0f))

            // Set pitch (0.5 to 2.0)
            setPitch(options.pitch.coerceIn(0.5f, 2.0f))

            // Set language
            try {
                val locale = parseLocale(options.language)
                val result = setLanguage(locale)
                if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                    logger.warn("Language ${options.language} not fully supported, using default")
                }
            } catch (e: Exception) {
                logger.warn("Failed to set language: ${options.language}")
            }

            // Set voice if specified (iOS pattern: voice is optional string ID)
            options.voice?.let { voiceId ->
                setVoiceById(voiceId)
            }
        }
    }

    /**
     * Set voice by ID
     */
    private fun setVoiceById(voiceId: String) {
        try {
            val voice = textToSpeech?.voices?.find { it.name == voiceId }
            if (voice != null) {
                textToSpeech?.voice = voice
                logger.debug("Set voice to: ${voice.name}")
            } else {
                logger.warn("Voice '$voiceId' not found, using default")
            }
        } catch (e: Exception) {
            logger.warn("Failed to set voice: $voiceId")
        }
    }

    /**
     * Parse locale string to Locale object
     */
    private fun parseLocale(language: String): Locale =
        try {
            val parts = language.split("-", "_")
            when (parts.size) {
                1 -> Locale(parts[0])
                2 -> Locale(parts[0], parts[1])
                else -> Locale.US
            }
        } catch (e: Exception) {
            logger.warn("Failed to parse locale: $language, using US")
            Locale.US
        }

    /**
     * Synthesize text to byte array (audio data)
     */
    private suspend fun synthesizeToByteArray(
        text: String,
        options: TTSOptions,
    ): ByteArray =
        suspendCancellableCoroutine { cont ->
            try {
                // Configure TTS engine with options
                configureTTSEngine(options)

                // Create temporary file for audio output
                val outputFile = createTempFile("tts_android_", ".wav", context.cacheDir)

                val utteranceId = "tts_${System.currentTimeMillis()}"

                // Set up utterance listener
                textToSpeech?.setOnUtteranceProgressListener(
                    object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {
                            logger.debug("TTS synthesis started for utterance: $utteranceId")
                        }

                        override fun onDone(utteranceId: String?) {
                            try {
                                // Read the generated audio file
                                if (outputFile.exists() && outputFile.length() > 0) {
                                    val audioData = outputFile.readBytes()
                                    outputFile.delete()
                                    logger.debug("TTS synthesis completed: ${audioData.size} bytes")
                                    cont.resume(audioData)
                                } else {
                                    logger.error("TTS output file is empty or doesn't exist")
                                    cont.resumeWithException(SDKError.ComponentFailure("TTS failed to generate audio"))
                                }
                            } catch (e: Exception) {
                                logger.error("Error reading TTS output", e)
                                cont.resumeWithException(e)
                            }
                        }

                        override fun onError(utteranceId: String?) {
                            outputFile.delete()
                            logger.error("TTS synthesis error for utterance: $utteranceId")
                            cont.resumeWithException(SDKError.ComponentFailure("TTS synthesis failed"))
                        }

                        @Deprecated("Deprecated in Java")
                        override fun onError(
                            utteranceId: String?,
                            errorCode: Int,
                        ) {
                            outputFile.delete()
                            logger.error("TTS synthesis error for utterance: $utteranceId, code: $errorCode")
                            cont.resumeWithException(SDKError.ComponentFailure("TTS synthesis failed with code: $errorCode"))
                        }
                    },
                )

                // Synthesize to file
                val params =
                    Bundle().apply {
                        putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
                    }

                val result = textToSpeech?.synthesizeToFile(text, params, outputFile, utteranceId)

                if (result != TextToSpeech.SUCCESS) {
                    outputFile.delete()
                    cont.resumeWithException(SDKError.ComponentFailure("Failed to start TTS synthesis"))
                }

                cont.invokeOnCancellation {
                    textToSpeech?.stop()
                    outputFile.delete()
                }
            } catch (e: Exception) {
                logger.error("Error in TTS synthesis", e)
                cont.resumeWithException(e)
            }
        }

    /**
     * Create temporary file with automatic cleanup
     */
    private fun createTempFile(
        prefix: String,
        suffix: String,
        directory: File,
    ): File =
        File.createTempFile(prefix, suffix, directory).apply {
            deleteOnExit()
        }
}

/**
 * Android TTS Service Provider for integration with ModuleRegistry
 * Follows the same pattern as LLMServiceProvider and STTServiceProvider
 */
class AndroidTTSServiceProvider(
    private val context: Context,
) : com.runanywhere.sdk.core.TTSServiceProvider {
    override suspend fun createTTSService(configuration: TTSConfiguration): TTSService {
        val service = AndroidTTSService(context)
        service.initialize()
        return service
    }

    override fun canHandle(voiceId: String): Boolean {
        // Android TTS can handle system TTS requests
        return voiceId.startsWith("system") || voiceId == "default" || voiceId == "android-tts"
    }

    override val name: String = "AndroidTTSProvider"

    override val framework: com.runanywhere.sdk.models.enums.InferenceFramework =
        com.runanywhere.sdk.models.enums.InferenceFramework.SYSTEM_TTS
}
