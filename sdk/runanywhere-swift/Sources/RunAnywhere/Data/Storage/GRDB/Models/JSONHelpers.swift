import Foundation

/// Helper extension for encoding/decoding JSON data in GRDB records
extension Data {
    /// Encode a Codable object to JSON Data
    static func jsonData<T: Encodable>(from object: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(object)
    }

    /// Decode JSON Data to a Codable object
    func jsonObject<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: self)
    }
}

/// Helper for creating empty JSON objects
extension Data {
    static var emptyJSON: Data {
        return "{}".data(using: .utf8) ?? Data()
    }

    static var emptyJSONArray: Data {
        return "[]".data(using: .utf8) ?? Data()
    }
}

/// Common JSON structures for the database
struct ModelCapabilities: Codable {
    let maxTokens: Int
    let supportsStreaming: Bool
    let supportedLanguages: [String]?

    init(maxTokens: Int = 4096, supportsStreaming: Bool = true, supportedLanguages: [String]? = nil) {
        self.maxTokens = maxTokens
        self.supportsStreaming = supportsStreaming
        self.supportedLanguages = supportedLanguages
    }
}

struct ModelRequirements: Codable {
    let minMemoryMB: Int
    let minComputeUnits: Int?
    let requiresNeuralEngine: Bool

    init(minMemoryMB: Int = 512, minComputeUnits: Int? = nil, requiresNeuralEngine: Bool = false) {
        self.minMemoryMB = minMemoryMB
        self.minComputeUnits = minComputeUnits
        self.requiresNeuralEngine = requiresNeuralEngine
    }
}

struct DeviceInfo: Codable {
    let model: String
    let osVersion: String
    let appVersion: String
    let locale: String?

    init(model: String, osVersion: String, appVersion: String, locale: String? = nil) {
        self.model = model
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.locale = locale
    }
}
