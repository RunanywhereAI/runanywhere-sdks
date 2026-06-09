package com.runanywhere.sdk.public.extensions.TTS

import ai.runanywhere.proto.v1.TTSOutput
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.synthesizeStream
import kotlinx.coroutines.flow.Flow
import kotlin.test.Test
import kotlin.test.assertEquals

class TTSGeneratedStreamSurfaceTest {
    @Test
    fun `generated TTS output remains the public stream surface`() {
        val output = TTSOutput()

        assertEquals(0L, output.audio_size_bytes)
    }
}

@Suppress("unused")
private fun ttsStreamSurface(): Flow<TTSOutput> =
    RunAnywhere.synthesizeStream(
        "hello",
        options =
            ai.runanywhere.proto.v1
                .TTSOptions(),
    )
