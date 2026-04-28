/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Extension helpers for the proto-canonical Storage types
 * (ai.runanywhere.proto.v1.{DeviceStorageInfo, AppStorageInfo, StorageInfo,
 *  ModelStorageMetrics, StoredModel, StorageAvailability, NPUChip}).
 *
 * Note: DeviceStorageInfo.used_percent is materialized in the proto (not
 * computed) so consumers across all SDKs see the same value even when
 * total_bytes == 0. Use [DeviceStorageInfo.computedUsagePercentage] when
 * an always-fresh recomputed value is preferred.
 */

package com.runanywhere.sdk.foundation.protoext

import ai.runanywhere.proto.v1.DeviceStorageInfo
import ai.runanywhere.proto.v1.StorageInfo

/**
 * Compute a fresh used-storage percentage from total / used bytes.
 * Returns 0.0 if total_bytes == 0.
 */
val DeviceStorageInfo.computedUsagePercentage: Float
    get() = if (total_bytes > 0) (used_bytes.toFloat() / total_bytes.toFloat()) * 100f else 0f

/** Total bytes of all models on disk. */
val StorageInfo.totalModelBytes: Long
    get() = if (total_models_bytes != 0L) total_models_bytes else models.sumOf { it.size_on_disk_bytes }

/** Number of stored models. */
val StorageInfo.modelCount: Int
    get() = if (total_models != 0) total_models else models.size
