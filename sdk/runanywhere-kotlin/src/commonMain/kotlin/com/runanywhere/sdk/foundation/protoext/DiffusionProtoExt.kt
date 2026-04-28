/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Extension helpers for the proto-canonical Diffusion types
 * (ai.runanywhere.proto.v1.{DiffusionTokenizerSource, DiffusionTokenizerSourceKind,
 *  DiffusionConfiguration, DiffusionGenerationOptions, DiffusionResult,
 *  DiffusionMode, DiffusionScheduler, DiffusionModelVariant}).
 *
 * Wire generates a flat `kind + custom_path` for DiffusionTokenizerSource;
 * the legacy hand-rolled type was a sealed class. These extensions provide
 * idiomatic factories and a pattern-matching helper.
 */

package com.runanywhere.sdk.foundation.protoext

import ai.runanywhere.proto.v1.DiffusionTokenizerSource
import ai.runanywhere.proto.v1.DiffusionTokenizerSourceKind

// ============================================================================
// DiffusionTokenizerSource factories
// ============================================================================

/** Factory for the bundled SD 1.5 tokenizer (CLIP ViT-L/14). */
fun diffusionTokenizerSd15(): DiffusionTokenizerSource =
    DiffusionTokenizerSource(kind = DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15)

/** Factory for the bundled SD 2.x tokenizer (OpenCLIP ViT-H/14). */
fun diffusionTokenizerSd2(): DiffusionTokenizerSource =
    DiffusionTokenizerSource(kind = DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2)

/** Factory for the bundled SDXL tokenizer (dual). */
fun diffusionTokenizerSdxl(): DiffusionTokenizerSource =
    DiffusionTokenizerSource(kind = DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL)

/**
 * Factory for a custom tokenizer base URL. The URL should point at a
 * directory containing `merges.txt` and `vocab.json`.
 */
fun diffusionTokenizerCustom(baseUrl: String): DiffusionTokenizerSource =
    DiffusionTokenizerSource(
        kind = DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM,
        custom_path = baseUrl,
    )

// ============================================================================
// DiffusionTokenizerSource computed properties
// ============================================================================

/**
 * The base URL for downloading tokenizer files. Returns the bundled HF URL
 * for the BUNDLED_* presets, or the developer-supplied custom_path.
 */
val DiffusionTokenizerSource.baseUrl: String
    get() =
        when (kind) {
            DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15 ->
                "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer"
            DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2 ->
                "https://huggingface.co/stabilityai/stable-diffusion-2-1/resolve/main/tokenizer"
            DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL ->
                "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/tokenizer"
            DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM ->
                custom_path ?: ""
            DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED -> ""
        }

/** Human-readable description of this tokenizer source. */
val DiffusionTokenizerSource.description: String
    get() =
        when (kind) {
            DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15 -> "Stable Diffusion 1.5 (CLIP)"
            DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2 -> "Stable Diffusion 2.x (OpenCLIP)"
            DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL -> "Stable Diffusion XL"
            DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM -> "Custom (${custom_path ?: "unset"})"
            DiffusionTokenizerSourceKind.DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED -> "Unspecified"
        }
