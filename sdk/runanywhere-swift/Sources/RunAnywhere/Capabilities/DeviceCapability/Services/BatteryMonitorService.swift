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

/// Battery information
public struct BatteryInfo: Codable {
    public let level: Float // 0.0 to 1.0
    public let state: BatteryState
    public let isLowPowerModeEnabled: Bool

    public var isLowBattery: Bool {
        level < 0.2 // Less than 20%
    }
}

/// Battery state enumeration
public enum BatteryState: String, Codable {
    case unknown = "unknown"
    case unplugged = "unplugged"
    case charging = "charging"
    case full = "full"

    #if os(iOS)
    init(from uiDeviceState: UIDevice.BatteryState) {
        switch uiDeviceState {
        case .unknown:
            self = .unknown
        case .unplugged:
            self = .unplugged
        case .charging:
            self = .charging
        case .full:
            self = .full
        @unknown default:
            self = .unknown
        }
    }
    #endif
}
