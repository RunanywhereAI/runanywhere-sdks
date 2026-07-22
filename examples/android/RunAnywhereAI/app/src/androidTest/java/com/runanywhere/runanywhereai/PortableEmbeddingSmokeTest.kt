package com.runanywhere.runanywhereai

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.embeddings
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.sqrt

/**
 * Focused physical-device smoke for an already-downloaded portable GGUF embedder.
 *
 * Run with:
 *   -e class com.runanywhere.runanywhereai.PortableEmbeddingSmokeTest \
 *   -e modelId <registered-model-id>
 *
 * This deliberately exercises only public SDK APIs. Model registration and
 * download remain owned by the example app's normal model-picker workflow.
 */
@RunWith(AndroidJUnit4::class)
class PortableEmbeddingSmokeTest {
    private val tag = "PORTABLE_EMBED_E2E"

    @Test
    fun embedAlreadyDownloadedModel() {
        runBlocking {
            val modelId = requireNotNull(
                InstrumentationRegistry.getArguments().getString("modelId")?.takeIf { it.isNotBlank() },
            ) { "-e modelId is required" }

            awaitSdkReady(180_000)

            val query = "query: Which planet is known as the Red Planet?"
            val positive = "passage: Mars is commonly called the Red Planet because of iron oxide on its surface."
            val negative = "passage: The Pacific Ocean is the largest ocean on Earth."

            try {
                val started = System.currentTimeMillis()
                val vectors = listOf(query, positive, negative).map { text ->
                    withTimeout(180_000) {
                        RunAnywhere.embeddings.embed(text, modelId)
                    }.vectors.single().values.toFloatArray()
                }
                val elapsedMs = System.currentTimeMillis() - started
                val norms = vectors.map(::l2Norm)
                val positiveCosine = cosine(vectors[0], vectors[1])
                val negativeCosine = cosine(vectors[0], vectors[2])

                assertTrue("all embedding values must be finite", vectors.all { vector -> vector.all(Float::isFinite) })
                vectors.forEach { assertEquals("unexpected embedding dimension", 2_048, it.size) }
                norms.forEach { assertTrue("embedding must be L2-normalized, norm=$it", it in 0.99..1.01) }
                assertTrue(
                    "related passage must rank above distractor: positive=$positiveCosine negative=$negativeCosine",
                    positiveCosine > negativeCosine,
                )

                Log.i(
                    tag,
                    "PASS model=$modelId dims=${vectors.map { it.size }} norms=$norms " +
                        "positiveCosine=$positiveCosine negativeCosine=$negativeCosine elapsedMs=$elapsedMs",
                )
            } finally {
                withTimeout(180_000) { RunAnywhere.embeddings.unload() }
                assertNull("embedding lifecycle must be empty after unload", RunAnywhere.embeddings.currentModelID())
            }
        }
    }

    private fun awaitSdkReady(timeoutMs: Long) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (GlobalState.ready) return
            GlobalState.initError?.let { error("SDK init failed: $it") }
            Thread.sleep(500)
        }
        error("SDK not ready within ${timeoutMs}ms")
    }

    private fun l2Norm(vector: FloatArray): Double =
        sqrt(vector.sumOf { value -> value.toDouble() * value })

    private fun cosine(a: FloatArray, b: FloatArray): Double {
        require(a.size == b.size)
        var dot = 0.0
        var aSquared = 0.0
        var bSquared = 0.0
        for (index in a.indices) {
            dot += a[index] * b[index]
            aSquared += a[index].toDouble() * a[index]
            bSquared += b[index].toDouble() * b[index]
        }
        return dot / (sqrt(aSquared) * sqrt(bSquared))
    }
}
