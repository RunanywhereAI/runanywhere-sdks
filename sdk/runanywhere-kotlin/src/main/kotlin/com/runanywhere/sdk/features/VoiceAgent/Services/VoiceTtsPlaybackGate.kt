/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * VoiceTtsPlaybackGate.kt
 *
 * Half-duplex gate between the streaming TTS player and the voice-agent mic
 * driver. The voice agent is strictly turn-taking (no barge-in): while a reply
 * is playing out the device speaker, the mic must NOT feed captured audio to
 * the core — otherwise the device transcribes its OWN TTS output and the agent
 * talks to itself in an endless loop (observed: reply "…the capital is parent…"
 * re-transcribed and re-answered every ~15 s).
 *
 * Playback moved app-side to StreamingAudioPlayer (incremental AudioTrack), so
 * it happens asynchronously AFTER the core's blocking feed/turn returns; the
 * mic-driver's one-shot post-turn frame-drop no longer covers the out-loud
 * playback window. This gate closes that window: StreamingAudioPlayer marks
 * playback active for the whole reply, and VoiceAgentMicDriver drops mic frames
 * while active plus a short acoustic-decay tail after the last frame drains.
 */

package com.runanywhere.sdk.features.VoiceAgent.Services

import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import java.util.concurrent.atomic.AtomicInteger

internal object VoiceTtsPlaybackGate {
    private val logger = SDKLogger("VoiceTtsGate")

    // >0 while any streaming reply is actively writing to an AudioTrack.
    private val active = AtomicInteger(0)

    // Wall-clock cutoff covering the hardware buffer drain + room reverb after
    // the last chunk is handed to AudioTrack.stop() (deep-buffer output keeps
    // playing for a beat after the writer finishes), AND the deterministic,
    // reply-duration-based window the mic driver sets the instant a turn returns
    // (see [suppressForMs]). Whichever reaches furthest into the future wins.
    @Volatile private var suppressUntilMs = 0L

    /** A streaming reply started playing. Balanced by [onPlaybackStop]. */
    fun onPlaybackStart() {
        active.incrementAndGet()
    }

    /** The reply's AudioTrack was released (drained or hard-stopped). */
    fun onPlaybackStop(tailMs: Long = TAIL_MS) {
        if (active.get() > 0) active.decrementAndGet()
        extendUntil(System.currentTimeMillis() + tailMs)
    }

    /**
     * Deterministically mute the mic for [ms] from now. Called by the mic driver
     * the moment a turn returns with a reply, using the reply audio's own known
     * duration — so the whole out-loud playback is covered regardless of when the
     * async AudioTrack actually starts/stops. This is the primary echo guard; the
     * [onPlaybackStart]/[onPlaybackStop] pair is a secondary safety net.
     */
    fun suppressForMs(ms: Long) {
        extendUntil(System.currentTimeMillis() + ms)
    }

    /**
     * True while a reply is playing or within the suppression window. The mic
     * driver drops (does not feed) captured frames while this holds, so the
     * device never transcribes its own TTS.
     */
    fun micSuppressed(): Boolean =
        active.get() > 0 || System.currentTimeMillis() < suppressUntilMs

    private fun extendUntil(untilMs: Long) {
        if (untilMs > suppressUntilMs) {
            suppressUntilMs = untilMs
            logger.debug("mic suppressed for ${untilMs - System.currentTimeMillis()}ms")
        }
    }

    // Covers AudioTrack deep-buffer drain (~0.5 s buffer) plus a margin for the
    // speaker→mic acoustic tail so the last syllable is not re-transcribed.
    private const val TAIL_MS = 800L
}
