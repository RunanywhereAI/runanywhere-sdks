/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: `RunAnywhere.lora`.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.LoRAAdapterConfig
import ai.runanywhere.proto.v1.LoRAApplyRequest
import ai.runanywhere.proto.v1.LoRARemoveRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetRequest
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.extensions.AndroidLoRA

/**
 * LoRA adapters layered onto the loaded base model.
 *
 * ```kotlin
 * RunAnywhere.lora.apply("chat-style-v2", scale = 0.8f)
 * println(RunAnywhere.lora.list().applied)
 * ```
 */
public class LoraNamespace internal constructor() {
    /**
     * Layer the registered adapter [adapterId] onto the loaded base model,
     * downloading its weights first when they are absent.
     *
     * @throws SDKException when the adapter is unknown or incompatible.
     */
    public suspend fun apply(adapterId: String, scale: Float? = null) {
        val legacy = AndroidLoRA
        val entry =
            legacy.getCatalogEntry(LoraAdapterCatalogGetRequest(adapter_id = adapterId)).entry
                ?: throw SDKException.modelNotFound(adapterId)
        val path =
            entry.local_path?.takeIf { it.isNotBlank() }
                ?: legacy.download(entry)
        val result =
            legacy.apply(
                LoRAApplyRequest(
                    adapters =
                        listOf(
                            LoRAAdapterConfig(
                                adapter_path = path,
                                adapter_id = adapterId,
                                scale = scale ?: entry.default_scale.takeIf { it > 0f } ?: 1f,
                            ),
                        ),
                ),
            )
        if (!result.success) {
            throw SDKException.operation(
                result.error_message?.takeIf { it.isNotBlank() } ?: "LoRA apply failed",
            )
        }
    }

    /**
     * Peel off [adapterId], or every applied adapter when null.
     *
     * @throws SDKException when the removal fails.
     */
    public suspend fun remove(adapterId: String? = null) {
        val request =
            if (adapterId == null) {
                LoRARemoveRequest(clear_all = true)
            } else {
                LoRARemoveRequest(adapter_ids = listOf(adapterId))
            }
        AndroidLoRA.remove(request)
    }

    /** Which adapters are applied, and at what scale. */
    public suspend fun list(): LoraState = AndroidLoRA.list().toLoraState()
}
