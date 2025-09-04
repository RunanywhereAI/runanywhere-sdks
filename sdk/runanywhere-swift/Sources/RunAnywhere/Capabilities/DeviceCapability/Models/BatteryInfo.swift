import Foundation

/// Battery information for device power status
public struct BatteryInfo: Codable, Sendable {
    /// Battery level from 0.0 to 1.0 (nil if unknown)
    public let level: Float?
    /// Current battery state
    public let state: BatteryState
    /// Whether the device is in low power mode
    public let isLowPowerModeEnabled: Bool

    /// Check if battery is low (less than 20%)
    public var isLowBattery: Bool {
        guard let level = level else { return false }
        return level < 0.2
    }

    /// Check if battery is critical (less than 10%)
    public var isCriticalBattery: Bool {
        guard let level = level else { return false }
        return level < 0.1
    }

    public init(
        level: Float?,
        state: BatteryState,
        isLowPowerModeEnabled: Bool = false
    ) {
        self.level = level
        self.state = state
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }
}

/// Battery charging state
public enum BatteryState: String, Codable, Sendable {
    case unknown
    case unplugged
    case charging
    case full
}

#if canImport(UIKit)
import UIKit

extension BatteryState {
    /// Initialize from UIDevice battery state
    init(from deviceState: UIDevice.BatteryState) {
        switch deviceState {
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
}
#endif
