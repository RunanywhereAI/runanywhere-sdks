import Foundation

/// Source of model data (where the model info came from)
public enum ModelSource: String, Codable, Sendable {
    /// Model info came from remote API (backend model catalog)
    case remote

    /// Model info was provided locally via SDK input (addModel calls)
    case local
}

/// Information about a model - in-memory entity
public struct ModelInfo: Codable, Sendable, Identifiable {
    // Essential identifiers
    public let id: String
    public let name: String
    public let category: ModelCategory  // Type of model (language, speech, vision, etc.)

    // Format and location
    public let format: ModelFormat
    public let downloadURL: URL?
    public var localPath: URL?

    // Artifact type - describes how the model is packaged and what processing is needed
    // This drives download and extraction behavior
    public let artifactType: ModelArtifactType

    // Size information (in bytes)
    public let downloadSize: Int64?  // Size when downloading

    // Framework (1:1 mapping - each model has exactly one framework)
    public let framework: InferenceFramework

    // Model-specific capabilities (optional based on category)
    public let contextLength: Int?  // For language models
    public let supportsThinking: Bool  // For reasoning models
    public let thinkingPattern: ThinkingTagPattern?  // Custom thinking pattern (if supportsThinking)

    // Optional metadata
    public let description: String?

    // Tracking fields
    public let source: ModelSource
    public let createdAt: Date
    public var updatedAt: Date

    // MARK: - Computed Properties

    /// Whether this model is downloaded and available locally
    public var isDownloaded: Bool {
        guard let localPath = localPath else { return false }

        // Built-in models (e.g., Apple Foundation Models) are always available
        if localPath.scheme == "builtin" {
            return true
        }

        // Check if the file or directory actually exists on disk
        let (exists, isDirectory) = FileOperationsUtilities.existsWithType(at: localPath)

        // For directories, verify they contain files (not empty)
        if exists && isDirectory {
            return FileOperationsUtilities.isNonEmptyDirectory(at: localPath)
        }

        return exists
    }

    /// Whether this model is available for use (downloaded and locally accessible)
    public var isAvailable: Bool {
        isDownloaded
    }

    /// Whether this is a built-in platform model (e.g., Apple Foundation Models, System TTS)
    /// Built-in models don't require downloading - they use platform services
    public var isBuiltIn: Bool {
        // Check artifact type first (source of truth from C++ registration)
        if artifactType == .builtIn {
            return true
        }
        // Fallback: check for builtin:// URL scheme
        if let localPath = localPath, localPath.scheme == "builtin" {
            return true
        }
        // Check framework - Foundation Models and System TTS are always built-in
        return framework == .foundationModels || framework == .systemTTS
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, format, downloadURL, localPath
        case artifactType
        case downloadSize
        case framework
        case contextLength, supportsThinking, thinkingPattern
        case description
        case source, createdAt, updatedAt
    }

    public init(
        id: String,
        name: String,
        category: ModelCategory,
        format: ModelFormat,
        framework: InferenceFramework,
        downloadURL: URL? = nil,
        localPath: URL? = nil,
        artifactType: ModelArtifactType? = nil,
        downloadSize: Int64? = nil,
        contextLength: Int? = nil,
        supportsThinking: Bool = false,
        thinkingPattern: ThinkingTagPattern? = nil,
        description: String? = nil,
        source: ModelSource = .remote,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.format = format
        self.framework = framework
        self.downloadURL = downloadURL
        self.localPath = localPath

        // Infer artifact type from URL and format if not explicitly provided
        self.artifactType = artifactType ?? ModelArtifactType.infer(from: downloadURL, format: format)

        self.downloadSize = downloadSize

        // Set contextLength based on category if not provided
        if category.requiresContextLength {
            self.contextLength = contextLength ?? 2048
        } else {
            self.contextLength = contextLength
        }

        // Set supportsThinking based on category
        self.supportsThinking = category.supportsThinking ? supportsThinking : false

        // Set thinking pattern based on supportsThinking
        self.thinkingPattern = supportsThinking ? (thinkingPattern ?? .defaultPattern) : nil

        self.description = description
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

}
