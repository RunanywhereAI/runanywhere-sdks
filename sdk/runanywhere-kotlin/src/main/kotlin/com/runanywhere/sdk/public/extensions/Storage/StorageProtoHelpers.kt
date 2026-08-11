/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical Storage proto types. Mirrors the Swift
 * counterpart at
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Storage/StorageProto+Helpers.swift`.
 *
 * The `RA*` typealiases land in workstream L2; for now these helpers operate
 * on the Wire-generated proto types directly.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.AppStorageInfo
import ai.runanywhere.proto.v1.DeviceStorageInfo
import ai.runanywhere.proto.v1.ModelStorageMetrics
import ai.runanywhere.proto.v1.StorageAvailability
import ai.runanywhere.proto.v1.StorageInfo
import com.runanywhere.sdk.public.types.RAStorageInfo

// MARK: - DeviceStorageInfo

/**
 * Build a [DeviceStorageInfo] from the three canonical byte counters.
 *
 * Matches Swift's
 * `RADeviceStorageInfo.init(totalBytes:freeBytes:usedBytes:)`.
 */
fun DeviceStorageInfo.Companion.create(
    totalBytes: Long,
    freeBytes: Long,
    usedBytes: Long,
): DeviceStorageInfo =
    DeviceStorageInfo(
        total_bytes = totalBytes,
        free_bytes = freeBytes,
        used_bytes = usedBytes,
    )

// MARK: - AppStorageInfo

/**
 * Build an [AppStorageInfo] from the four canonical byte counters.
 *
 * Per `swift.md SWIFT-DUP-STORAGE-ALIASES` the legacy `documentsSize` /
 * `cacheSize` / `appSupportSize` / `totalSize` aliases were removed —
 * callers should use the canonical proto field names (`documents_bytes`
 * / `cache_bytes` / `app_support_bytes` / `total_bytes`).
 */
fun AppStorageInfo.Companion.create(
    documentsBytes: Long,
    cacheBytes: Long,
    appSupportBytes: Long,
    totalBytes: Long,
): AppStorageInfo =
    AppStorageInfo(
        documents_bytes = documentsBytes,
        cache_bytes = cacheBytes,
        app_support_bytes = appSupportBytes,
        total_bytes = totalBytes,
    )

// MARK: - StorageInfo

/**
 * An empty [StorageInfo] with default device/app sub-records and no
 * per-model rows. Matches Swift's `RAStorageInfo.empty` static.
 */
val StorageInfo.Companion.empty: RAStorageInfo
    get() =
        RAStorageInfo(
            app = AppStorageInfo(),
            device = DeviceStorageInfo(),
            models = emptyList(),
            total_models_bytes = 0L,
        )

// MARK: - ModelStorageMetrics

/**
 * Build a [ModelStorageMetrics] entry.
 *
 * `last_used_ms` is deleted outright (idl/storage_types.proto): this
 * metrics record now carries only `model_id` + `size_on_disk_bytes`.
 */
fun ModelStorageMetrics.Companion.create(
    modelId: String,
    sizeOnDiskBytes: Long,
): ModelStorageMetrics =
    ModelStorageMetrics(
        model_id = modelId,
        size_on_disk_bytes = sizeOnDiskBytes,
    )

// MARK: - StorageAvailability

/**
 * Build a [StorageAvailability] result. Mirrors Swift's
 * `RAStorageAvailability.make(isAvailable:requiredBytes:availableBytes:recommendation:)`.
 */
fun StorageAvailability.Companion.create(
    isAvailable: Boolean,
    requiredBytes: Long,
    availableBytes: Long,
    recommendation: String? = null,
): StorageAvailability =
    StorageAvailability(
        is_available = isAvailable,
        required_bytes = requiredBytes,
        available_bytes = availableBytes,
        recommendation = recommendation,
    )
