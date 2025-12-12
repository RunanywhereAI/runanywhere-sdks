import Foundation

/// Device information for registration - simplified to essential fields only
public struct DeviceRegistrationInfo: Codable, Sendable {
    public let architecture: String
    public let deviceModel: String
    public let deviceUUID: String
    public let formFactor: String
    public let osVersion: String
    public let platform: String
    public let totalMemory: Int64

    public init(
        architecture: String,
        deviceModel: String,
        deviceUUID: String,
        formFactor: String,
        osVersion: String,
        platform: String,
        totalMemory: Int64
    ) {
        self.architecture = architecture
        self.deviceModel = deviceModel
        self.deviceUUID = deviceUUID
        self.formFactor = formFactor
        self.osVersion = osVersion
        self.platform = platform
        self.totalMemory = totalMemory
    }

    enum CodingKeys: String, CodingKey {
        case architecture
        case deviceModel = "device_model"
        case deviceUUID = "device_uuid"
        case formFactor = "form_factor"
        case osVersion = "os_version"
        case platform
        case totalMemory = "total_memory"
    }
}
