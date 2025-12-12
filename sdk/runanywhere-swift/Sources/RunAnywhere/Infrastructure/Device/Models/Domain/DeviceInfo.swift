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

    /// Device type for API requests (mobile, tablet, desktop, etc.)
    public let deviceType: String

    /// Form factor (phone, tablet, laptop, desktop)
    public let formFactor: String

    public init(
        model: String,
        osVersion: String,
        platform: String,
        architecture: String,
        deviceType: String,
        formFactor: String
    ) {
        self.model = model
        self.osVersion = osVersion
        self.platform = platform
        self.architecture = architecture
        self.deviceType = deviceType
        self.formFactor = formFactor
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
        let device = UIDevice.current
        let deviceType: String
        let formFactor: String
        if device.userInterfaceIdiom == .phone {
            deviceType = "mobile"
            formFactor = "phone"
        } else if device.userInterfaceIdiom == .pad {
            deviceType = "tablet"
            formFactor = "tablet"
        } else {
            deviceType = "mobile"
            formFactor = "unknown"
        }
        #elseif os(macOS)
        let model = "Mac"
        let platform = "macOS"
        let deviceType = "desktop"
        // Simple check for laptop vs desktop based on model identifier
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var modelId = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &modelId, &size, nil, 0)
        let modelString = String(cString: modelId)
        let formFactor = modelString.contains("MacBook") ? "laptop" : "desktop"
        #elseif os(tvOS)
        let model = UIDevice.current.model
        let platform = "tvOS"
        let deviceType = "tv"
        let formFactor = "tv"
        #elseif os(watchOS)
        let model = WKInterfaceDevice.current().model
        let platform = "watchOS"
        let deviceType = "watch"
        let formFactor = "watch"
        #elseif os(visionOS)
        let model = "Apple Vision"
        let platform = "visionOS"
        let deviceType = "vr"
        let formFactor = "headset"
        #else
        let model = "Unknown"
        let platform = "unknown"
        let deviceType = "unknown"
        let formFactor = "unknown"
        #endif

        return DeviceInfo(
            model: model,
            osVersion: processInfo.operatingSystemVersionString,
            platform: platform,
            architecture: architecture,
            deviceType: deviceType,
            formFactor: formFactor
        )
    }
}
