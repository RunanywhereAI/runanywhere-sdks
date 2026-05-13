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
import ai.runanywhere.proto.v1.StoredModel
import com.runanywhere.sdk.public.types.RAStorageInfo

// MARK: - DeviceStorageInfo

/**
 * Build a [DeviceStorageInfo] computing `used_percent` from the supplied
 * counters (matching Swift's behavior of materializing the percentage on
 * the producer side so every binding reports the same value).
 */
fun DeviceStorageInfo.Companion.create(
    totalBytes: Long,
    freeBytes: Long,
    usedBytes: Long,
): DeviceStorageInfo {
    val usedPercent =
        if (totalBytes > 0L) {
            (usedBytes.toDouble() / totalBytes.toDouble() * 100.0).toFloat()
        } else {
            0f
        }
    return DeviceStorageInfo(
        total_bytes = totalBytes,
        free_bytes = freeBytes,
        used_bytes = usedBytes,
        used_percent = usedPercent,
    )
}

/**
 * Recomputed usage percentage as a Double (0.0–100.0). Equivalent to
 * `used_percent` but returned as `Double` to match the Swift API.
 */
val DeviceStorageInfo.usagePercentage: Double
    get() =
        if (total_bytes > 0L) {
            used_bytes.toDouble() / total_bytes.toDouble() * 100.0
        } else {
            0.0
        }

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
            total_models = 0,
            total_models_bytes = 0L,
        )

/** Sum of `size_on_disk_bytes` across all per-model rows. */
val RAStorageInfo.totalModelsSizeBytes: Long
    get() = models.sumOf { it.size_on_disk_bytes }

/**
 * Aggregate "models size" — prefers the denormalized `total_models_bytes`
 * counter, falls back to a fresh sum over the rows when the counter is 0.
 */
val RAStorageInfo.totalModelsSize: Long
    get() = if (total_models_bytes > 0L) total_models_bytes else totalModelsSizeBytes

/** Number of model rows currently in the storage view. */
val RAStorageInfo.modelCount: Int
    get() = models.size

/**
 * Project the per-model storage rows into the legacy `StoredModel` view
 * Swift, Flutter, and React Native call sites consume.
 */
val RAStorageInfo.storedModels: List<StoredModel>
    get() =
        models.map { metrics ->
            StoredModel(
                model_id = metrics.model_id,
                name = metrics.model_id,
                size_bytes = metrics.size_on_disk_bytes,
            )
        }

// MARK: - ModelStorageMetrics

/**
 * Build a [ModelStorageMetrics] entry, optionally stamped with the Unix
 * epoch milliseconds of the last load.
 */
fun ModelStorageMetrics.Companion.create(
    modelId: String,
    sizeOnDiskBytes: Long,
    lastUsedMs: Long? = null,
): ModelStorageMetrics =
    ModelStorageMetrics(
        model_id = modelId,
        size_on_disk_bytes = sizeOnDiskBytes,
        last_used_ms = lastUsedMs,
    )

// MARK: - StoredModel

/** Alias for `size_bytes` to match the Swift `size` accessor. */
val StoredModel.size: Long
    get() = size_bytes

/**
 * Local file path string. Returns `"/unknown"` when the underlying
 * `local_path` is empty, matching the Swift fallback.
 */
val StoredModel.path: String
    get() = if (local_path.isEmpty()) "/unknown" else local_path

/**
 * Created (download-completed) timestamp as Unix epoch ms. Returns 0L when
 * the proto field is absent — Kotlin can't return a `Date` here, so the
 * consumer can convert to `Instant`/`Date` itself.
 */
val StoredModel.createdDate: Long
    get() = downloaded_at_ms ?: 0L

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
