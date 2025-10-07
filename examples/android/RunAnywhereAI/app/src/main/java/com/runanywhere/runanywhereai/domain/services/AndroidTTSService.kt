package com.runanywhere.runanywhereai.domain.services

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.*
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Android Text-to-Speech service implementation
 * Matches iOS TTSService functionality
 */
class AndroidTTSService(private val context: Context) {

    private var textToSpeech: TextToSpeech? = null
    private var isInitialized = false
    private var selectedVoice = "default"

    /**
     * Initialize the TTS engine
     */
    suspend fun initialize(voice: String = "default"): Boolean = suspendCancellableCoroutine { cont ->
        selectedVoice = voice

        textToSpeech = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                // Set language to US English by default
                val result = textToSpeech?.setLanguage(Locale.US)

                isInitialized = result != TextToSpeech.LANG_MISSING_DATA &&
                               result != TextToSpeech.LANG_NOT_SUPPORTED

                // Configure TTS parameters
                textToSpeech?.apply {
                    setSpeechRate(1.0f) // Normal speed
                    setPitch(1.0f) // Normal pitch
                }

                cont.resume(isInitialized)
            } else {
                isInitialized = false
                cont.resumeWithException(Exception("TTS initialization failed"))
            }
        }
    }

    /**
     * Speak the given text
     */
    fun speak(text: String, onComplete: (() -> Unit)? = null) {
        if (!isInitialized) {
            throw IllegalStateException("TTS not initialized")
        }

        val utteranceId = UUID.randomUUID().toString()

        textToSpeech?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}

            override fun onDone(utteranceId: String?) {
                onComplete?.invoke()
            }

            override fun onError(utteranceId: String?) {
                onComplete?.invoke()
            }
        })

        // Use the newer speak method for API 21+
        val params = android.os.Bundle().apply {
            putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
        }

        textToSpeech?.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
    }

    /**
     * Stop current speech
     */
    fun stop() {
        textToSpeech?.stop()
    }

    /**
     * Set speech rate (0.5 to 2.0)
     */
    fun setSpeechRate(rate: Float) {
        textToSpeech?.setSpeechRate(rate.coerceIn(0.5f, 2.0f))
    }

    /**
     * Set pitch (0.5 to 2.0)
     */
    fun setPitch(pitch: Float) {
        textToSpeech?.setPitch(pitch.coerceIn(0.5f, 2.0f))
    }

    /**
     * Get available voices
     */
    fun getAvailableVoices(): List<String> {
        val voices = mutableListOf<String>()

        textToSpeech?.voices?.forEach { voice ->
            if (!voice.isNetworkConnectionRequired &&
                voice.locale.language == Locale.US.language) {
                voices.add(voice.name)
            }
        }

        return voices.ifEmpty { listOf("default") }
    }

    /**
     * Set a specific voice
     */
    fun setVoice(voiceName: String) {
        val voice = textToSpeech?.voices?.find { it.name == voiceName }
        if (voice != null) {
            textToSpeech?.voice = voice
            selectedVoice = voiceName
        }
    }

    /**
     * Check if TTS is speaking
     */
    fun isSpeaking(): Boolean {
        return textToSpeech?.isSpeaking == true
    }

    /**
     * Clean up TTS resources
     */
    fun shutdown() {
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        isInitialized = false
    }
}
