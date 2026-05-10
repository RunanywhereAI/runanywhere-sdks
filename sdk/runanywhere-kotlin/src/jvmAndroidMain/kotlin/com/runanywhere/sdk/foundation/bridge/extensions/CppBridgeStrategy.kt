/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Strategy bridge extension for C++ interop.
 *
 * Mirrors the model-selection-heuristics + archive-type conversion
 * surface that Swift exposes via `CppBridge+Strategy.swift`. The Swift
 * file is responsible for two things today:
 *  1. Converting between Swift `ArchiveType` / `ArchiveStructure` enums
 *     and their `rac_archive_*` C ABI counterparts.
 *  2. Acting as the namespace future model-selection helpers will hang
 *     off of (currently the C++ side owns all of that logic).
 *
 * Mirrors iOS source of truth:
 *   sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/
 *     CppBridge+Strategy.swift
 *
 * NOTE (B18): no `racStrategy*` JNI bindings exist in `RunAnywhereBridge`
 * yet — the model-selection helpers are stubs pending the commons
 * follow-up that exposes `rac_strategy_*` over JNI. The archive-type
 * conversions are wired up against the existing Wire-generated proto
 * enums so callers can already use them.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType

/**
 * Bridge for model-selection heuristics and archive-type conversions.
 *
 * Mirrors Swift's `ArchiveType.toC()` / `ArchiveType.init(from:)` and
 * `ArchiveStructure.toC()` / `ArchiveStructure.init(from:)` extension
 * methods. The C ABI represents both as plain ints — the same shape
 * Wire uses for its proto enums — so the conversion is just a value
 * mapping.
 *
 * Thread safety: pure functions, no shared state.
 */
object CppBridgeStrategy {

    // ────────────────────────────────────────────────────────────────────────
    // Archive type ↔ C ABI conversion
    // ────────────────────────────────────────────────────────────────────────

    /**
     * Convert a Wire-generated [ArchiveType] to its `rac_archive_type_t`
     * integer value. Falls back to ZIP for unknown / unspecified inputs,
     * matching Swift's default-arm in `CppBridge+Strategy.swift`.
     */
    fun archiveTypeToC(type: ArchiveType): Int =
        when (type) {
            ArchiveType.ARCHIVE_TYPE_ZIP -> RAC_ARCHIVE_TYPE_ZIP
            ArchiveType.ARCHIVE_TYPE_TAR_BZ2 -> RAC_ARCHIVE_TYPE_TAR_BZ2
            ArchiveType.ARCHIVE_TYPE_TAR_GZ -> RAC_ARCHIVE_TYPE_TAR_GZ
            ArchiveType.ARCHIVE_TYPE_TAR_XZ -> RAC_ARCHIVE_TYPE_TAR_XZ
            ArchiveType.ARCHIVE_TYPE_UNSPECIFIED -> RAC_ARCHIVE_TYPE_ZIP
        }

    /**
     * Convert a `rac_archive_type_t` integer back to a Wire
     * [ArchiveType], or `null` for unknown values. Mirrors Swift's
     * failable `init(from cType:)` initializer.
     */
    fun archiveTypeFromC(cType: Int): ArchiveType? =
        when (cType) {
            RAC_ARCHIVE_TYPE_ZIP -> ArchiveType.ARCHIVE_TYPE_ZIP
            RAC_ARCHIVE_TYPE_TAR_BZ2 -> ArchiveType.ARCHIVE_TYPE_TAR_BZ2
            RAC_ARCHIVE_TYPE_TAR_GZ -> ArchiveType.ARCHIVE_TYPE_TAR_GZ
            RAC_ARCHIVE_TYPE_TAR_XZ -> ArchiveType.ARCHIVE_TYPE_TAR_XZ
            else -> null
        }

    // ────────────────────────────────────────────────────────────────────────
    // Archive structure ↔ C ABI conversion
    // ────────────────────────────────────────────────────────────────────────

    /**
     * Convert a Wire-generated [ArchiveStructure] to its
     * `rac_archive_structure_t` integer value. Unknown / unspecified
     * inputs fall through to UNKNOWN, matching Swift's default arm.
     */
    fun archiveStructureToC(structure: ArchiveStructure): Int =
        when (structure) {
            ArchiveStructure.ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED ->
                RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED
            ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED ->
                RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED
            ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY ->
                RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY
            ArchiveStructure.ARCHIVE_STRUCTURE_UNKNOWN,
            ArchiveStructure.ARCHIVE_STRUCTURE_UNSPECIFIED,
            -> RAC_ARCHIVE_STRUCTURE_UNKNOWN
        }

    /**
     * Convert a `rac_archive_structure_t` integer to a Wire
     * [ArchiveStructure]. Unknown values map to
     * `ARCHIVE_STRUCTURE_UNKNOWN`, matching Swift's non-failable
     * `init(from cStructure:)` initializer.
     */
    fun archiveStructureFromC(cStructure: Int): ArchiveStructure =
        when (cStructure) {
            RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED ->
                ArchiveStructure.ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED
            RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED ->
                ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED
            RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY ->
                ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY
            else -> ArchiveStructure.ARCHIVE_STRUCTURE_UNKNOWN
        }

    // ────────────────────────────────────────────────────────────────────────
    // Model-selection heuristics (placeholder)
    // ────────────────────────────────────────────────────────────────────────
    //
    // TODO(KOT-B18): no `racStrategy*` external funs exist in
    // `RunAnywhereBridge.kt` today. When the commons follow-up exposes
    // model-selection scoring (e.g. `rac_strategy_score_model`,
    // `rac_strategy_pick_runtime`) over JNI, add wrapper methods here
    // that mirror the Swift equivalents one-to-one.

    // Internal C ABI integer mirrors. These match the constants emitted
    // by `idl/codegen/generate_c.sh` for `rac_archive_type_t` and
    // `rac_archive_structure_t`. They live here rather than alongside
    // `RunAnywhereBridge` because Kotlin is the only consumer.
    private const val RAC_ARCHIVE_TYPE_ZIP: Int = 1
    private const val RAC_ARCHIVE_TYPE_TAR_BZ2: Int = 2
    private const val RAC_ARCHIVE_TYPE_TAR_GZ: Int = 3
    private const val RAC_ARCHIVE_TYPE_TAR_XZ: Int = 4

    private const val RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED: Int = 1
    private const val RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED: Int = 2
    private const val RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY: Int = 3
    private const val RAC_ARCHIVE_STRUCTURE_UNKNOWN: Int = 4
}
