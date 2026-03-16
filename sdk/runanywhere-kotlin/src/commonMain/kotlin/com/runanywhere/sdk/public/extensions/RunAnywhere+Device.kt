package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.types.NPUChip
import com.runanywhere.sdk.public.RunAnywhere

/**
 * Detect the device's NPU chipset for Genie model compatibility.
 *
 * Returns the [NPUChip] if the device has a supported Qualcomm SoC,
 * or null if the device does not support NPU inference.
 *
 * Use [NPUChip.identifier] to construct chipset-specific download URLs:
 * ```kotlin
 * val chip = RunAnywhere.getChip()
 * if (chip != null) {
 *     val url = "https://example.com/models/qwen-${chip.identifier}.zip"
 *     RunAnywhere.registerModel(id = "qwen-npu", name = "Qwen NPU", url = url, ...)
 * }
 * ```
 */
expect fun RunAnywhere.getChip(): NPUChip?
