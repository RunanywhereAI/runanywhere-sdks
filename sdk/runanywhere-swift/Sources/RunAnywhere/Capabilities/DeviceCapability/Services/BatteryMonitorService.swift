import Foundation
#if os(iOS)
import UIKit
#endif

/// Service for monitoring device battery state
public actor BatteryMonitorService {
    private let logger = SDKLogger(category: "BatteryMonitor")

    public init() {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
    }

    /// Get current battery information
    public func getBatteryInfo() -> BatteryInfo? {
        #if os(iOS)
        let device = UIDevice.current
        guard device.isBatteryMonitoringEnabled else { return nil }

        return BatteryInfo(
            level: device.batteryLevel,
            state: BatteryState(from: device.batteryState),
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        #else
        // Battery monitoring not available on macOS/tvOS/watchOS
        return nil
        #endif
    }

    /// Check if device is in low power mode
    public func isLowPowerMode() -> Bool {
        #if os(iOS)
        return ProcessInfo.processInfo.isLowPowerModeEnabled
        #else
        return false
        #endif
    }
}
