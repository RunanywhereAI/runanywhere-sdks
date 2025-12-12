import Foundation

/// Request model for device registration
public struct DeviceRegistrationRequest: Codable, Sendable {
    public let deviceInfo: DeviceRegistrationInfo

    public init(deviceInfo: DeviceRegistrationInfo) {
        self.deviceInfo = deviceInfo
    }

    enum CodingKeys: String, CodingKey {
        case deviceInfo = "device_info"
    }
}
