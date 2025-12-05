package com.runanywhere.sdk.capabilities.device.services

import com.runanywhere.sdk.capabilities.device.ThermalState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * JVM/Android shared base implementation of ThermalMonitorService
 *
 * Note: This base implementation returns NOMINAL thermal state.
 * Android-specific code in androidMain can extend this with actual thermal monitoring.
 */
open class JvmAndroidThermalMonitorService : ThermalMonitorService {

    private val thermalStateFlow = MutableStateFlow(ThermalState.NOMINAL)

    override fun getCurrentThermalState(): ThermalState {
        // Desktop JVM has no thermal state monitoring
        // Android can override with PowerManager.getThermalHeadroom() on API 29+
        return ThermalState.NOMINAL
    }

    override fun observeThermalStateChanges(): Flow<ThermalState> {
        // Return a flow that emits NOMINAL
        // Android can override with actual thermal state updates
        return thermalStateFlow.asStateFlow()
    }
}

/**
 * Factory function for creating ThermalMonitorService on JVM/Android
 */
actual fun createThermalMonitorService(): ThermalMonitorService {
    return JvmAndroidThermalMonitorService()
}
