/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for proto-backed model and component lifecycle.
 *
 * Mirrors Swift sdk/runanywhere-swift/.../Models/RunAnywhere+ModelLifecycle.swift.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ComponentLifecycleSnapshot
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.ModelUnloadResult
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RAModelLoadResult

// MARK: - Lifecycle Operations

expect suspend fun RunAnywhere.loadModel(request: RAModelLoadRequest): RAModelLoadResult

expect suspend fun RunAnywhere.unloadModel(request: ModelUnloadRequest): ModelUnloadResult

expect suspend fun RunAnywhere.currentModel(request: CurrentModelRequest = CurrentModelRequest()): CurrentModelResult

expect suspend fun RunAnywhere.componentLifecycleSnapshot(component: SDKComponent): ComponentLifecycleSnapshot

// MARK: - Model Assignments
// `fetchModelAssignments` was deleted in the dead-code wave (KOT-DEAD).
// The legacy path was a JSON adapter over `racModelAssignmentFetch`.
// Use `refreshModelRegistry(includeRemoteCatalog = true)` followed by
// `availableModels()` to drive the proto-backed catalog refresh instead.
