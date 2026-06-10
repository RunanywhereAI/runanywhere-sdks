package com.runanywhere.sdk.public.extensions.LoRA

import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.LoraAdapterCatalogListRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogQuery
import ai.runanywhere.proto.v1.LoraAdapterDownloadCompletedRequest
import ai.runanywhere.proto.v1.LoraAdapterDownloadCompletedResult
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LoRACatalogProtoSurfaceTest {
    @Test
    fun `catalog list request carries generated query fields`() {
        val request =
            LoraAdapterCatalogListRequest(
                query =
                    LoraAdapterCatalogQuery(
                        model_id = "qwen2.5-0.5b",
                        downloaded_only = true,
                        search_query = "style",
                        tags = listOf("chat"),
                    ),
                include_counts = true,
            )

        val decoded =
            LoraAdapterCatalogListRequest.ADAPTER.decode(
                LoraAdapterCatalogListRequest.ADAPTER.encode(request),
            )

        assertEquals("qwen2.5-0.5b", decoded.query?.model_id)
        assertEquals(true, decoded.query?.downloaded_only)
        assertEquals("style", decoded.query?.search_query)
        assertEquals(listOf("chat"), decoded.query?.tags)
        assertTrue(decoded.include_counts)
    }

    @Test
    fun `download completion result carries persisted catalog state`() {
        val request =
            LoraAdapterDownloadCompletedRequest(
                adapter_id = "adapter-1",
                local_path = "/models/lora/adapter-1.gguf",
                size_bytes = 42L,
                checksum_sha256 = "abc123",
                completed_at_unix_ms = 1234L,
                status_message = "download completed",
            )
        val result =
            LoraAdapterDownloadCompletedResult(
                success = true,
                persisted = true,
                entry =
                    LoraAdapterCatalogEntry(
                        id = request.adapter_id,
                        local_path = request.local_path,
                        is_downloaded = true,
                        downloaded_at_unix_ms = request.completed_at_unix_ms,
                        status_message = request.status_message,
                    ),
            )

        val decoded =
            LoraAdapterDownloadCompletedResult.ADAPTER.decode(
                LoraAdapterDownloadCompletedResult.ADAPTER.encode(result),
            )

        assertTrue(decoded.success)
        assertTrue(decoded.persisted)
        assertEquals("/models/lora/adapter-1.gguf", decoded.entry?.local_path)
        assertEquals(true, decoded.entry?.is_downloaded)
        assertEquals(1234L, decoded.entry?.downloaded_at_unix_ms)
    }
}
