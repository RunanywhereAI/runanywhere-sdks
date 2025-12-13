//
//  TelemetryDeviceInfo.swift
//  RunAnywhere SDK
//
//  Helper to provide device information for telemetry events
//

import Foundation

/// Helper struct to provide device information for telemetry events
public struct TelemetryDeviceInfo: Sendable, Codable {
    /// Device model identifier (e.g., "iPhone", "Mac")
    public let device: String

    /// OS version string (e.g., "17.2")
    public let osVersion: String

    /// Platform identifier (e.g., "iOS", "macOS")
    public let platform: String

    /// Get current device info for telemetry
    public static var current: TelemetryDeviceInfo {
        let deviceInfo = DeviceInfo.current

        // Extract clean OS version (e.g., "17.2" from "Version 17.2 (Build 21C52)")
        let osVersion = extractOSVersion(from: deviceInfo.osVersion)

        return TelemetryDeviceInfo(
            device: deviceInfo.model,
            osVersion: osVersion,
            platform: deviceInfo.platform
        )
    }

    /// Cached regex for extracting OS version - compiled once for performance
    private static let versionRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(\d+\.\d+(?:\.\d+)?)"#)
    }()

    /// Extract clean OS version number from full version string
    private static func extractOSVersion(from fullVersion: String) -> String {
        guard let regex = versionRegex,
              let match = regex.firstMatch(in: fullVersion, range: NSRange(fullVersion.startIndex..., in: fullVersion)),
              let range = Range(match.range(at: 1), in: fullVersion) else {
            return fullVersion
        }
        return String(fullVersion[range])
    }

    private init(device: String, osVersion: String, platform: String) {
        self.device = device
        self.osVersion = osVersion
        self.platform = platform
    }
}
