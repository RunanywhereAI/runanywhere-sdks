//
//  ModelBuilder.swift
//  RunAnywhere SDK
//
//  Fluent builder for creating ModelInfo instances.
//  This is generic infrastructure - framework-specific builders belong in framework modules.
//

import Foundation

/// Fluent builder for creating ModelInfo instances
/// Provides a clean, chainable API for model registration
///
/// Example usage:
/// ```swift
/// let model = ModelBuilder(id: "my-model", name: "My Model")
///     .category(.language)
///     .format(.gguf)
///     .downloadURL("https://example.com/model.gguf")
///     .framework(.llamaCpp)
///     .singleFile()
///     .downloadSize(2, unit: .gigabytes)
///     .build()
/// ```
public final class ModelBuilder {

    // MARK: - Required Properties

    private let id: String
    private let name: String

    // MARK: - Optional Properties

    private var category: ModelCategory = .language
    private var format: ModelFormat = .unknown
    private var downloadURL: URL?
    private var localPath: URL?
    private var artifactType: ModelArtifactType?
    private var downloadSize: Int64?
    private var memoryRequired: Int64?
    private var compatibleFrameworks: [InferenceFramework] = []
    private var preferredFramework: InferenceFramework?
    private var contextLength: Int?
    private var supportsThinking: Bool = false
    private var thinkingPattern: ThinkingTagPattern?
    private var tags: [String] = []
    private var modelDescription: String?
    private var source: ConfigurationSource = .consumer

    // MARK: - Initialization

    /// Create a new model builder
    /// - Parameters:
    ///   - id: Unique identifier for the model
    ///   - name: Human-readable display name
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    // MARK: - Category & Format

    /// Set the model category
    @discardableResult
    public func category(_ category: ModelCategory) -> ModelBuilder {
        self.category = category
        return self
    }

    /// Set the model format
    @discardableResult
    public func format(_ format: ModelFormat) -> ModelBuilder {
        self.format = format
        return self
    }

    // MARK: - URLs

    /// Set the download URL
    @discardableResult
    public func downloadURL(_ url: URL) -> ModelBuilder {
        self.downloadURL = url
        return self
    }

    /// Set the download URL from string
    @discardableResult
    public func downloadURL(_ urlString: String) -> ModelBuilder {
        self.downloadURL = URL(string: urlString)
        return self
    }

    /// Set the local path (for pre-downloaded models)
    @discardableResult
    public func localPath(_ path: URL) -> ModelBuilder {
        self.localPath = path
        return self
    }

    // MARK: - Artifact Type

    /// Mark as a single file download (no extraction needed)
    @discardableResult
    public func singleFile(expectedFiles: ExpectedModelFiles = .none) -> ModelBuilder {
        self.artifactType = .singleFile(expectedFiles: expectedFiles)
        return self
    }

    /// Mark as a ZIP archive
    @discardableResult
    public func zipArchive(structure: ArchiveStructure = .directoryBased, expectedFiles: ExpectedModelFiles = .none) -> ModelBuilder {
        self.artifactType = .archive(.zip, structure: structure, expectedFiles: expectedFiles)
        return self
    }

    /// Mark as a tar.bz2 archive
    @discardableResult
    public func tarBz2Archive(structure: ArchiveStructure = .nestedDirectory, expectedFiles: ExpectedModelFiles = .none) -> ModelBuilder {
        self.artifactType = .archive(.tarBz2, structure: structure, expectedFiles: expectedFiles)
        return self
    }

    /// Mark as a tar.gz archive
    @discardableResult
    public func tarGzArchive(structure: ArchiveStructure = .nestedDirectory, expectedFiles: ExpectedModelFiles = .none) -> ModelBuilder {
        self.artifactType = .archive(.tarGz, structure: structure, expectedFiles: expectedFiles)
        return self
    }

    /// Set a custom artifact type
    @discardableResult
    public func artifactType(_ type: ModelArtifactType) -> ModelBuilder {
        self.artifactType = type
        return self
    }

    /// Mark as a multi-file download (files fetched individually)
    @discardableResult
    public func multiFile(_ files: [ModelFileDescriptor]) -> ModelBuilder {
        self.artifactType = .multiFile(files)
        return self
    }

    /// Use a custom download strategy
    @discardableResult
    public func customStrategy(_ strategyId: String) -> ModelBuilder {
        self.artifactType = .custom(strategyId: strategyId)
        return self
    }

    // MARK: - Size Information

    /// Set the download size in bytes
    @discardableResult
    public func downloadSize(_ bytes: Int64) -> ModelBuilder {
        self.downloadSize = bytes
        return self
    }

    /// Set the download size with unit
    @discardableResult
    public func downloadSize(_ value: Double, unit: SizeUnit) -> ModelBuilder {
        self.downloadSize = Int64(value * Double(unit.bytes))
        return self
    }

    /// Set the memory required to run the model
    @discardableResult
    public func memoryRequired(_ bytes: Int64) -> ModelBuilder {
        self.memoryRequired = bytes
        return self
    }

    /// Set the memory required with unit
    @discardableResult
    public func memoryRequired(_ value: Double, unit: SizeUnit) -> ModelBuilder {
        self.memoryRequired = Int64(value * Double(unit.bytes))
        return self
    }

    // MARK: - Framework

    /// Set the preferred framework
    @discardableResult
    public func framework(_ framework: InferenceFramework) -> ModelBuilder {
        self.preferredFramework = framework
        if !compatibleFrameworks.contains(framework) {
            compatibleFrameworks.append(framework)
        }
        return self
    }

    /// Set compatible frameworks
    @discardableResult
    public func compatibleWith(_ frameworks: InferenceFramework...) -> ModelBuilder {
        self.compatibleFrameworks.append(contentsOf: frameworks)
        return self
    }

    // MARK: - Capabilities

    /// Set the context length (for language models)
    @discardableResult
    public func contextLength(_ length: Int) -> ModelBuilder {
        self.contextLength = length
        return self
    }

    /// Enable thinking/reasoning support
    @discardableResult
    public func supportsThinking(_ enabled: Bool = true, pattern: ThinkingTagPattern? = nil) -> ModelBuilder {
        self.supportsThinking = enabled
        self.thinkingPattern = pattern
        return self
    }

    // MARK: - Metadata

    /// Add tags
    @discardableResult
    public func tags(_ tags: String...) -> ModelBuilder {
        self.tags.append(contentsOf: tags)
        return self
    }

    /// Set description
    @discardableResult
    public func description(_ description: String) -> ModelBuilder {
        self.modelDescription = description
        return self
    }

    /// Set the configuration source
    @discardableResult
    public func source(_ source: ConfigurationSource) -> ModelBuilder {
        self.source = source
        return self
    }

    // MARK: - Build

    /// Build the ModelInfo instance
    public func build() -> ModelInfo {
        ModelInfo(
            id: id,
            name: name,
            category: category,
            format: format,
            downloadURL: downloadURL,
            localPath: localPath,
            artifactType: artifactType,
            downloadSize: downloadSize,
            memoryRequired: memoryRequired,
            compatibleFrameworks: compatibleFrameworks,
            preferredFramework: preferredFramework,
            contextLength: contextLength,
            supportsThinking: supportsThinking,
            thinkingPattern: thinkingPattern,
            tags: tags,
            description: modelDescription,
            source: source
        )
    }
}

// MARK: - Size Unit

/// Size units for convenience
public enum SizeUnit {
    case bytes
    case kilobytes
    case megabytes
    case gigabytes

    var bytes: Int64 {
        switch self {
        case .bytes: return 1
        case .kilobytes: return 1024
        case .megabytes: return 1024 * 1024
        case .gigabytes: return 1024 * 1024 * 1024
        }
    }
}

// MARK: - Convenience Extensions

public extension ModelBuilder {

    /// Create a language model builder
    static func languageModel(id: String, name: String) -> ModelBuilder {
        ModelBuilder(id: id, name: name)
            .category(.language)
    }

    /// Create a speech recognition model builder
    static func speechRecognitionModel(id: String, name: String) -> ModelBuilder {
        ModelBuilder(id: id, name: name)
            .category(.speechRecognition)
    }

    /// Create a speech synthesis model builder
    static func speechSynthesisModel(id: String, name: String) -> ModelBuilder {
        ModelBuilder(id: id, name: name)
            .category(.speechSynthesis)
    }

    /// Create a vision model builder
    static func visionModel(id: String, name: String) -> ModelBuilder {
        ModelBuilder(id: id, name: name)
            .category(.vision)
    }

    /// Create an audio processing model builder
    static func audioModel(id: String, name: String) -> ModelBuilder {
        ModelBuilder(id: id, name: name)
            .category(.audio)
    }

    /// Create a multimodal model builder
    static func multimodalModel(id: String, name: String) -> ModelBuilder {
        ModelBuilder(id: id, name: name)
            .category(.multimodal)
    }
}
