// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

package com.runanywhere.demo

import com.runanywhere.adapter.RunAnywhere
import com.runanywhere.adapter.VoiceAgentConfig
import com.runanywhere.adapter.VoiceEvent
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.runBlocking

fun main() = runBlocking<Unit> {
    println("RunAnywhere Kotlin JVM demo")
    println("  java.library.path: ${System.getProperty("java.library.path")}")

    val session = RunAnywhere.solution(VoiceAgentConfig())
    var events = 0
    session.run().collect { event: VoiceEvent ->
        ++events
        when (event) {
            is VoiceEvent.Error ->
                println("  event[error]: code=${event.code} message=${event.message}")
            is VoiceEvent.UserSaid ->
                println("  event[user]: ${event.text} (final=${event.isFinal})")
            is VoiceEvent.AssistantTok ->
                println("  event[tok ${event.kind}]: ${event.text}")
            is VoiceEvent.Audio ->
                println("  event[audio]: ${event.pcm.size} bytes @ ${event.sampleRateHz} Hz")
            is VoiceEvent.Interrupted ->
                println("  event[interrupted]: ${event.reason}")
        }
    }
    println("  ✓ stream completed with $events event(s)")
    println("")
    println("End-to-end path: Kotlin → System.loadLibrary(racommons_core) → " +
            "Java_com_runanywhere_adapter_VoiceSession_nativeCreate → " +
            "ra_pipeline_create_voice_agent (C ABI)")
}
