import Foundation

/// Information about a model
public struct ModelInfo {
    public let id: String
    public let name: String
    public let format: ModelFormat
    public let downloadURL: URL?
    public var localPath: URL?
    public let estimatedMemory: Int64
    public let contextLength: Int
    public let downloadSize: Int64?
    public let checksum: String?
    public let compatibleFrameworks: [LLMFramework]
    public let preferredFramework: LLMFramework?
    public let hardwareRequirements: [HardwareRequirement]
    public let tokenizerFormat: TokenizerFormat?
    public let metadata: ModelInfoMetadata?
    public let alternativeDownloadURLs: [URL]?
    public var additionalProperties: [String: Any] = [:]

    public init(
        id: String,
        name: String,
        format: ModelFormat,
        downloadURL: URL? = nil,
        localPath: URL? = nil,
        estimatedMemory: Int64 = 1_000_000_000, // 1GB default
        contextLength: Int = 2048,
        downloadSize: Int64? = nil,
        checksum: String? = nil,
        compatibleFrameworks: [LLMFramework] = [],
        preferredFramework: LLMFramework? = nil,
        hardwareRequirements: [HardwareRequirement] = [],
        tokenizerFormat: TokenizerFormat? = nil,
        metadata: ModelInfoMetadata? = nil,
        alternativeDownloadURLs: [URL]? = nil,
        additionalProperties: [String: Any] = [:]
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.downloadURL = downloadURL
        self.localPath = localPath
        self.estimatedMemory = estimatedMemory
        self.contextLength = contextLength
        self.downloadSize = downloadSize
        self.checksum = checksum
        self.compatibleFrameworks = compatibleFrameworks
        self.preferredFramework = preferredFramework
        self.hardwareRequirements = hardwareRequirements
        self.tokenizerFormat = tokenizerFormat
        self.metadata = metadata
        self.alternativeDownloadURLs = alternativeDownloadURLs
        self.additionalProperties = additionalProperties
    }
}
