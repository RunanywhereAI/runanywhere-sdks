//
//  ModelRegistration.swift
//  RunAnywhere
//

/// One builder covering URL, archive, and multi-file model registration.
public struct ModelRegistration: Sendable {

    enum Payload: Sendable {
        case url(String)
        case archive(url: String, structure: RAArchiveStructure, type: RAArchiveType?)
        case multiFile([RAModelFileDescriptor])
    }

    let payload: Payload
    public var id: String?
    public var name: String
    public var framework: InferenceFramework
    public var category: ModelCategory
    public var memoryRequirementBytes: Int64?
    public var downloadSizeBytes: Int64?
    public var contextLength: Int?
    public var source: ModelSource
    public var description: String?
    public var supportsThinking: Bool
    public var supportsLora: Bool

    /// Computer-Use-Agent profile id (e.g. `RunAnywhere.CUA.faraProfile`) for a
    /// CUA-capable model; lands on `RAModelInfo.cuaProfile` so callers can
    /// discover which registered models are drivable through `RunAnywhere.CUA`.
    public var cuaProfile: String?

    private init(
        payload: Payload,
        id: String?,
        name: String,
        framework: InferenceFramework,
        category: ModelCategory,
        memoryRequirementBytes: Int64?,
        downloadSizeBytes: Int64?,
        contextLength: Int?,
        source: ModelSource,
        description: String?,
        supportsThinking: Bool,
        supportsLora: Bool,
        cuaProfile: String? = nil
    ) {
        self.payload = payload
        self.id = id
        self.name = name
        self.framework = framework
        self.category = category
        self.memoryRequirementBytes = memoryRequirementBytes
        self.downloadSizeBytes = downloadSizeBytes
        self.contextLength = contextLength
        self.source = source
        self.description = description
        self.supportsThinking = supportsThinking
        self.supportsLora = supportsLora
        self.cuaProfile = cuaProfile
    }

    /// Register a model served from a single download URL or `hf.co` reference.
    public static func url(
        _ url: String,
        name: String,
        framework: InferenceFramework,
        category: ModelCategory = .language,
        id: String? = nil,
        memoryRequirementBytes: Int64? = nil,
        downloadSizeBytes: Int64? = nil,
        contextLength: Int? = nil,
        source: ModelSource = .remote,
        description: String? = nil,
        supportsThinking: Bool = false,
        supportsLora: Bool = false,
        cuaProfile: String? = nil
    ) -> ModelRegistration {
        ModelRegistration(
            payload: .url(url),
            id: id,
            name: name,
            framework: framework,
            category: category,
            memoryRequirementBytes: memoryRequirementBytes,
            downloadSizeBytes: downloadSizeBytes,
            contextLength: contextLength,
            source: source,
            description: description,
            supportsThinking: supportsThinking,
            supportsLora: supportsLora,
            cuaProfile: cuaProfile
        )
    }

    /// Register an archive-packaged model whose on-disk layout the URL cannot imply.
    public static func archive(
        _ url: String,
        structure: RAArchiveStructure,
        name: String,
        framework: InferenceFramework,
        category: ModelCategory = .language,
        archiveType: RAArchiveType? = nil,
        id: String? = nil,
        memoryRequirementBytes: Int64? = nil,
        downloadSizeBytes: Int64? = nil,
        contextLength: Int? = nil,
        source: ModelSource = .remote,
        description: String? = nil,
        supportsThinking: Bool = false,
        supportsLora: Bool = false,
        cuaProfile: String? = nil
    ) -> ModelRegistration {
        ModelRegistration(
            payload: .archive(url: url, structure: structure, type: archiveType),
            id: id,
            name: name,
            framework: framework,
            category: category,
            memoryRequirementBytes: memoryRequirementBytes,
            downloadSizeBytes: downloadSizeBytes,
            contextLength: contextLength,
            source: source,
            description: description,
            supportsThinking: supportsThinking,
            supportsLora: supportsLora,
            cuaProfile: cuaProfile
        )
    }

    /// Register a model made of several files, each carrying its own URL.
    public static func multiFile(
        _ files: [RAModelFileDescriptor],
        id: String,
        name: String,
        framework: InferenceFramework,
        category: ModelCategory = .language,
        memoryRequirementBytes: Int64? = nil,
        downloadSizeBytes: Int64? = nil,
        contextLength: Int? = nil,
        source: ModelSource = .remote,
        description: String? = nil,
        supportsThinking: Bool = false,
        supportsLora: Bool = false,
        cuaProfile: String? = nil
    ) -> ModelRegistration {
        ModelRegistration(
            payload: .multiFile(files),
            id: id,
            name: name,
            framework: framework,
            category: category,
            memoryRequirementBytes: memoryRequirementBytes,
            downloadSizeBytes: downloadSizeBytes,
            contextLength: contextLength,
            source: source,
            description: description,
            supportsThinking: supportsThinking,
            supportsLora: supportsLora,
            cuaProfile: cuaProfile
        )
    }
}
