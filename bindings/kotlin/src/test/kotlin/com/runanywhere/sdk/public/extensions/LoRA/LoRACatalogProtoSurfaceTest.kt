package com.runanywhere.sdk.public.extensions.LoRA

import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogListRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogListResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogQuery
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Focused tests for generated Lora* catalog surface.
 *
 * idl/lora_options.proto's "lora-delete-download-import-bookkeeping" edit
 * deleted `LoraAdapterDownloadCompletedRequest`/`Result` and
 * `LoraAdapterImportRequest`/`Result` outright (no replacement -- adapter
 * files are acquired exclusively through the models domain's download/import
 * verbs now, see `RunAnywhereLoRA.kt`), and shrunk `LoraAdapterCatalogEntry`
 * to `{id, name, compatible_models, default_scale, tags, local_path}` --
 * `url`/`filename`/`is_downloaded`/`is_imported` all deleted ("everything
 * generic about the artifact ... lives on the ModelInfo record for this
 * adapter" now). `LoraAdapterCatalogListRequest.include_counts` is likewise
 * deleted with no replacement. Mirrors Swift's `LoRAProtoSurfaceTests.swift`.
 */
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
            )

        val decoded =
            LoraAdapterCatalogListRequest.ADAPTER.decode(
                LoraAdapterCatalogListRequest.ADAPTER.encode(request),
            )

        assertEquals("qwen2.5-0.5b", decoded.query?.model_id)
        assertEquals(true, decoded.query?.downloaded_only)
        assertEquals("style", decoded.query?.search_query)
        assertEquals(listOf("chat"), decoded.query?.tags)
    }

    @Test
    fun `catalog entries carry canonical fields, local_path is the sole downloaded signal`() {
        val entry =
            LoraAdapterCatalogEntry(
                id = "adapter-a",
                name = "Adapter A",
                compatible_models = listOf("base-model"),
                default_scale = 1.0f,
                tags = listOf("chat"),
                local_path = "/models/adapter-a.gguf",
            )

        val listResult =
            LoraAdapterCatalogListResult(
                entries = listOf(entry),
                total_count = 1,
                downloaded_count = 1,
            )

        val getRequest = LoraAdapterCatalogGetRequest(adapter_id = "adapter-a")
        val getResult = LoraAdapterCatalogGetResult(found = true, entry = entry)

        assertEquals("/models/adapter-a.gguf", listResult.entries.first().local_path)
        assertEquals(1, listResult.downloaded_count)
        assertEquals("adapter-a", getRequest.adapter_id)
        assertTrue(getResult.found)
        // Non-empty local_path is the single definition of "downloaded" now
        // (is_downloaded/is_imported were deleted outright).
        assertTrue(!(getResult.entry?.local_path.isNullOrEmpty()))
    }
}
