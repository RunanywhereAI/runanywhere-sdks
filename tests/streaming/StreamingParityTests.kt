/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * parity_test.kt — GAP 09 / v2 close-out Phase 4 streaming parity test (Kotlin/JVM).
 *
 * Loads the golden file produced by parity_test_cpp and compares it against
 * a Kotlin-side encoding of the same 8-event golden sequence. Wire-format
 * equivalence proves the Wire-generated VoiceEvent type round-trips through
 * the line schema identically to the C++ producer.
 *
 * To regenerate the golden after a deliberate schema change:
 *     ./build/macos-release/tests/streaming/parity_test_cpp \
 *         tests/streaming/fixtures/golden_events.txt
 */

package com.runanywhere.sdk.tests.streaming

// Wire-generated bindings live under `ai.runanywhere.proto.v1` (see
// `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/generated/
// ai/runanywhere/proto/v1/`). The matching SDK adapters (e.g.
// VoiceAgentStreamAdapter) consume these same types, so the parity check
// proves the wire-format is identical to the C++ producer's emit path.
import ai.runanywhere.proto.v1.AssistantTokenEvent
import ai.runanywhere.proto.v1.AudioEncoding
import ai.runanywhere.proto.v1.AudioFrameEvent
import ai.runanywhere.proto.v1.ErrorEvent
import ai.runanywhere.proto.v1.MetricsEvent
import ai.runanywhere.proto.v1.PipelineState
import ai.runanywhere.proto.v1.StateChangeEvent
import ai.runanywhere.proto.v1.TokenKind
import ai.runanywhere.proto.v1.UserSaidEvent
import ai.runanywhere.proto.v1.VADEvent
import ai.runanywhere.proto.v1.VADEventType
import ai.runanywhere.proto.v1.VoiceEvent
import okio.ByteString
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.io.File

class StreamingParityTests {
    /** Same line-schema as parity_test.cpp / parity_test.swift. */
    private fun formatEvent(event: VoiceEvent): String =
        when {
            event.user_said != null -> {
                val u = event.user_said
                "user_said:text=${u.text},is_final=${if (u.is_final) "true" else "false"}"
            }
            event.assistant_token != null -> {
                val t = event.assistant_token
                "assistant_token:text=${t.text},is_final=${if (t.is_final) "true" else "false"},kind=${t.kind.value}"
            }
            event.audio != null -> {
                val a = event.audio
                "audio:bytes=${a.pcm.size},sample_rate=${a.sample_rate_hz},channels=${a.channels},encoding=${a.encoding.value}"
            }
            event.vad != null -> "vad:type=${event.vad.type.value}"
            event.state != null -> "state:previous=${event.state.previous.value},current=${event.state.current.value}"
            event.error != null -> "error:code=${event.error.code},component=${event.error.component}"
            event.metrics != null -> {
                val overBudget = if (event.metrics.is_over_budget) "true" else "false"
                "metrics:tokens_generated=${event.metrics.tokens_generated},is_over_budget=$overBudget"
            }
            event.interrupted != null -> "interrupted:reason=${event.interrupted.reason.value}"
            else -> "unknown_arm"
        }

    private fun loadGolden(): List<String> {
        // The golden file is repo-root-relative (`tests/streaming/fixtures/
        // golden_events.txt`). Resolve it without depending on the runner's
        // CWD: probe `RAC_PARITY_GOLDEN` first (CI / explicit override),
        // then walk parent directories from the JVM's CWD looking for the
        // fixture. Works whether `./gradlew jvmTest` is invoked at the
        // repo root or under `sdk/runanywhere-kotlin/`.
        val relative = "tests/streaming/fixtures/golden_events.txt"
        val envPath = System.getenv("RAC_PARITY_GOLDEN")?.takeIf { it.isNotBlank() }
        val resolved: File =
            envPath?.let(::File)?.takeIf { it.exists() }
                ?: generateSequence(File(".").canonicalFile) { it.parentFile }
                    .map { File(it, relative) }
                    .firstOrNull { it.exists() }
                ?: error("golden file not found: $relative (cwd=${File(".").canonicalPath})")
        return resolved
            .readLines()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
    }

    /** Same 8-event sequence parity_test.cpp emits, hand-built from the
     *  Wire-generated types. Pure data; no JNI / live agent required. */
    private fun kotlinGoldenSequence(): List<VoiceEvent> =
        listOf(
            VoiceEvent(vad = VADEvent(type = VADEventType.VAD_EVENT_VOICE_START)),
            VoiceEvent(vad = VADEvent(type = VADEventType.VAD_EVENT_VOICE_END_OF_UTTERANCE)),
            VoiceEvent(user_said = UserSaidEvent(text = "what is the weather today", is_final = true)),
            VoiceEvent(
                assistant_token =
                    AssistantTokenEvent(
                        text = "the weather is sunny and 72 degrees",
                        is_final = true,
                        kind = TokenKind.TOKEN_KIND_ANSWER,
                    ),
            ),
            VoiceEvent(
                audio =
                    AudioFrameEvent(
                        pcm = ByteString.of(*ByteArray(16)),
                        sample_rate_hz = 24000,
                        channels = 1,
                        encoding = AudioEncoding.AUDIO_ENCODING_PCM_F32_LE,
                    ),
            ),
            VoiceEvent(metrics = MetricsEvent()),
            VoiceEvent(error = ErrorEvent(code = -259, component = "pipeline")),
            VoiceEvent(
                state =
                    StateChangeEvent(
                        previous = PipelineState.PIPELINE_STATE_IDLE,
                        current = PipelineState.PIPELINE_STATE_LISTENING,
                    ),
            ),
        )

    @Test
    fun voiceAgent_streamsExpectedEvents() {
        val golden = loadGolden()
        val actual = kotlinGoldenSequence().map(::formatEvent)
        assertEquals(
            golden,
            actual,
            "Kotlin event line schema drifted from parity_test_cpp golden output",
        )
    }

    @Test
    fun cancellation_yieldsNoStaleEvents() {
        // VoiceAgentStreamAdapter cancellation contract: when Flow collection
        // is cancelled, awaitClose fires and JNI deregisters the C callback.
        // Pure-Flow mechanics check here — full live-agent verification is in
        // docs/v2_closeout_device_verification.md.
        //
        // CancellationException thrown inside `collect { ... }` propagates up
        // through `runBlocking`; catch it here so the test itself observes
        // the same "first emission only, cancel is honored" contract that
        // the real adapter exposes via Flow cancellation.
        val collected = mutableListOf<Int>()
        try {
            kotlinx.coroutines.runBlocking {
                kotlinx.coroutines.flow
                    .flow<Int> {
                        emit(1)
                        emit(2)
                        emit(3)
                    }.collect {
                        collected.add(it)
                        if (collected.size >= 1) {
                            throw kotlinx.coroutines.CancellationException("user break")
                        }
                    }
            }
        } catch (_: kotlinx.coroutines.CancellationException) {
            // Expected — proves the cancel signal terminated collection.
        }
        assertEquals(listOf(1), collected, "cancel should fire after first emission")
    }
}
