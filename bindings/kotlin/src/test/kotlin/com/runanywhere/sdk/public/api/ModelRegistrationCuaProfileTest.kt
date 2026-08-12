/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.RegisterModelFromUrlRequest
import ai.runanywhere.proto.v1.RegisterMultiFileModelRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Register-mapping + IDL round-trip coverage for `cuaProfile`
 * (PR #605 review issue 9): every [ModelRegistration] factory must carry the
 * field, and the generated register proto Wire types must round-trip it.
 */
class ModelRegistrationCuaProfileTest {
    @Test
    fun `url registration carries cuaProfile`() {
        val model =
            ModelRegistration.url(
                name = "Fara1.5",
                url = "https://example.com/fara.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                cuaProfile = "fara",
            )
        assertEquals("fara", model.cuaProfile)
    }

    @Test
    fun `archive registration carries cuaProfile`() {
        val model =
            ModelRegistration.archive(
                name = "Fara1.5",
                url = "https://example.com/fara.tar.gz",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                structure = ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
                cuaProfile = "fara",
            )
        assertEquals("fara", model.cuaProfile)
    }

    @Test
    fun `multiFile registration carries cuaProfile`() {
        val model =
            ModelRegistration.multiFile(
                id = "fara1.5-4b-q4_k_m",
                name = "Fara1.5 4B",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                files = emptyList(),
                cuaProfile = "fara",
            )
        assertEquals("fara", model.cuaProfile)
    }

    @Test
    fun `registration without cuaProfile leaves it null`() {
        val model =
            ModelRegistration.url(
                name = "Some Model",
                url = "https://example.com/model.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
            )
        assertNull(model.cuaProfile)
    }

    @Test
    fun `RegisterModelFromUrlRequest round-trips cua_profile`() {
        val request =
            RegisterModelFromUrlRequest(
                url = "https://example.com/fara.gguf",
                name = "Fara1.5",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                cua_profile = "fara",
            )
        val decoded = RegisterModelFromUrlRequest.ADAPTER.decode(RegisterModelFromUrlRequest.ADAPTER.encode(request))
        assertEquals("fara", decoded.cua_profile)
    }

    @Test
    fun `RegisterMultiFileModelRequest round-trips cua_profile`() {
        val request =
            RegisterMultiFileModelRequest(
                id = "fara1.5-4b-q4_k_m",
                name = "Fara1.5 4B",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                files =
                    listOf(
                        ModelFileDescriptor(
                            url = "https://example.com/fara.gguf",
                            filename = "fara.gguf",
                        ),
                    ),
                cua_profile = "fara",
            )
        val decoded =
            RegisterMultiFileModelRequest.ADAPTER.decode(RegisterMultiFileModelRequest.ADAPTER.encode(request))
        assertEquals("fara", decoded.cua_profile)
    }
}
