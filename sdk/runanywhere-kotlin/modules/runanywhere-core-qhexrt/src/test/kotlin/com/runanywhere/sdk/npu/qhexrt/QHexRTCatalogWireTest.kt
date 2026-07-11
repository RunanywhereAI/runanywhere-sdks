package com.runanywhere.sdk.npu.qhexrt

import ai.runanywhere.proto.v1.HexagonArch
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelSource
import ai.runanywhere.proto.v1.RegisterModelFromUrlRequest
import org.junit.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals

class QHexRTCatalogWireTest {
    @Test
    fun `generated V75 V79 V81 values cross JNI unchanged`() {
        val arches =
            listOf(
                HexagonArch.HEXAGON_ARCH_V75,
                HexagonArch.HEXAGON_ARCH_V79,
                HexagonArch.HEXAGON_ARCH_V81,
            )

        assertContentEquals(intArrayOf(75, 79, 81), QHexRTCatalogWire.archValues(arches))
    }

    @Test
    fun `model definition crosses JNI as canonical proto bytes`() {
        val request =
            RegisterModelFromUrlRequest(
                id = "catalog-contract-model",
                name = "Catalog Contract Model",
                url = "https://huggingface.co/runanywhere/catalog-contract-model_HNPU/model.json",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                source = ModelSource.MODEL_SOURCE_REMOTE,
            )

        val bytes = QHexRTCatalogWire.encodeRequest(request)

        assertEquals(
            "0a4968747470733a2f2f68756767696e67666163652e636f2f72756e616e7977686572652f636174616c6f672d636f6e74726163742d6d6f64656c5f484e50552f6d6f64656c2e6a736f6e1216436174616c6f6720436f6e7472616374204d6f64656c1818200128016a16636174616c6f672d636f6e74726163742d6d6f64656c",
            bytes.joinToString(separator = "") { "%02x".format(it) },
        )
        assertEquals(request, RegisterModelFromUrlRequest.ADAPTER.decode(bytes))
    }
}
