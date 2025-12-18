//
//  DeviceRegistrationRequest.swift
//  RunAnywhere SDK
//
//  Unified request model for device registration across all environments
//

import Foundation

/// Request model for device registration
/// Used for all SDK environments (development, staging, production)
/// Contains complete device information plus SDK metadata
public struct DeviceRegistrationRequest: Codable, Sendable {

    // MARK: - Device Information (embedded)

    /// Complete device hardware information
    public let deviceInfo: DeviceInfo

    // MARK: - SDK Metadata

    /// SDK version string (from VERSION file)
    public let sdkVersion: String

    /// Build token for environment/build identification
    public let buildToken: String

    /// Timestamp of this registration request (updated every call)
    public let lastSeenAt: Date

    // MARK: - Initialization

    public init(
        deviceInfo: DeviceInfo,
        sdkVersion: String,
        buildToken: String,
        lastSeenAt: Date
    ) {
        self.deviceInfo = deviceInfo
        self.sdkVersion = sdkVersion
        self.buildToken = buildToken
        self.lastSeenAt = lastSeenAt
    }

    // MARK: - JSON Coding

    enum CodingKeys: String, CodingKey {
        case deviceInfo = "device_info"
        case sdkVersion = "sdk_version"
        case buildToken = "build_token"
        case lastSeenAt = "last_seen_at"
    }

    /// Custom encoding to use ISO8601 for dates
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceInfo, forKey: .deviceInfo)
        try container.encode(sdkVersion, forKey: .sdkVersion)
        try container.encode(buildToken, forKey: .buildToken)

        // Encode date as ISO8601 string
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: lastSeenAt), forKey: .lastSeenAt)
    }

    /// Custom decoding to parse ISO8601 dates
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceInfo = try container.decode(DeviceInfo.self, forKey: .deviceInfo)
        sdkVersion = try container.decode(String.self, forKey: .sdkVersion)
        buildToken = try container.decode(String.self, forKey: .buildToken)

        // Decode date from ISO8601 string
        let dateString = try container.decode(String.self, forKey: .lastSeenAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            lastSeenAt = date
        } else {
            // Try without fractional seconds as fallback
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                lastSeenAt = date
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .lastSeenAt,
                    in: container,
                    debugDescription: "Invalid ISO8601 date format: \(dateString)"
                )
            }
        }
    }
}

// MARK: - Factory Method

extension DeviceRegistrationRequest {
    /// Create a registration request from current device info
    /// Called fresh every time to ensure lastSeenAt is current
    /// - Returns: Populated registration request with current device data and timestamp
    public static func fromCurrentDevice() -> DeviceRegistrationRequest {
        return DeviceRegistrationRequest(
            deviceInfo: DeviceInfo.current,
            sdkVersion: SDKConstants.version,
            buildToken: BuildToken.token,
            lastSeenAt: Date()
        )
    }
}

// MARK: - Convenience Accessors

extension DeviceRegistrationRequest {
    /// Direct access to device ID (convenience)
    public var deviceId: String { deviceInfo.deviceId }

    /// Direct access to device model name (convenience)
    public var deviceModel: String { deviceInfo.modelName }

    /// Direct access to OS version (convenience)
    public var osVersion: String { deviceInfo.cleanOSVersion }

    /// Direct access to architecture (convenience)
    public var architecture: String { deviceInfo.architecture }

    /// Direct access to platform (convenience)
    public var platform: String { deviceInfo.platform }
}
