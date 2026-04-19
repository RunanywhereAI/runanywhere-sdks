package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.types.NPUChip
import com.runanywhere.sdk.public.RunAnywhere

/**
 * JVM stub — NPU chip detection is not applicable on desktop.
 */
actual fun RunAnywhere.getChip(): NPUChip? = null
