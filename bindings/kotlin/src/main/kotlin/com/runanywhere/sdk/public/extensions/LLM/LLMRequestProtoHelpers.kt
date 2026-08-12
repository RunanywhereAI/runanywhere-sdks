/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public request helpers for canonical LLM proto types.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.types.RALLMGenerateRequest
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.foundation.bridge.extensions.toRALLMGenerateRequest as toCppGenerateRequest

/**
 * Build the canonical generation request for these options and [prompt].
 * Mirrors Swift's public `RALLMGenerationOptions.toRALLMGenerateRequest` helper.
 */
fun RALLMGenerationOptions.toRALLMGenerateRequest(prompt: String): RALLMGenerateRequest =
    this.toCppGenerateRequest(prompt)
