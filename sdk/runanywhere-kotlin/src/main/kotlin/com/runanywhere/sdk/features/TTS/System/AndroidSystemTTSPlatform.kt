package com.runanywhere.sdk.features.TTS.System

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.runanywhere.sdk.foundation.security.AndroidPlatformContext
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

private const val RAC_SUCCESS = 0
private const val RAC_ERROR_TIMEOUT = -155
private const val RAC_ERROR_NOT_SUPPORTED = -236
private const val RAC_ERROR_CANCELLED = -380
private const val RAC_ERROR_MODULE_ALREADY_REGISTERED = -401
private const val RAC_ERROR_INTERNAL = -805

private const val INIT_TIMEOUT_SECONDS = 15L
private const val SPEAK_TIMEOUT_SECONDS = 120L

internal object AndroidSystemTTSPlatform {
    private val logger = SDKLogger.tts
    private val nextHandle = AtomicLong(1)
    private val services = ConcurrentHashMap<Long, AndroidSystemTTSService>()

    fun register(): Int {
        if (!AndroidPlatformContext.isInitialized()) {
            logger.warning("Android System TTS skipped: AndroidPlatformContext is not initialized")
            return RAC_ERROR_NOT_SUPPORTED
        }
        if (!RunAnywhereBridge.ensureNativeLibraryLoaded()) {
            logger.warning("Android System TTS skipped: native commons library is not loaded")
            return RAC_ERROR_NOT_SUPPORTED
        }

        val result = RunAnywhereBridge.racPlatformRegisterSystemTts()
        if (result == RAC_SUCCESS || result == RAC_ERROR_MODULE_ALREADY_REGISTERED) {
            logger.info("Android System TTS platform backend registered")
        } else {
            logger.warning("Android System TTS platform registration returned code: $result")
        }
        return result
    }

    fun unregister(): Int {
        services.values.forEach { it.destroy() }
        services.clear()
        return runCatching { RunAnywhereBridge.racPlatformUnregister() }
            .getOrElse {
                logger.debug("Android System TTS platform unregister failed: ${it.message}")
                RAC_ERROR_INTERNAL
            }
    }

    @JvmStatic
    fun canHandle(voiceId: String?): Boolean {
        val normalized = voiceId?.lowercase(Locale.US) ?: return true
        return normalized == "system" ||
            normalized == "system-tts" ||
            normalized == "system_tts" ||
            normalized.startsWith("android-tts") ||
            normalized.startsWith("android_tts")
    }

    @JvmStatic
    fun create(voiceId: String?, language: String?): Long {
        return runCatching {
            val service = AndroidSystemTTSService(voiceId = voiceId, language = language)
            val handle = nextHandle.getAndIncrement()
            services[handle] = service
            handle
        }.getOrElse {
            logger.error("Failed to create Android System TTS service: ${it.message}", throwable = it)
            0L
        }
    }

    @JvmStatic
    fun synthesize(
        handle: Long,
        text: String,
        rate: Float,
        pitch: Float,
        volume: Float,
        voiceId: String?,
    ): Int {
        val service = services[handle] ?: return RAC_ERROR_INTERNAL
        return service.speak(text = text, rate = rate, pitch = pitch, volume = volume, voiceId = voiceId)
    }

    @JvmStatic
    fun stop(handle: Long) {
        services[handle]?.stop()
    }

    @JvmStatic
    fun destroy(handle: Long) {
        services.remove(handle)?.destroy()
    }
}

private class AndroidSystemTTSService(
    voiceId: String?,
    language: String?,
) {
    private val logger = SDKLogger.tts
    private val mainHandler = Handler(Looper.getMainLooper())
    private val initLatch = CountDownLatch(1)
    private val initStatus = AtomicInteger(TextToSpeech.ERROR)
    private val tts: TextToSpeech

    init {
        val created =
            runOnMainBlocking(INIT_TIMEOUT_SECONDS, TimeUnit.SECONDS) {
                TextToSpeech(AndroidPlatformContext.applicationContext) { status ->
                    initStatus.set(status)
                    initLatch.countDown()
                }
            } ?: throw IllegalStateException("Timed out creating Android TextToSpeech")

        tts = created
        if (!initLatch.await(INIT_TIMEOUT_SECONDS, TimeUnit.SECONDS) ||
            initStatus.get() != TextToSpeech.SUCCESS
        ) {
            runOnMain { created.shutdown() }
            throw IllegalStateException("Android TextToSpeech initialization failed: ${initStatus.get()}")
        }

        runOnMainBlocking(INIT_TIMEOUT_SECONDS, TimeUnit.SECONDS) {
            applyVoice(voiceId = voiceId, language = language)
        }
    }

    @Synchronized
    fun speak(
        text: String,
        rate: Float,
        pitch: Float,
        volume: Float,
        voiceId: String?,
    ): Int {
        if (text.isBlank()) {
            return RAC_SUCCESS
        }

        val done = CountDownLatch(1)
        val result = AtomicInteger(RAC_ERROR_INTERNAL)
        val utteranceId = "runanywhere-system-tts-${System.nanoTime()}"

        val speakResult =
            runOnMainBlocking(INIT_TIMEOUT_SECONDS, TimeUnit.SECONDS) {
                applyVoice(voiceId = voiceId, language = null)
                tts.setSpeechRate(if (rate > 0f) rate else 1.0f)
                tts.setPitch(if (pitch > 0f) pitch else 1.0f)
                tts.setOnUtteranceProgressListener(
                    object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) = Unit

                        override fun onDone(utteranceId: String?) {
                            result.set(RAC_SUCCESS)
                            done.countDown()
                        }

                        @Deprecated("Deprecated in Android framework")
                        override fun onError(utteranceId: String?) {
                            result.set(RAC_ERROR_INTERNAL)
                            done.countDown()
                        }

                        override fun onStop(utteranceId: String?, interrupted: Boolean) {
                            result.set(if (interrupted) RAC_ERROR_CANCELLED else RAC_SUCCESS)
                            done.countDown()
                        }
                    },
                )

                val params =
                    Bundle().apply {
                        putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume.coerceIn(0f, 1f))
                    }
                tts.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
            } ?: return RAC_ERROR_TIMEOUT

        if (speakResult == TextToSpeech.ERROR) {
            return RAC_ERROR_INTERNAL
        }

        return if (done.await(SPEAK_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            result.get()
        } else {
            stop()
            RAC_ERROR_TIMEOUT
        }
    }

    fun stop() {
        runOnMain { tts.stop() }
    }

    fun destroy() {
        runOnMain {
            tts.stop()
            tts.shutdown()
        }
    }

    private fun applyVoice(voiceId: String?, language: String?) {
        val normalizedVoice = voiceId?.takeIf { AndroidSystemTTSPlatform.canHandle(it).not() }
        val selectedVoice = normalizedVoice?.let { id -> tts.voices?.firstOrNull { it.name == id } }
        if (selectedVoice != null) {
            tts.voice = selectedVoice
            return
        }

        val locale = language?.takeIf { it.isNotBlank() }?.let(Locale::forLanguageTag) ?: Locale.US
        tts.language = locale
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }

    private fun <T> runOnMainBlocking(
        timeout: Long,
        unit: TimeUnit,
        block: () -> T,
    ): T? {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return block()
        }

        val latch = CountDownLatch(1)
        var value: T? = null
        var error: Throwable? = null
        mainHandler.post {
            try {
                value = block()
            } catch (t: Throwable) {
                error = t
            } finally {
                latch.countDown()
            }
        }

        if (!latch.await(timeout, unit)) {
            return null
        }
        error?.let { throw it }
        return value
    }
}
