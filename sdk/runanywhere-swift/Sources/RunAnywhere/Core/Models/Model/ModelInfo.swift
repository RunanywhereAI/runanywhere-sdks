import Foundation

/// Information about a model
public struct ModelInfo: Codable {
    // Essential identifiers
    public let id: String
    public let name: String
    public let category: ModelCategory  // NEW: Type of model (language, speech, vision, etc.)

    // Format and location
    public let format: ModelFormat
    public let downloadURL: URL?
    public var localPath: URL?

    // Size information (in bytes)
    public let downloadSize: Int64?  // Size when downloading
    public let memoryRequired: Int64?  // RAM needed to run the model

    // Framework compatibility
    public let compatibleFrameworks: [LLMFramework]
    public let preferredFramework: LLMFramework?

    // Model-specific capabilities (optional based on category)
    public let contextLength: Int?  // For language models
    public let supportsThinking: Bool  // For reasoning models

    // Optional metadata
    public let metadata: ModelInfoMetadata?

    // Non-Codable runtime properties
    public var additionalProperties: [String: Any] = [:]

    private enum CodingKeys: String, CodingKey {
        case id, name, category, format, downloadURL, localPath
        case downloadSize, memoryRequired
        case compatibleFrameworks, preferredFramework
        case contextLength, supportsThinking
        case metadata
    }

    public init(
        id: String,
        name: String,
        category: ModelCategory,
        format: ModelFormat,
        downloadURL: URL? = nil,
        localPath: URL? = nil,
        downloadSize: Int64? = nil,
        memoryRequired: Int64? = nil,
        compatibleFrameworks: [LLMFramework] = [],
        preferredFramework: LLMFramework? = nil,
        contextLength: Int? = nil,
        supportsThinking: Bool = false,
        metadata: ModelInfoMetadata? = nil,
        additionalProperties: [String: Any] = [:]
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.format = format
        self.downloadURL = downloadURL
        self.localPath = localPath
        self.downloadSize = downloadSize
        self.memoryRequired = memoryRequired
        self.compatibleFrameworks = compatibleFrameworks
        self.preferredFramework = preferredFramework ?? compatibleFrameworks.first

        // Set contextLength based on category if not provided
        if category.requiresContextLength {
            self.contextLength = contextLength ?? 2048
        } else {
            self.contextLength = contextLength
        }

        // Set supportsThinking based on category
        self.supportsThinking = category.supportsThinking ? supportsThinking : false

        self.metadata = metadata
        self.additionalProperties = additionalProperties
    }
}
