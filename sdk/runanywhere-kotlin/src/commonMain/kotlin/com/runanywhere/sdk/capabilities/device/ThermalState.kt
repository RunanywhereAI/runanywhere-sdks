package com.runanywhere.sdk.capabilities.device

/**
 * Device thermal state
 *
 * Matches iOS: ProcessInfo.ThermalState
 */
enum class ThermalState {
    /**
     * The thermal state is within normal limits.
     */
    NOMINAL,

    /**
     * The thermal state is slightly elevated.
     */
    FAIR,

    /**
     * The thermal state is high.
     */
    SERIOUS,

    /**
     * The thermal state is critical.
     */
    CRITICAL;

    /**
     * Whether the thermal state allows heavy processing
     */
    val allowsHeavyProcessing: Boolean
        get() = this == NOMINAL || this == FAIR

    /**
     * Whether the device should throttle operations
     */
    val shouldThrottle: Boolean
        get() = this == SERIOUS || this == CRITICAL
}
