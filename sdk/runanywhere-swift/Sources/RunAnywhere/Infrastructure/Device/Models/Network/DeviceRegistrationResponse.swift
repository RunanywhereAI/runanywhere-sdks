//
//  DeviceRegistrationResponse.swift
//  RunAnywhere SDK
//
//  Unified response model for device registration across all environments
//

import Foundation

/// Response model for device registration
/// Matches backend schemas/device.py DeviceRegistrationResponse
public struct DeviceRegistrationResponse: Codable, Sendable {
    /// Device ID that was registered
    public let deviceId: String

    /// Registration status ("registered" or "updated")
    public let status: String

    /// Sync status ("synced" or "pending")
    public let syncStatus: String

    public init(deviceId: String, status: String, syncStatus: String) {
        self.deviceId = deviceId
        self.status = status
        self.syncStatus = syncStatus
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case status
        case syncStatus = "sync_status"
    }

    /// Convenience: Check if registration was successful
    public var isSuccess: Bool {
        status == "registered" || status == "updated"
    }
}
