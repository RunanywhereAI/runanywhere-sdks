/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public proto-backed model registry API.
 *
 * Mirrors Swift sdk/runanywhere-swift/.../Models/RunAnywhere+ModelRegistry.swift:
 *   - listModels(request: ModelListRequest = ModelListRequest()) -> ModelListResult
 *   - queryModels(query: ModelQuery) -> ModelListResult
 *   - getModel(request: ModelGetRequest) -> ModelGetResult
 *   - downloadedModels() -> ModelListResult
 *
 * Internal helper `registerModelInternal` is retained because the LoRA
 * adapter registration and the Android System TTS module both seed the
 * proto registry through it. It is not part of Swift's public surface.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ModelGetRequest
import ai.runanywhere.proto.v1.ModelGetResult
import ai.runanywhere.proto.v1.ModelListRequest
import ai.runanywhere.proto.v1.ModelListResult
import ai.runanywhere.proto.v1.ModelQuery
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAModelInfo

// MARK: - Registry Discovery (Swift parity)

/** Mirrors Swift `RunAnywhere.listModels(_:)`. */
expect suspend fun RunAnywhere.listModels(request: ModelListRequest = ModelListRequest()): ModelListResult

/** Mirrors Swift `RunAnywhere.queryModels(_:)`. */
expect suspend fun RunAnywhere.queryModels(query: ModelQuery): ModelListResult

/** Mirrors Swift `RunAnywhere.getModel(_:)`. */
expect suspend fun RunAnywhere.getModel(request: ModelGetRequest): ModelGetResult

/** Mirrors Swift `RunAnywhere.downloadedModels()`. */
expect suspend fun RunAnywhere.downloadedModels(): ModelListResult

// MARK: - Internal Registration Helper
//
// Not in Swift's `RunAnywhere+ModelRegistry.swift`. Retained because the
// LoRA adapter flow (`RunAnywhere+LoRA.registerLoraArtifact`) and Android's
// `SystemTTSModule` both push synthetic ModelInfo entries through this
// path. Public callers should go through the registerModel API (when
// re-introduced under a Storage-aligned extension that mirrors Swift's
// `RunAnywhere+Storage.swift`).
internal expect fun registerModelInternal(modelInfo: RAModelInfo)
