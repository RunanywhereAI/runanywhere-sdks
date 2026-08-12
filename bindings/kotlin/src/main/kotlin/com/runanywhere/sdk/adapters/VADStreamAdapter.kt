/*
 * VADStreamAdapter.kt
 *
 * Thin decode helper over commons `rac_vad_stream_*` `VADStreamEvent` bytes.
 * Endpointing stays in commons; this adapter only maps SPEECH_ACTIVITY /
 * FRAME / ERROR envelopes onto public [VadEvent]s for bridge consumers and
 * tests — no local isSpeech edge machine, debounce, or one-shot fallback.
 */

package com.runanywhere.sdk.adapters

import com.runanywhere.sdk.public.api.VadEvent
import com.runanywhere.sdk.public.api.decodeVadStreamEvent

/**
 * Stateless mapper from serialized commons stream events to public VAD events.
 */
object VADStreamAdapter {
    /** Decode one `VADStreamEvent` payload into zero or more [VadEvent]s. */
    fun decode(raw: ByteArray): List<VadEvent> = decodeVadStreamEvent(raw)
}
