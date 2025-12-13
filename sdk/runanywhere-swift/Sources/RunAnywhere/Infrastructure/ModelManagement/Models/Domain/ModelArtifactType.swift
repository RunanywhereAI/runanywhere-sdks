//
//  ModelArtifactType.swift
//  RunAnywhere SDK
//
//  Describes how a model is packaged and what processing it requires after download.
//  This is generic infrastructure - framework-specific logic belongs in framework modules.
//

import Foundation

// MARK: - Archive Types

/// Supported archive formats for model packaging
public enum ArchiveType: String, CaseIterable, Codable, Sendable {
    case zip = "zip"
    case tarBz2 = "tar.bz2"
    case tarGz = "tar.gz"
    case tarXz = "tar.xz"

    /// File extension for this archive type
    public var fileExtension: String {
        rawValue
    }

    /// Detect archive type from URL
    public static func from(url: URL) -> ArchiveType? {
        let path = url.path.lowercased()
        if path.hasSuffix(".tar.bz2") || path.hasSuffix(".tbz2") {
            return .tarBz2
        } else if path.hasSuffix(".tar.gz") || path.hasSuffix(".tgz") {
            return .tarGz
        } else if path.hasSuffix(".tar.xz") || path.hasSuffix(".txz") {
            return .tarXz
        } else if path.hasSuffix(".zip") {
            return .zip
        }
        return nil
    }
}

// MARK: - Archive Structure

/// Describes the internal structure of an archive after extraction
public enum ArchiveStructure: Codable, Sendable, Equatable {
    /// Archive contains a single model file at root or nested in one directory
    case singleFileNested

    /// Archive extracts to a directory containing multiple files
    case directoryBased

    /// Archive has a subdirectory structure (e.g., extracts to subfolder)
    case nestedDirectory

    /// Unknown structure - will be detected after extraction
    case unknown
}

// MARK: - Multi-File Descriptor

/// Describes a file that needs to be downloaded as part of a multi-file model
public struct ModelFileDescriptor: Codable, Sendable, Equatable {
    /// Relative path from base URL to this file
    public let relativePath: String

    /// Destination path relative to model folder
    public let destinationPath: String

    /// Whether this file is required (vs optional)
    public let isRequired: Bool

    public init(relativePath: String, destinationPath: String, isRequired: Bool = true) {
        self.relativePath = relativePath
        self.destinationPath = destinationPath
        self.isRequired = isRequired
    }
}

// MARK: - Model Artifact Type

/// Describes how a model is packaged and what processing is needed after download.
/// This is set during model registration and drives the download/extraction behavior.
public enum ModelArtifactType: Codable, Sendable, Equatable {

    /// A single model file (e.g., .gguf, .onnx, .mlmodel)
    /// No extraction needed - just download and use
    case singleFile

    /// An archive that needs extraction
    /// - archiveType: The archive format (zip, tar.bz2, etc.)
    /// - structure: What's inside the archive
    case archive(ArchiveType, structure: ArchiveStructure)

    /// Multiple files that need to be downloaded separately
    /// Used for models where files are fetched individually from a repository
    case multiFile([ModelFileDescriptor])

    /// Use a custom download strategy identified by string
    /// Framework modules can register their own strategies
    case custom(strategyId: String)

    // MARK: - Computed Properties

    /// Whether this artifact type requires extraction after download
    public var requiresExtraction: Bool {
        switch self {
        case .archive:
            return true
        case .singleFile, .multiFile, .custom:
            return false
        }
    }

    /// Human-readable description
    public var displayName: String {
        switch self {
        case .singleFile:
            return "Single File"
        case .archive(let type, _):
            return "\(type.rawValue.uppercased()) Archive"
        case .multiFile(let files):
            return "Multi-File (\(files.count) files)"
        case .custom(let strategyId):
            return "Custom (\(strategyId))"
        }
    }
}

// MARK: - Factory Methods

public extension ModelArtifactType {

    /// Infer artifact type from download URL
    /// This is a convenience for when the artifact type isn't explicitly specified
    static func infer(from url: URL?, format: ModelFormat) -> ModelArtifactType {
        guard let url = url else {
            return .singleFile
        }

        // Check for archive extensions
        if let archiveType = ArchiveType.from(url: url) {
            return .archive(archiveType, structure: .unknown)
        }

        // Otherwise assume single file
        return .singleFile
    }

    /// Create a ZIP archive type
    static func zipArchive(structure: ArchiveStructure = .directoryBased) -> ModelArtifactType {
        .archive(.zip, structure: structure)
    }

    /// Create a tar.bz2 archive type
    static func tarBz2Archive(structure: ArchiveStructure = .nestedDirectory) -> ModelArtifactType {
        .archive(.tarBz2, structure: structure)
    }

    /// Create a tar.gz archive type
    static func tarGzArchive(structure: ArchiveStructure = .nestedDirectory) -> ModelArtifactType {
        .archive(.tarGz, structure: structure)
    }
}

// MARK: - Codable Conformance

extension ModelArtifactType {
    private enum CodingKeys: String, CodingKey {
        case type
        case archiveType
        case structure
        case files
        case strategyId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "singleFile":
            self = .singleFile
        case "archive":
            let archiveType = try container.decode(ArchiveType.self, forKey: .archiveType)
            let structure = try container.decode(ArchiveStructure.self, forKey: .structure)
            self = .archive(archiveType, structure: structure)
        case "multiFile":
            let files = try container.decode([ModelFileDescriptor].self, forKey: .files)
            self = .multiFile(files)
        case "custom":
            let strategyId = try container.decode(String.self, forKey: .strategyId)
            self = .custom(strategyId: strategyId)
        default:
            self = .singleFile
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .singleFile:
            try container.encode("singleFile", forKey: .type)
        case .archive(let archiveType, let structure):
            try container.encode("archive", forKey: .type)
            try container.encode(archiveType, forKey: .archiveType)
            try container.encode(structure, forKey: .structure)
        case .multiFile(let files):
            try container.encode("multiFile", forKey: .type)
            try container.encode(files, forKey: .files)
        case .custom(let strategyId):
            try container.encode("custom", forKey: .type)
            try container.encode(strategyId, forKey: .strategyId)
        }
    }
}
