/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public download API mirroring Swift `RunAnywhere.downloadModel(...)` in
 * `RunAnywhere+Storage.swift`. Executes the canonical plan → start → poll
 * pattern over `CppBridge.Download`.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.DownloadProgress
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.flow.Flow

/**
 * Download a model to local storage.
 *
 * Returns a cold [Flow] of [DownloadProgress] updates. Collect the flow until it
 * completes (terminal `DOWNLOAD_STATE_COMPLETED`) or throws.
 *
 * Mirrors Swift `RunAnywhere.downloadModel(_:onProgress:)` which executes:
 *   1. `CppBridge.Download.plan(planRequest)` to create a download plan.
 *   2. `CppBridge.Download.start(startRequest)` with the plan.
 *   3. Polls `CppBridge.Download.pollProgress(...)` every 250 ms until terminal.
 */
expect fun RunAnywhere.downloadModel(model: RAModelInfo): Flow<DownloadProgress>
