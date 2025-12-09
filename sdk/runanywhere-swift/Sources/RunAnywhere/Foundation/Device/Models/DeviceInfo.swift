//
//  DeviceInfo.swift
//  RunAnywhere SDK
//
//  Simple device information for telemetry and logging
//

import Foundation

#if os(iOS) || os(tvOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// Simple device information for telemetry and logging
/// This is a lightweight struct - no complex hardware detection
public struct DeviceInfo: Codable, Sendable {
    /// Device model name (e.g., "iPhone", "Mac")
    public let model: String

    /// Operating system version string
    public let osVersion: String

    /// Platform identifier
    public let platform: String

    /// CPU architecture
    public let architecture: String

    public init(
        model: String,
        osVersion: String,
        platform: String,
        architecture: String
    ) {
        self.model = model
        self.osVersion = osVersion
        self.platform = platform
        self.architecture = architecture
    }

    /// Get current device info - simple implementation without DeviceKit
    public static var current: DeviceInfo {
        let processInfo = ProcessInfo.processInfo

        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif

        #if os(iOS)
        let model = UIDevice.current.model
        let platform = "iOS"
        #elseif os(macOS)
        let model = "Mac"
        let platform = "macOS"
        #elseif os(tvOS)
        let model = UIDevice.current.model
        let platform = "tvOS"
        #elseif os(watchOS)
        let model = WKInterfaceDevice.current().model
        let platform = "watchOS"
        #elseif os(visionOS)
        let model = "Apple Vision"
        let platform = "visionOS"
        #else
        let model = "Unknown"
        let platform = "unknown"
        #endif

        return DeviceInfo(
            model: model,
            osVersion: processInfo.operatingSystemVersionString,
            platform: platform,
            architecture: architecture
        )
    }
}
