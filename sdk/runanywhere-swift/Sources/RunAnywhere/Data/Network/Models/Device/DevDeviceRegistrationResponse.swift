import Foundation

/// Response model for development device registration
public struct DevDeviceRegistrationResponse: Codable, Sendable {
    public let success: Bool
    public let deviceId: String
    public let registeredAt: String

    public init(success: Bool, deviceId: String, registeredAt: String) {
        self.success = success
        self.deviceId = deviceId
        self.registeredAt = registeredAt
    }

    enum CodingKeys: String, CodingKey {
        case success
        case deviceId
        case registeredAt
    }
}
