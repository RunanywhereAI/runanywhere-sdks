/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * RAVADTypesCppBridge.kt
 *
 * C-bridge extensions on proto-generated RA* VAD types.
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/RAVADTypes+CppBridge.swift`.
 * Pure ergonomic accessors / aliases; no JNI. Statistics-side helpers live
 * in `RAVADConfigurationHelpers.kt` (in `public.extensions.VAD`).
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.VADConfiguration
import com.runanywhere.sdk.public.types.RAVADResult

// MARK: - RAVADConfiguration

/**
 * Returns the configuration's `model_id` or `null` when it's the proto3
 * default (empty string). Mirrors Swift `RAVADConfiguration.modelId`.
 */
val VADConfiguration.modelIdOrNull: String?
    get() = model_id.takeIf { it.isNotEmpty() }

// MARK: - RAVADResult: convenience aliases

/**
 * Alias for `is_speech` matching Swift `RAVADResult.isSpeechDetected`.
 */
val RAVADResult.isSpeechDetected: Boolean
    get() = is_speech

/**
 * Alias for `energy` matching Swift `RAVADResult.energyLevel`.
 */
val RAVADResult.energyLevel: Float
    get() = energy
