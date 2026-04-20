// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// NPU chip identifier — used by the Android sample to gate which models
// can run on Qualcomm Hexagon NPU via Genie. Returned by
// `RunAnywhere.getChip()`.

package com.runanywhere.sdk.core.types

enum class NPUChip(
    val identifier: String,
    val displayName: String,
) {
    SNAPDRAGON_8_ELITE     ("sd8elite",      "Snapdragon 8 Elite"),
    SNAPDRAGON_8_ELITE_GEN5("sd8elitegen5",  "Snapdragon 8 Elite Gen 5"),
    SNAPDRAGON_X_ELITE     ("sdxelite",      "Snapdragon X Elite"),
    UNKNOWN                ("unknown",       "Unknown");

    /// HuggingFace URL for the given model slug + quantization on this
    /// chip. Mirrors the main-branch Genie model-catalog URL scheme.
    fun downloadUrl(slug: String, quant: String): String =
        "https://huggingface.co/runanywhere/$slug-$identifier-$quant/resolve/main/model.bin"

    companion object {
        @JvmStatic
        fun detect(): NPUChip = UNKNOWN
    }
}
