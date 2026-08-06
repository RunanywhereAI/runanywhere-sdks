/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: `RunAnywhere.lora`.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.LoraAdapterConfig
import ai.runanywhere.proto.v1.LoraApplyRequest
import ai.runanywhere.proto.v1.LoraRemoveRequest
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
     * Layer the registered adapter [adapterId] onto the loaded base model.
     *
     * `LoraAdapterCatalogEntry` carries no URL/artifact metadata any more
     * (idl/lora_options.proto: "everything generic about the artifact ...
     * lives on the ModelInfo record for this adapter") and the LoRA-domain
     * download bookkeeping ABI was retired outright, so this no longer
     * auto-downloads on a cache miss -- callers download through
     * [com.runanywhere.sdk.public.extensions.LoRA.download] (or the models
     * domain directly) first, which stamps the catalog entry's `local_path`.
     * Mirrors Swift's simplified `LoraNamespace.apply(adapterId:scale:)`.
     *
     * @throws SDKException when the adapter is unknown, not yet downloaded,
     *   or incompatible.
     */
    public suspend fun apply(adapterId: String, scale: Float? = null) {
        val legacy = AndroidLoRA
        val entry =
            legacy.getCatalogEntry(LoraAdapterCatalogGetRequest(adapter_id = adapterId)).entry
                ?: throw SDKException.modelNotFound(adapterId)
        val path =
            entry.local_path?.takeIf { it.isNotBlank() }
                ?: throw SDKException.invalidArgument(
                    "LoRA adapter '$adapterId' has no local path; download it first",
                )
        val result =
            legacy.apply(
                LoraApplyRequest(
                    adapters =
                        listOf(
                            LoraAdapterConfig(
                                adapter_path = path,
                                adapter_id = adapterId,
                                scale = scale ?: entry.default_scale?.takeIf { it > 0f } ?: 1f,
                            ),
                        ),
                ),
            )
        if (result.error != null) {
            throw SDKException.operation(
                result.error!!.message.takeIf { it.isNotBlank() } ?: "LoRA apply failed",
            )
        }
    }

    /**
     * Peel off [adapterId].
     *
     * @throws SDKException when the removal fails.
     */
    public suspend fun remove(adapterId: String) {
        AndroidLoRA.remove(LoraRemoveRequest(adapter_ids = listOf(adapterId)))
    }

    /**
     * Peel off every applied adapter.
     *
     * @throws SDKException when the removal fails.
     */
    public suspend fun removeAll() {
        AndroidLoRA.remove(LoraRemoveRequest(clear_all = true))
    }

    /**
     * @deprecated Use [remove] with an explicit id, or [removeAll]. A null
     *   [adapterId] forwards to [removeAll].
     */
    @JvmName("removeOrClear")
    @Deprecated("Use remove(adapterId) or removeAll().")
    public suspend fun remove(adapterId: String? = null) {
        if (adapterId == null) removeAll() else remove(adapterId)
    }

    /** Which adapters are applied, and at what scale. */
    public suspend fun list(): LoraState = AndroidLoRA.list().toLoraState()
}
