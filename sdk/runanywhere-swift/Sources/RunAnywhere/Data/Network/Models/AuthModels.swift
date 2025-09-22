import Foundation

// MARK: - Authentication Models

/// Request model for authentication
public struct AuthenticationRequest: Codable {
    let apiKey: String
    let deviceId: String
    let platform: String
    let sdkVersion: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case deviceId = "device_id"
        case platform
        case sdkVersion = "sdk_version"
    }
}

/// Response model for authentication
public struct AuthenticationResponse: Codable {
    let accessToken: String
    let deviceId: String
    let expiresIn: Int
    let organizationId: String
    let refreshToken: String
    let tokenType: String
    let userId: String?  // Made optional since API key should be org level or user level, will see if update is neeeded.

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case deviceId = "device_id"
        case expiresIn = "expires_in"
        case organizationId = "organization_id"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case userId = "user_id"
    }
}

// MARK: - Token Refresh Models

/// Request model for token refresh
public struct RefreshTokenRequest: Codable {
    let deviceId: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case refreshToken = "refresh_token"
    }
}

/// Response model for token refresh (same as AuthenticationResponse)
public typealias RefreshTokenResponse = AuthenticationResponse

// MARK: - Health Check Models

/// Response model for health check
public struct HealthCheckResponse: Codable {
    let status: HealthStatus
    let version: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case status
        case version
        case timestamp
    }
}

/// Health status enum
public enum HealthStatus: String, Codable {
    case healthy
    case degraded
    case unhealthy
}

// MARK: - Device Registration Models

/// Device information for registration
public struct DeviceRegistrationInfo: Codable {
    let architecture: String
    let availableMemory: Int64
    let batteryLevel: Double?
    let batteryState: String?
    let chipName: String?
    let coreCount: Int
    let deviceModel: String
    let deviceName: String?
    let efficiencyCores: Int?
    let formFactor: String
    let gpuFamily: String?
    let hasNeuralEngine: Bool
    let isLowPowerMode: Bool?
    let neuralEngineCores: Int?
    let osVersion: String
    let performanceCores: Int?
    let platform: String
    let totalMemory: Int64

    enum CodingKeys: String, CodingKey {
        case architecture
        case availableMemory = "available_memory"
        case batteryLevel = "battery_level"
        case batteryState = "battery_state"
        case chipName = "chip_name"
        case coreCount = "core_count"
        case deviceModel = "device_model"
        case deviceName = "device_name"
        case efficiencyCores = "efficiency_cores"
        case formFactor = "form_factor"
        case gpuFamily = "gpu_family"
        case hasNeuralEngine = "has_neural_engine"
        case isLowPowerMode = "is_low_power_mode"
        case neuralEngineCores = "neural_engine_cores"
        case osVersion = "os_version"
        case performanceCores = "performance_cores"
        case platform
        case totalMemory = "total_memory"
    }
}

/// Request model for device registration
public struct DeviceRegistrationRequest: Codable {
    let deviceInfo: DeviceRegistrationInfo

    enum CodingKeys: String, CodingKey {
        case deviceInfo = "device_info"
    }
}

/// Response model for device registration
public struct DeviceRegistrationResponse: Codable {
    let deviceId: String
    let status: String
    let syncStatus: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case status
        case syncStatus = "sync_status"
    }
}

// MARK: - Model API Responses

/// Response from GET /api/v1/models/available
public struct AvailableModelsResponse: Codable {
    let success: Bool
    let models: [APIModelInfo]
    let count: Int?
    let message: String?
}


/// Individual model information from API
public struct APIModelInfo: Codable {
    let id: String
    let name: String
    let description: String?
    let version: String?
    let size: Int64?
    let format: String?
    let downloadUrl: String?
    let checksum: String?
    let compatibleFrameworks: [String]?
    let requirements: ModelRequirements?
    let metadata: [String: AnyCodable]?
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case version
        case size
        case format
        case downloadUrl = "download_url"
        case checksum
        case compatibleFrameworks = "compatible_frameworks"
        case requirements
        case metadata
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Model requirements from API
public struct ModelRequirements: Codable {
    let minMemory: Int64?
    let minStorage: Int64?
    let minComputeUnits: Int?
    let supportedPlatforms: [String]?

    private enum CodingKeys: String, CodingKey {
        case minMemory = "min_memory"
        case minStorage = "min_storage"
        case minComputeUnits = "min_compute_units"
        case supportedPlatforms = "supported_platforms"
    }
}

/// Response from GET /api/v1/models/{model_id}/download
public struct ModelDownloadResponse: Codable {
    let modelId: String?
    let modelName: String?
    let downloadUrl: String
    let expiresAt: String?
    let sizeBytes: Int64?
    let format: String?
    let version: String?
    let checksum: String?
    let compatibility: CompatibilityInfo?

    // Computed property for backward compatibility
    var size: Int64? {
        return sizeBytes
    }

    private enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case modelName = "model_name"
        case downloadUrl = "download_url"
        case expiresAt = "expires_at"
        case sizeBytes = "size_bytes"
        case format
        case version
        case checksum
        case compatibility
    }
}

/// Compatibility information for model download
public struct CompatibilityInfo: Codable {
    let isCompatible: Bool?
    let reason: String?

    private enum CodingKeys: String, CodingKey {
        case isCompatible = "is_compatible"
        case reason
    }
}

/// Helper to encode/decode Any types in JSON
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Cannot encode value"
                )
            )
        }
    }
}

// MARK: - Conversion Extensions

extension APIModelInfo {
    /// Convert API model to SDK ModelInfo
    func toModelInfo() -> ModelInfo {
        // Map compatible frameworks from strings to enum
        let frameworks = (compatibleFrameworks ?? []).compactMap { frameworkString in
            LLMFramework(rawValue: frameworkString)
        }

        // Determine model format
        let modelFormat: ModelFormat
        if let format = format {
            modelFormat = ModelFormat(rawValue: format) ?? .gguf
        } else {
            modelFormat = .gguf
        }

        // Convert download URL string to URL
        let downloadURL = downloadUrl.flatMap { URL(string: $0) }

        // Determine category based on name or metadata
        let category: ModelCategory = .language // Default to language, could be enhanced

        // Create metadata
        let metadataObj = ModelInfoMetadata(
            author: metadata?["author"].flatMap { $0.value as? String },
            license: metadata?["license"].flatMap { $0.value as? String },
            tags: metadata?["tags"].flatMap { $0.value as? [String] } ?? [],
            description: description,
            version: version
        )

        return ModelInfo(
            id: id,
            name: name,
            category: category,
            format: modelFormat,
            downloadURL: downloadURL,
            localPath: nil,
            downloadSize: size,
            memoryRequired: requirements?.minMemory,
            compatibleFrameworks: frameworks,
            preferredFramework: frameworks.first,
            contextLength: metadata?["context_length"].flatMap { $0.value as? Int },
            supportsThinking: metadata?["supports_thinking"].flatMap { $0.value as? Bool } ?? false,
            metadata: metadataObj,
            source: .remote,
            createdAt: Date(),
            updatedAt: Date(),
            syncPending: false,
            lastUsed: nil,
            usageCount: 0
        )
    }
}
