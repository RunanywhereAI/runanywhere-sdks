//
//  DeviceInfo.swift
//  RunAnywhere SDK
//
//  Core device hardware information for telemetry, logging, and API requests
//

import Foundation

#if os(iOS) || os(tvOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// Core device hardware information
/// This is embedded in DeviceRegistrationRequest and also available standalone
/// via DeviceRegistrationService.currentDeviceInfo
public struct DeviceInfo: Codable, Sendable, Equatable {

    // MARK: - Device Identity

    /// Persistent device UUID (survives app reinstalls via Keychain)
    public let deviceId: String

    // MARK: - Device Hardware

    /// Device model identifier (e.g., "iPhone16,2" for iPhone 15 Pro Max)
    public let modelIdentifier: String

    /// User-friendly device name (e.g., "iPhone 15 Pro Max")
    public let modelName: String

    /// CPU architecture (e.g., "arm64", "x86_64")
    public let architecture: String

    // MARK: - Operating System

    /// Operating system version string (e.g., "17.2")
    public let osVersion: String

    /// Platform identifier (e.g., "iOS", "macOS")
    public let platform: String

    // MARK: - Device Classification

    /// Device type for API requests (mobile, tablet, desktop, tv, watch, vr)
    public let deviceType: String

    /// Form factor (phone, tablet, laptop, desktop, tv, watch, headset)
    public let formFactor: String

    // MARK: - Hardware Specs

    /// Total physical memory in bytes
    public let totalMemory: UInt64

    /// Number of processor cores
    public let processorCount: Int

    // MARK: - Initialization

    public init(
        deviceId: String,
        modelIdentifier: String,
        modelName: String,
        architecture: String,
        osVersion: String,
        platform: String,
        deviceType: String,
        formFactor: String,
        totalMemory: UInt64,
        processorCount: Int
    ) {
        self.deviceId = deviceId
        self.modelIdentifier = modelIdentifier
        self.modelName = modelName
        self.architecture = architecture
        self.osVersion = osVersion
        self.platform = platform
        self.deviceType = deviceType
        self.formFactor = formFactor
        self.totalMemory = totalMemory
        self.processorCount = processorCount
    }

    // MARK: - JSON Coding Keys

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case modelIdentifier = "model_identifier"
        case modelName = "model_name"
        case architecture
        case osVersion = "os_version"
        case platform
        case deviceType = "device_type"
        case formFactor = "form_factor"
        case totalMemory = "total_memory"
        case processorCount = "processor_count"
    }

    // MARK: - Computed Properties

    /// Clean OS version (e.g., "17.2" instead of "Version 17.2 (Build 21C52)")
    public var cleanOSVersion: String {
        let regex = try? NSRegularExpression(pattern: #"(\d+\.\d+(?:\.\d+)?)"#)
        if let match = regex?.firstMatch(in: osVersion, range: NSRange(osVersion.startIndex..., in: osVersion)),
           let range = Range(match.range(at: 1), in: osVersion) {
            return String(osVersion[range])
        }
        return osVersion
    }

    // MARK: - Current Device Info

    /// Get current device info - called fresh each time
    public static var current: DeviceInfo {
        let processInfo = ProcessInfo.processInfo
        let deviceId = DeviceIdentity.persistentUUID

        // Architecture
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif

        let modelIdentifier = getModelIdentifier()

        #if os(iOS)
        let modelName = mapModelIdentifierToName(modelIdentifier) ?? UIDevice.current.model
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
        let modelName = mapModelIdentifierToName(modelIdentifier) ?? "Mac"
        let platform = "macOS"
        let deviceType = "desktop"
        let formFactor = modelIdentifier.contains("MacBook") ? "laptop" : "desktop"
        #elseif os(tvOS)
        let modelName = mapModelIdentifierToName(modelIdentifier) ?? UIDevice.current.model
        let platform = "tvOS"
        let deviceType = "tv"
        let formFactor = "tv"
        #elseif os(watchOS)
        let modelName = mapModelIdentifierToName(modelIdentifier) ?? WKInterfaceDevice.current().model
        let platform = "watchOS"
        let deviceType = "watch"
        let formFactor = "watch"
        #elseif os(visionOS)
        let modelName = mapModelIdentifierToName(modelIdentifier) ?? "Apple Vision Pro"
        let platform = "visionOS"
        let deviceType = "vr"
        let formFactor = "headset"
        #else
        let modelName = "Unknown"
        let platform = "unknown"
        let deviceType = "unknown"
        let formFactor = "unknown"
        #endif

        return DeviceInfo(
            deviceId: deviceId,
            modelIdentifier: modelIdentifier,
            modelName: modelName,
            architecture: architecture,
            osVersion: processInfo.operatingSystemVersionString,
            platform: platform,
            deviceType: deviceType,
            formFactor: formFactor,
            totalMemory: processInfo.physicalMemory,
            processorCount: processInfo.processorCount
        )
    }

    // MARK: - Private Helpers

    private static func getModelIdentifier() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
        #elseif os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
        #else
        return "Unknown"
        #endif
    }

    // swiftlint:disable function_body_length
    private static func mapModelIdentifierToName(_ identifier: String) -> String? {
        // iPhone models (2020-2025)
        let iPhoneModels: [String: String] = [
            "iPhone18,1": "iPhone 17 Pro",
            "iPhone18,2": "iPhone 17 Pro Max",
            "iPhone18,3": "iPhone 17",
            "iPhone18,4": "iPhone 17 Plus",
            "iPhone18,5": "iPhone Air",
            "iPhone17,5": "iPhone 16e",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,5": "iPhone 13",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,6": "iPhone SE (3rd generation)",
            "iPhone12,8": "iPhone SE (2nd generation)"
        ]

        // iPad models (2020-2025)
        let iPadModels: [String: String] = [
            "iPad17,1": "iPad Pro 11-inch (M5)",
            "iPad17,2": "iPad Pro 11-inch (M5)",
            "iPad17,3": "iPad Pro 13-inch (M5)",
            "iPad17,4": "iPad Pro 13-inch (M5)",
            "iPad15,3": "iPad Air 11-inch (M3)",
            "iPad15,4": "iPad Air 11-inch (M3)",
            "iPad15,5": "iPad Air 13-inch (M3)",
            "iPad15,6": "iPad Air 13-inch (M3)",
            "iPad15,7": "iPad (11th generation)",
            "iPad15,8": "iPad (11th generation)",
            "iPad16,3": "iPad Pro 11-inch (M4)",
            "iPad16,4": "iPad Pro 11-inch (M4)",
            "iPad16,5": "iPad Pro 13-inch (M4)",
            "iPad16,6": "iPad Pro 13-inch (M4)",
            "iPad16,1": "iPad mini (A17 Pro)",
            "iPad16,2": "iPad mini (A17 Pro)",
            "iPad14,8": "iPad Air 11-inch (M2)",
            "iPad14,9": "iPad Air 11-inch (M2)",
            "iPad14,10": "iPad Air 13-inch (M2)",
            "iPad14,11": "iPad Air 13-inch (M2)",
            "iPad14,3": "iPad Pro 11-inch (4th generation)",
            "iPad14,4": "iPad Pro 11-inch (4th generation)",
            "iPad14,5": "iPad Pro 12.9-inch (6th generation)",
            "iPad14,6": "iPad Pro 12.9-inch (6th generation)",
            "iPad14,1": "iPad mini (6th generation)",
            "iPad14,2": "iPad mini (6th generation)",
            "iPad13,18": "iPad (10th generation)",
            "iPad13,19": "iPad (10th generation)",
            "iPad12,1": "iPad (9th generation)",
            "iPad12,2": "iPad (9th generation)",
            "iPad13,16": "iPad Air (5th generation)",
            "iPad13,17": "iPad Air (5th generation)"
        ]

        // Mac models - Apple Silicon (2020-2025)
        let macModels: [String: String] = [
            "Mac16,1": "MacBook Pro 14-inch (M4)",
            "Mac16,2": "MacBook Pro 14-inch (M4)",
            "Mac16,3": "MacBook Pro 14-inch (M4 Pro)",
            "Mac16,4": "MacBook Pro 14-inch (M4 Pro)",
            "Mac16,5": "MacBook Pro 16-inch (M4 Pro)",
            "Mac16,6": "MacBook Pro 16-inch (M4 Pro)",
            "Mac16,7": "MacBook Pro 14-inch (M4 Max)",
            "Mac16,8": "MacBook Pro 16-inch (M4 Max)",
            "Mac16,9": "iMac 24-inch (M4)",
            "Mac16,10": "iMac 24-inch (M4)",
            "Mac16,11": "iMac 24-inch (M4)",
            "Mac16,12": "iMac 24-inch (M4)",
            "Mac16,13": "Mac mini (M4)",
            "Mac16,14": "Mac mini (M4)",
            "Mac16,15": "Mac mini (M4 Pro)",
            "Mac16,16": "Mac mini (M4 Pro)",
            "Mac15,3": "MacBook Pro 14-inch (M3)",
            "Mac15,6": "MacBook Pro 14-inch (M3 Pro)",
            "Mac15,7": "MacBook Pro 14-inch (M3 Pro)",
            "Mac15,8": "MacBook Pro 14-inch (M3 Max)",
            "Mac15,9": "MacBook Pro 16-inch (M3 Pro)",
            "Mac15,10": "MacBook Pro 16-inch (M3 Pro)",
            "Mac15,11": "MacBook Pro 16-inch (M3 Max)",
            "Mac15,12": "MacBook Air 13-inch (M3)",
            "Mac15,13": "MacBook Air 15-inch (M3)",
            "Mac15,4": "iMac 24-inch (M3)",
            "Mac15,5": "iMac 24-inch (M3)",
            "Mac14,2": "MacBook Air (M2)",
            "Mac14,15": "MacBook Air 15-inch (M2)",
            "Mac14,5": "MacBook Pro 14-inch (M2 Pro)",
            "Mac14,6": "MacBook Pro 16-inch (M2 Pro)",
            "Mac14,9": "MacBook Pro 14-inch (M2 Max)",
            "Mac14,10": "MacBook Pro 16-inch (M2 Max)",
            "Mac14,3": "Mac mini (M2)",
            "Mac14,12": "Mac mini (M2 Pro)",
            "Mac14,13": "Mac Studio (M2 Max)",
            "Mac14,14": "Mac Studio (M2 Ultra)",
            "Mac14,8": "Mac Pro (M2 Ultra)",
            "Mac14,7": "MacBook Pro 13-inch (M2)",
            "MacBookPro18,3": "MacBook Pro 14-inch (M1 Pro)",
            "MacBookPro18,4": "MacBook Pro 14-inch (M1 Max)",
            "MacBookPro18,1": "MacBook Pro 16-inch (M1 Pro)",
            "MacBookPro18,2": "MacBook Pro 16-inch (M1 Max)",
            "MacBookAir10,1": "MacBook Air (M1)",
            "Macmini9,1": "Mac mini (M1)",
            "iMac21,1": "iMac 24-inch (M1)",
            "iMac21,2": "iMac 24-inch (M1)",
            "Mac13,1": "Mac Studio (M1 Max)",
            "Mac13,2": "Mac Studio (M1 Ultra)"
        ]

        // Apple Watch models (2020-2025)
        let watchModels: [String: String] = [
            "Watch9,1": "Apple Watch Series 11 (42mm)",
            "Watch9,2": "Apple Watch Series 11 (46mm)",
            "Watch9,3": "Apple Watch Series 11 (42mm, GPS+Cellular)",
            "Watch9,4": "Apple Watch Series 11 (46mm, GPS+Cellular)",
            "Watch9,5": "Apple Watch Ultra 3",
            "Watch9,6": "Apple Watch Ultra 3 (GPS+Cellular)",
            "Watch8,1": "Apple Watch Series 10 (42mm)",
            "Watch8,2": "Apple Watch Series 10 (46mm)",
            "Watch8,3": "Apple Watch Series 10 (42mm, GPS+Cellular)",
            "Watch8,4": "Apple Watch Series 10 (46mm, GPS+Cellular)",
            "Watch7,5": "Apple Watch Ultra 2",
            "Watch7,6": "Apple Watch Ultra 2 (GPS+Cellular)",
            "Watch7,1": "Apple Watch Series 9 (41mm)",
            "Watch7,2": "Apple Watch Series 9 (45mm)",
            "Watch7,3": "Apple Watch Series 9 (41mm, GPS+Cellular)",
            "Watch7,4": "Apple Watch Series 9 (45mm, GPS+Cellular)",
            "Watch6,18": "Apple Watch Ultra",
            "Watch6,14": "Apple Watch Series 8 (41mm)",
            "Watch6,15": "Apple Watch Series 8 (45mm)",
            "Watch6,16": "Apple Watch Series 8 (41mm, GPS+Cellular)",
            "Watch6,17": "Apple Watch Series 8 (45mm, GPS+Cellular)",
            "Watch6,10": "Apple Watch SE (2nd gen, 40mm)",
            "Watch6,11": "Apple Watch SE (2nd gen, 44mm)",
            "Watch6,12": "Apple Watch SE (2nd gen, 40mm, GPS+Cellular)",
            "Watch6,13": "Apple Watch SE (2nd gen, 44mm, GPS+Cellular)",
            "Watch6,6": "Apple Watch Series 7 (41mm)",
            "Watch6,7": "Apple Watch Series 7 (45mm)",
            "Watch6,8": "Apple Watch Series 7 (41mm, GPS+Cellular)",
            "Watch6,9": "Apple Watch Series 7 (45mm, GPS+Cellular)"
        ]

        // Apple TV & Vision Pro
        let otherModels: [String: String] = [
            "AppleTV14,1": "Apple TV 4K (3rd generation)",
            "AppleTV14,2": "Apple TV 4K (3rd generation, Wi-Fi+Ethernet)",
            "AppleTV11,1": "Apple TV 4K (2nd generation)",
            "AppleTV6,2": "Apple TV HD",
            "RealityDevice14,1": "Apple Vision Pro"
        ]

        if let name = iPhoneModels[identifier] { return name }
        if let name = iPadModels[identifier] { return name }
        if let name = macModels[identifier] { return name }
        if let name = watchModels[identifier] { return name }
        if let name = otherModels[identifier] { return name }

        return nil
    }
    // swiftlint:enable function_body_length
}
