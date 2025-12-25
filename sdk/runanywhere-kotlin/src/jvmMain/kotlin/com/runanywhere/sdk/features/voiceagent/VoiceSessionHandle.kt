package com.runanywhere.sdk.features.voiceagent

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * JVM stub implementation of VoiceSessionHandle.
 * Voice sessions are primarily designed for mobile platforms with microphone access.
 */
@Suppress("UnusedPrivateProperty")
actual class VoiceSessionHandle actual constructor(
    private val config: VoiceSessionConfig,
) {
    private val _events = MutableSharedFlow<VoiceSessionEvent>(replay = 1)

    /** Stream of session events */
    actual val events: Flow<VoiceSessionEvent> = _events.asSharedFlow()

    /** Start the voice session - JVM stub */
    actual suspend fun start() {
        _events.emit(VoiceSessionEvent.Error("Voice sessions are not supported on JVM. Use Android or iOS."))
    }

    /** Stop the voice session */
    actual fun stop() {
        // No-op on JVM
    }

    /** Force process current audio (push-to-talk) */
    actual suspend fun sendNow() {
        // No-op on JVM
    }
}
