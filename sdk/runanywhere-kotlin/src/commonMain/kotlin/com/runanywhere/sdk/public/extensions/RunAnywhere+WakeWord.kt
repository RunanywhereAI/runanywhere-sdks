/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for Wake Word detection (P2 feature B11).
 *
 * Mirrors Swift's `RunAnywhere+WakeWord.swift` shape. The native C ABI
 * `rac_wake_word_init / rac_wake_word_process / rac_wake_word_destroy`
 * exists in runanywhere-commons but is currently stubbed and returns
 * `RAC_ERROR_FEATURE_NOT_AVAILABLE`. Until the native pipeline is
 * wired, the `jvmAndroidMain` actual for [detectWakeWord] throws
 * `SDKException.notImplemented(...)`; `loadWakeWordModel` and
 * `unloadWakeWordModel` are the canonical load/unload triple.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere

// ─────────────────────────────────────────────────────────────────────────────
// Wake-word lifecycle — canonical §6 shape: load → detect → unload.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Load a wake-word model from disk.
 *
 * Mirrors Swift's `RunAnywhere.wakeWord.load(modelPath:)`.
 *
 * @param modelPath Absolute path to a wake-word model file
 *   (Porcupine / OpenWakeWord / pv-keyword blob).
 */
expect suspend fun RunAnywhere.loadWakeWordModel(modelPath: String)

/**
 * Run wake-word detection over a PCM buffer.
 *
 * Mirrors Swift's `RunAnywhere.wakeWord.detect(audio:)`.
 *
 * @param audio Raw PCM bytes. Native commons expects 16 kHz mono
 *   `float` samples; the public facade accepts `ByteArray` so call
 *   sites do not need to depend on the C ABI layout.
 * @return `true` when the wake-word was detected in the buffer.
 */
expect suspend fun RunAnywhere.detectWakeWord(audio: ByteArray): Boolean

/**
 * Unload the currently loaded wake-word model and release all
 * native resources. Safe to call when no model is loaded.
 *
 * Mirrors Swift's `RunAnywhere.wakeWord.unload()`.
 */
expect suspend fun RunAnywhere.unloadWakeWordModel()
