package com.runanywhere.agent.tts

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.Locale
import java.util.UUID
import kotlin.coroutines.resume

class TTSManager(context: Context) {
    companion object {
        private const val TAG = "TTSManager"
    }

    private var tts: TextToSpeech? = null
    private var isReady = false
    private val pendingCallbacks = mutableMapOf<String, (Boolean) -> Unit>()

    init {
        tts = TextToSpeech(context.applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val result = tts?.setLanguage(Locale.US)
                isReady = result != TextToSpeech.LANG_MISSING_DATA &&
                          result != TextToSpeech.LANG_NOT_SUPPORTED
                if (isReady) {
                    tts?.setSpeechRate(1.1f)
                    tts?.setPitch(1.0f)
                    Log.i(TAG, "TTS initialized")
                } else {
                    Log.e(TAG, "TTS language not supported")
                }
            } else {
                Log.e(TAG, "TTS init failed: $status")
            }
        }

        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) {
                utteranceId?.let { id ->
                    pendingCallbacks.remove(id)?.invoke(true)
                }
            }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                utteranceId?.let { id ->
                    pendingCallbacks.remove(id)?.invoke(false)
                }
            }
        })
    }

    fun speak(text: String) {
        if (!isReady) return
        val utteranceId = UUID.randomUUID().toString()
        tts?.speak(text, TextToSpeech.QUEUE_ADD, null, utteranceId)
    }

    suspend fun speakAndWait(text: String): Boolean {
        if (!isReady) return false
        return suspendCancellableCoroutine { cont ->
            val utteranceId = UUID.randomUUID().toString()
            pendingCallbacks[utteranceId] = { success -> cont.resume(success) }
            cont.invokeOnCancellation {
                pendingCallbacks.remove(utteranceId)
                tts?.stop()
            }
            tts?.speak(text, TextToSpeech.QUEUE_ADD, null, utteranceId)
        }
    }

    fun speakInterrupt(text: String) {
        if (!isReady) return
        val utteranceId = UUID.randomUUID().toString()
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
    }

    fun stop() {
        tts?.stop()
        pendingCallbacks.clear()
    }

    fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        isReady = false
        pendingCallbacks.clear()
    }
}
