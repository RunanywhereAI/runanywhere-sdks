// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

package com.runanywhere.sdk.`public`.extensions

import com.runanywhere.sdk.core.types.NPUChip
import com.runanywhere.sdk.`public`.RunAnywhere

/// Detect the device's NPU chip, or null if unsupported. Sample apps use
/// this to filter their displayed model list to only those that will
/// actually run on the current hardware.
fun RunAnywhere.getChip(): NPUChip? {
    val detected = NPUChip.detect()
    return if (detected == NPUChip.UNKNOWN) null else detected
}
