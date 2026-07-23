package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelCompatibilityResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RAModelLoadResult
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelCompatibilityPreflightTest {
    @Test
    fun `insufficient memory blocks before download network`() =
        runBlocking {
            var networkCalls = 0
            val error =
                captureSdkException {
                    withModelCompatibilityPreflight(
                        operation = ModelCompatibilityOperation.DOWNLOAD,
                        resultProvider = {
                            compatibilityResult(canRun = false, canFit = true)
                        },
                    ) {
                        networkCalls += 1
                    }
                }

            assertEquals(0, networkCalls)
            assertTrue(error.message.orEmpty().contains("Close other apps"))
        }

    @Test
    fun `compatible result proceeds to download network`() =
        runBlocking {
            var networkCalls = 0
            withModelCompatibilityPreflight(
                operation = ModelCompatibilityOperation.DOWNLOAD,
                resultProvider = { compatibilityResult(canRun = true, canFit = true) },
            ) {
                networkCalls += 1
            }

            assertEquals(1, networkCalls)
        }

    @Test
    fun `request load gate proceeds to native load when compatible`() =
        runBlocking {
            val request = loadRequest()
            var nativeLoadCalls = 0
            val result =
                withModelLoadCompatibilityPreflight(
                    request = request,
                    resultProvider = { compatibilityResult(canRun = true, canFit = true) },
                ) {
                    nativeLoadCalls += 1
                    RAModelLoadResult(success = true, model_id = request.model_id)
                }

            assertEquals(1, nativeLoadCalls)
            assertTrue(result.success)
        }

    @Test
    fun `request load gate blocks native load with actionable failure result`() =
        runBlocking {
            val request = loadRequest()
            var nativeLoadCalls = 0
            val result =
                withModelLoadCompatibilityPreflight(
                    request = request,
                    resultProvider = { compatibilityResult(canRun = false, canFit = true) },
                ) {
                    nativeLoadCalls += 1
                    RAModelLoadResult(success = true, model_id = request.model_id)
                }

            assertEquals(0, nativeLoadCalls)
            assertFalse(result.success)
            assertEquals(request.model_id, result.model_id)
            assertEquals(request.category, result.category)
            assertEquals(request.framework, result.framework)
            assertTrue(result.error_message.contains("Close other apps"))
        }

    @Test
    fun `request load gate permits imported model with unknown zero memory requirement`() =
        runBlocking {
            val request = loadRequest().copy(model_id = "local-import-with-unknown-memory")
            var nativeLoadCalls = 0
            val result =
                withModelLoadCompatibilityPreflight(
                    request = request,
                    resultProvider = {
                        compatibilityResult(
                            canRun = true,
                            canFit = false,
                            requiredMemoryBytes = 0L,
                        ).copy(model_id = request.model_id)
                    },
                ) {
                    nativeLoadCalls += 1
                    RAModelLoadResult(success = true, model_id = request.model_id)
                }

            assertEquals(1, nativeLoadCalls)
            assertTrue(result.success)
        }

    private suspend fun captureSdkException(block: suspend () -> Unit): SDKException =
        try {
            block()
            throw AssertionError("Expected SDKException")
        } catch (error: SDKException) {
            error
        }

    private fun loadRequest(): RAModelLoadRequest =
        RAModelLoadRequest(
            model_id = "llama-3.1-nemotron-nano-8b-v1-q4_k_m",
            category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
            framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        )

    private fun compatibilityResult(
        canRun: Boolean,
        canFit: Boolean,
        requiredMemoryBytes: Long = 6L * 1_024L * 1_024L * 1_024L,
    ): ModelCompatibilityResult =
        ModelCompatibilityResult(
            model_id = "llama-3.1-nemotron-nano-8b-v1-q4_k_m",
            can_run = canRun,
            can_fit = canFit,
            is_compatible = canRun && canFit,
            required_memory_bytes = requiredMemoryBytes,
            available_memory_bytes = 3L * 1_024L * 1_024L * 1_024L,
            required_storage_bytes = 4_920_736_864L,
            available_storage_bytes = 10L * 1_024L * 1_024L * 1_024L,
        )
}
