package com.runanywhere.runanywhereai.ui.screens.rag

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RagPipelineCoordinatorPolicyTest {
    private val pipeline = RagPipelineIdentity("embed", "answer", rerankEnabled = false)

    @Test
    fun `another screen must reacquire even for the same model pair`() {
        assertTrue(
            shouldRecreateRagPipeline(
                activeOwner = "chat",
                activeIdentity = pipeline,
                requestedOwner = "documents",
                requestedIdentity = pipeline,
            ),
        )
    }

    @Test
    fun `same owner and exact configuration can reuse its indexed corpus`() {
        assertFalse(
            shouldRecreateRagPipeline(
                activeOwner = "documents",
                activeIdentity = pipeline,
                requestedOwner = "documents",
                requestedIdentity = pipeline,
            ),
        )
    }

    @Test
    fun `model or rerank change recreates the native singleton`() {
        assertTrue(
            shouldRecreateRagPipeline(
                activeOwner = "documents",
                activeIdentity = pipeline,
                requestedOwner = "documents",
                requestedIdentity = pipeline.copy(llmModelId = "answer-v2"),
            ),
        )
        assertTrue(
            shouldRecreateRagPipeline(
                activeOwner = "documents",
                activeIdentity = pipeline,
                requestedOwner = "documents",
                requestedIdentity = pipeline.copy(rerankEnabled = true),
            ),
        )
    }

    @Test
    fun `chat document B replaces document A instead of extending its corpus`() = runBlocking {
        val corpus = mutableListOf<String>()

        replaceRagCorpus(clear = corpus::clear, ingest = { corpus += "A" })
        replaceRagCorpus(clear = corpus::clear, ingest = { corpus += "B" })

        assertEquals(listOf("B"), corpus)
    }
}
