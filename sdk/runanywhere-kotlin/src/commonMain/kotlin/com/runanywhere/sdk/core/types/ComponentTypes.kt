package com.runanywhere.sdk.core.types

import ai.runanywhere.proto.v1.InferenceFramework

/**
 * Protocol for component configuration and initialization.
 *
 * Component schemas are generated from proto; this interface only preserves
 * Kotlin's common configuration contract across component implementations.
 */
interface ComponentConfiguration {
    val modelId: String?
    val preferredFramework: InferenceFramework?
}

/**
 * Protocol for component output data.
 *
 * Generated proto result types own public payload schemas; this remains a
 * narrow Kotlin contract for outputs that need a common timestamp.
 */
interface ComponentOutput {
    val timestamp: Long
}
