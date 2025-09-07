package com.runanywhere.sdk.models

import kotlinx.serialization.Serializable

/**
 * Execution target for model inference - exact match with iOS ExecutionTarget
 */
@Serializable
enum class ExecutionTarget(val value: String) {
    /** Execute on device */
    ON_DEVICE("onDevice"),

    /** Execute in the cloud */
    CLOUD("cloud"),

    /** Hybrid execution (partial on-device, partial cloud) */
    HYBRID("hybrid");

    companion object {
        fun fromValue(value: String): ExecutionTarget? {
            return values().find { it.value == value }
        }
    }
}
