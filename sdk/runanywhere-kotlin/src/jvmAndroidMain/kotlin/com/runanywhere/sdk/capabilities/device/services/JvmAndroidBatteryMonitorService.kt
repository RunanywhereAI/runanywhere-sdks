package com.runanywhere.sdk.capabilities.device.services

import com.runanywhere.sdk.capabilities.device.BatteryInfo
import com.runanywhere.sdk.capabilities.device.BatteryState

/**
 * JVM/Android shared base implementation of BatteryMonitorService
 *
 * Note: This base implementation returns unknown battery state.
 * Android-specific code in androidMain can extend this with actual battery monitoring.
 */
open class JvmAndroidBatteryMonitorService : BatteryMonitorService {

    override fun getBatteryInfo(): BatteryInfo? {
        // Desktop JVM has no battery monitoring
        // Android will override with actual implementation
        return null
    }

    override fun isLowPowerMode(): Boolean {
        // Desktop JVM has no low power mode concept
        // Android will override with actual implementation
        return false
    }
}

/**
 * Factory function for creating BatteryMonitorService on JVM/Android
 */
actual fun createBatteryMonitorService(): BatteryMonitorService {
    return JvmAndroidBatteryMonitorService()
}
