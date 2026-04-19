package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.types.NPUChip
import com.runanywhere.sdk.public.RunAnywhere

/**
 * Detect the device's NPU chipset for Genie model compatibility.
 *
 * Returns the [NPUChip] if the device has a supported Qualcomm SoC,
 * or null if the device does not support NPU inference.
 *
 * Use [NPUChip.downloadUrl] to construct chipset-specific download URLs:
 * ```kotlin
 * val chip = RunAnywhere.getChip()
 * if (chip != null) {
 *     val url = chip.downloadUrl("qwen3-4b")
 *     RunAnywhere.registerModel(id = "qwen3-4b-npu", name = "Qwen3 4B NPU", url = url, ...)
 * }
 * ```
 */
expect fun RunAnywhere.getChip(): NPUChip?
