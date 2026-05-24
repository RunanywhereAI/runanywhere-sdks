/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public LLM type aliases.
 *
 * The concrete public data contract lives in generated Wire types from
 * idl/llm_options.proto. Keep this file as an import-stability shim only.
 */

package com.runanywhere.sdk.public.extensions.LLM

typealias LLMConfiguration = ai.runanywhere.proto.v1.LLMConfiguration
typealias ThinkingTagPattern = ai.runanywhere.proto.v1.ThinkingTagPattern
