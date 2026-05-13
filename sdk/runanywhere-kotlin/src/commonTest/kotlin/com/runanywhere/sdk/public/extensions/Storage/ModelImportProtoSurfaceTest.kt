package com.runanywhere.sdk.public.extensions.Storage

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelFormat
import ai.runanywhere.proto.v1.ModelImportRequest
import ai.runanywhere.proto.v1.ModelImportResult
import ai.runanywhere.proto.v1.ModelInfo
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.importModel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Mirrors Swift `ModelImportProtoSurfaceTests.swift`.
 *
 * Compile-time checks for the generated model import surface and the public
 * `RunAnywhere.importModel(...)` API.
 */
class ModelImportProtoSurfaceTest {
    @Test
    fun testModelImportRequestCarriesCanonicalFields() {
        val model =
            ModelInfo(
                id = "demo-model",
                name = "Demo Model",
                local_path = "/models/demo.gguf",
                format = ModelFormat.MODEL_FORMAT_GGUF,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                is_downloaded = true,
            )

        val request =
            ModelImportRequest(
                model = model,
                source_path = "/models/demo.gguf",
                overwrite_existing = true,
                validate_before_register = true,
            )

        val resolved = assertNotNull(request.model)
        assertEquals("demo-model", resolved.id)
        assertEquals("/models/demo.gguf", request.source_path)
        assertTrue(request.overwrite_existing)
        assertTrue(request.validate_before_register)
    }

    @Test
    fun testModelImportRequestRoundTripsThroughGeneratedAdapter() {
        val request =
            ModelImportRequest(
                model =
                    ModelInfo(
                        id = "round-trip",
                        name = "Round Trip",
                        local_path = "/models/round.gguf",
                        format = ModelFormat.MODEL_FORMAT_GGUF,
                        framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                    ),
                source_path = "/models/round.gguf",
                copy_into_managed_storage = true,
                validate_before_register = true,
            )

        val decoded =
            ModelImportRequest.ADAPTER.decode(
                ModelImportRequest.ADAPTER.encode(request),
            )

        assertEquals("round-trip", decoded.model?.id)
        assertEquals("/models/round.gguf", decoded.source_path)
        assertTrue(decoded.copy_into_managed_storage)
        assertTrue(decoded.validate_before_register)
    }

    @Test
    fun testModelImportResultCarriesPersistenceMetadata() {
        val result =
            ModelImportResult(
                success = true,
                model =
                    ModelInfo(
                        id = "demo-model",
                        name = "Demo Model",
                        local_path = "/models/demo.gguf",
                    ),
                local_path = "/models/demo.gguf",
                imported_bytes = 1024L,
                registered = true,
                copied_into_managed_storage = false,
            )

        val decoded =
            ModelImportResult.ADAPTER.decode(
                ModelImportResult.ADAPTER.encode(result),
            )

        assertTrue(decoded.success)
        assertTrue(decoded.registered)
        assertEquals("demo-model", decoded.model?.id)
        assertEquals("/models/demo.gguf", decoded.local_path)
        assertEquals(1024L, decoded.imported_bytes)
        assertEquals(false, decoded.copied_into_managed_storage)
    }
}

/**
 * Compile-time proof that `RunAnywhere.importModel(ModelImportRequest)` is
 * declared with the canonical generated request/result types.
 *
 * Mirrors Swift `testModelImportSurfaceUsesGeneratedProtoTypes` which assigns
 * the symbol to a typed function value to confirm the signature.
 */
@Suppress("unused")
private suspend fun modelImportSurface(request: ModelImportRequest): ModelImportResult =
    RunAnywhere.importModel(request)
