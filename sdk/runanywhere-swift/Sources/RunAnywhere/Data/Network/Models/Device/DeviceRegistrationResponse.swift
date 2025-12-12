import Foundation

/// Response model for device registration
public struct DeviceRegistrationResponse: Codable, Sendable {
    public let deviceId: String
    public let status: String
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
}
