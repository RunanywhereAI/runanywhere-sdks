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
public enum ArchiveStructure: String, Codable, Sendable, Equatable {
    /// Archive contains a single model file at root or nested in one directory
    case singleFileNested

    /// Archive extracts to a directory containing multiple files
    case directoryBased

    /// Archive has a subdirectory structure (e.g., extracts to subfolder)
    case nestedDirectory

    /// Unknown structure - will be detected after extraction
    case unknown
}

// MARK: - Expected Model Files

/// Describes what files are expected after model extraction/download
/// Used for validation and to understand model requirements
public struct ExpectedModelFiles: Codable, Sendable, Equatable {
    /// File patterns that must be present (e.g., "*.onnx", "encoder*.onnx")
    public let requiredPatterns: [String]

    /// File patterns that may be present but are optional
    public let optionalPatterns: [String]

    /// Description of the model files for documentation
    public let description: String?

    public init(
        requiredPatterns: [String] = [],
        optionalPatterns: [String] = [],
        description: String? = nil
    ) {
        self.requiredPatterns = requiredPatterns
        self.optionalPatterns = optionalPatterns
        self.description = description
    }

    /// No specific file expectations
    public static let none = ExpectedModelFiles()
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
    case singleFile(expectedFiles: ExpectedModelFiles = .none)

    /// An archive that needs extraction
    /// - archiveType: The archive format (zip, tar.bz2, etc.)
    /// - structure: What's inside the archive
    /// - expectedFiles: What files to expect after extraction
    case archive(ArchiveType, structure: ArchiveStructure, expectedFiles: ExpectedModelFiles = .none)

    /// Multiple files that need to be downloaded separately
    case multiFile([ModelFileDescriptor])

    /// Use a custom download strategy identified by string
    case custom(strategyId: String)

    /// Built-in model that doesn't require download
    case builtIn

    // MARK: - Computed Properties

    /// Whether this artifact type requires extraction after download
    public var requiresExtraction: Bool {
        if case .archive = self { return true }
        return false
    }

    /// Whether this artifact type requires downloading
    public var requiresDownload: Bool {
        if case .builtIn = self { return false }
        return true
    }

    /// Get the expected files for this artifact type
    public var expectedFiles: ExpectedModelFiles {
        switch self {
        case .singleFile(let expected), .archive(_, _, let expected):
            return expected
        default:
            return .none
        }
    }

    /// Human-readable description
    public var displayName: String {
        switch self {
        case .singleFile:
            return "Single File"
        case .archive(let type, _, _):
            return "\(type.rawValue.uppercased()) Archive"
        case .multiFile(let files):
            return "Multi-File (\(files.count) files)"
        case .custom(let strategyId):
            return "Custom (\(strategyId))"
        case .builtIn:
            return "Built-in"
        }
    }
}

// MARK: - Factory Methods

public extension ModelArtifactType {

    /// Infer artifact type from download URL
    static func infer(from url: URL?, format _: ModelFormat) -> ModelArtifactType {
        guard let url = url else {
            return .singleFile(expectedFiles: .none)
        }

        if let archiveType = ArchiveType.from(url: url) {
            return .archive(archiveType, structure: .unknown, expectedFiles: .none)
        }

        return .singleFile(expectedFiles: .none)
    }

    /// Create a ZIP archive type
    static func zipArchive(structure: ArchiveStructure = .directoryBased, expectedFiles: ExpectedModelFiles = .none) -> ModelArtifactType {
        .archive(.zip, structure: structure, expectedFiles: expectedFiles)
    }

    /// Create a tar.bz2 archive type
    static func tarBz2Archive(structure: ArchiveStructure = .nestedDirectory, expectedFiles: ExpectedModelFiles = .none) -> ModelArtifactType {
        .archive(.tarBz2, structure: structure, expectedFiles: expectedFiles)
    }

    /// Create a tar.gz archive type
    static func tarGzArchive(structure: ArchiveStructure = .nestedDirectory, expectedFiles: ExpectedModelFiles = .none) -> ModelArtifactType {
        .archive(.tarGz, structure: structure, expectedFiles: expectedFiles)
    }
}

// MARK: - Codable Conformance

extension ModelArtifactType {
    private enum CodingKeys: String, CodingKey {
        case type, archiveType, structure, expectedFiles, files, strategyId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "singleFile":
            let expected = try container.decodeIfPresent(ExpectedModelFiles.self, forKey: .expectedFiles) ?? .none
            self = .singleFile(expectedFiles: expected)
        case "archive":
            let archiveType = try container.decode(ArchiveType.self, forKey: .archiveType)
            let structure = try container.decode(ArchiveStructure.self, forKey: .structure)
            let expected = try container.decodeIfPresent(ExpectedModelFiles.self, forKey: .expectedFiles) ?? .none
            self = .archive(archiveType, structure: structure, expectedFiles: expected)
        case "multiFile":
            let files = try container.decode([ModelFileDescriptor].self, forKey: .files)
            self = .multiFile(files)
        case "custom":
            let strategyId = try container.decode(String.self, forKey: .strategyId)
            self = .custom(strategyId: strategyId)
        case "builtIn":
            self = .builtIn
        default:
            self = .singleFile()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .singleFile(let expected):
            try container.encode("singleFile", forKey: .type)
            if expected != .none {
                try container.encode(expected, forKey: .expectedFiles)
            }
        case .archive(let archiveType, let structure, let expected):
            try container.encode("archive", forKey: .type)
            try container.encode(archiveType, forKey: .archiveType)
            try container.encode(structure, forKey: .structure)
            if expected != .none {
                try container.encode(expected, forKey: .expectedFiles)
            }
        case .multiFile(let files):
            try container.encode("multiFile", forKey: .type)
            try container.encode(files, forKey: .files)
        case .custom(let strategyId):
            try container.encode("custom", forKey: .type)
            try container.encode(strategyId, forKey: .strategyId)
        case .builtIn:
            try container.encode("builtIn", forKey: .type)
        }
    }
}
