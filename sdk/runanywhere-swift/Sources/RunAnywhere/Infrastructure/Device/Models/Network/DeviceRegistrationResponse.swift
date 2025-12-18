//
//  DeviceRegistrationResponse.swift
//  RunAnywhere SDK
//
//  Unified response model for device registration across all environments
//

import Foundation

/// Response model for device registration
/// Used for all SDK environments (development, staging, production)
public struct DeviceRegistrationResponse: Codable, Sendable {
    /// Whether registration was successful
    public let success: Bool

    /// Device ID that was registered
    public let deviceId: String

    /// ISO8601 timestamp when device was registered
    public let registeredAt: String

    public init(success: Bool, deviceId: String, registeredAt: String) {
        self.success = success
        self.deviceId = deviceId
        self.registeredAt = registeredAt
    }

    enum CodingKeys: String, CodingKey {
        case success
        case deviceId = "device_id"
        case registeredAt = "registered_at"
    }
}
