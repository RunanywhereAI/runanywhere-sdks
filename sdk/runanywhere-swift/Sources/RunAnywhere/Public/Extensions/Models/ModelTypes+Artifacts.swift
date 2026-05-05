//
//  ModelTypes+Artifacts.swift
//  RunAnywhere SDK
//
//  Artifact/archive/expected-files helpers for the generated model contract
//  types. Split out of ModelTypes.swift so that file stays under the
//  SwiftLint file_length warning and the enum/typealias/Codable surface is
//  decoupled from the download-artifact logic.
//

import CRACommons
import Foundation
import SwiftProtobuf

// MARK: - Generated Model Contract Helpers

extension RAModelInfo: Identifiable {}

public extension RAExpectedModelFiles {
    static var none: RAExpectedModelFiles { RAExpectedModelFiles() }

    var isEmptyManifest: Bool {
        files.isEmpty
            && rootDirectory.isEmpty
            && requiredPatterns.isEmpty
            && optionalPatterns.isEmpty
            && description_p.isEmpty
    }
}

public extension RAModelFileDescriptor {
    init(url: URL, filename: String, isRequired: Bool = true) {
        self.init()
        self.url = url.absoluteString
        self.filename = filename
        self.isRequired = isRequired
        self.relativePath = url.lastPathComponent
        self.destinationPath = filename
    }

    var urlValue: URL? {
        guard !url.isEmpty else { return nil }
        return URL(string: url)
    }

    var destinationFilename: String {
        if !destinationPath.isEmpty { return destinationPath }
        if !filename.isEmpty { return filename }
        return relativePath
    }

    var resolvedLocalPath: String? {
        guard !localPath.isEmpty else { return nil }
        return localPath
    }
}

public extension Collection where Element == RAModelFileDescriptor {
    func resolvedModelFilePath(role: RAModelFileRole) -> String? {
        first { $0.role == role }?.resolvedLocalPath
    }

    var resolvedPrimaryModelPath: String? {
        resolvedModelFilePath(role: .primaryModel)
    }

    var resolvedVisionProjectorPath: String? {
        resolvedModelFilePath(role: .visionProjector)
    }

    var resolvedTokenizerPath: String? {
        resolvedModelFilePath(role: .tokenizer)
    }

    var resolvedConfigPath: String? {
        resolvedModelFilePath(role: .config)
    }

    var resolvedVocabularyPath: String? {
        resolvedModelFilePath(role: .vocabulary)
    }
}

public extension RAModelLoadResult {
    func resolvedModelFilePath(role: RAModelFileRole) -> String? {
        resolvedArtifacts.resolvedModelFilePath(role: role)
    }

    var resolvedPrimaryModelPath: String? {
        resolvedArtifacts.resolvedPrimaryModelPath
    }

    var resolvedVisionProjectorPath: String? {
        resolvedArtifacts.resolvedVisionProjectorPath
    }

    var resolvedTokenizerPath: String? {
        resolvedArtifacts.resolvedTokenizerPath
    }

    var resolvedConfigPath: String? {
        resolvedArtifacts.resolvedConfigPath
    }

    var resolvedVocabularyPath: String? {
        resolvedArtifacts.resolvedVocabularyPath
    }

    var lifecyclePrimaryArtifactPath: String? {
        resolvedPrimaryModelPath ?? resolvedPath.nilIfEmpty
    }
}

public extension RACurrentModelResult {
    func resolvedModelFilePath(role: RAModelFileRole) -> String? {
        resolvedArtifacts.resolvedModelFilePath(role: role)
    }

    var resolvedPrimaryModelPath: String? {
        resolvedArtifacts.resolvedPrimaryModelPath
    }

    var resolvedVisionProjectorPath: String? {
        resolvedArtifacts.resolvedVisionProjectorPath
    }

    var resolvedTokenizerPath: String? {
        resolvedArtifacts.resolvedTokenizerPath
    }

    var resolvedConfigPath: String? {
        resolvedArtifacts.resolvedConfigPath
    }

    var resolvedVocabularyPath: String? {
        resolvedArtifacts.resolvedVocabularyPath
    }

    var lifecyclePrimaryArtifactPath: String? {
        resolvedPrimaryModelPath ?? resolvedPath.nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

public extension RAModelArtifactType {
    var requiresExtraction: Bool {
        switch self {
        case .archive, .zipArchive, .tarGzArchive, .tarBz2Archive, .tarXzArchive:
            return true
        default:
            return false
        }
    }

    var requiresDownload: Bool {
        self != .builtIn
    }

    var displayName: String {
        switch self {
        case .singleFile:
            return "Single File"
        case .archive:
            return "Archive"
        case .zipArchive:
            return "ZIP Archive"
        case .tarGzArchive:
            return "TAR.GZ Archive"
        case .tarBz2Archive:
            return "TAR.BZ2 Archive"
        case .tarXzArchive:
            return "TAR.XZ Archive"
        case .directory:
            return "Directory"
        case .multiFile:
            return "Multi-File"
        case .custom:
            return "Custom"
        case .builtIn:
            return "Built-in"
        default:
            return "Unspecified"
        }
    }
}

public extension RAModelInfo.OneOf_Artifact {
    var artifactType: RAModelArtifactType {
        switch self {
        case .singleFile:
            return .singleFile
        case .archive(let archive):
            return archive.type.artifactType
        case .multiFile:
            return .multiFile
        case .customStrategyID:
            return .custom
        case .builtIn(let enabled):
            return enabled ? .builtIn : .unspecified
        }
    }

    var requiresExtraction: Bool {
        if case .archive = self { return true }
        return artifactType.requiresExtraction
    }

    var requiresDownload: Bool {
        if case .builtIn(let enabled) = self, enabled { return false }
        return artifactType.requiresDownload
    }

    var displayName: String {
        switch self {
        case .singleFile:
            return RAModelArtifactType.singleFile.displayName
        case .archive(let artifact):
            return "\(artifact.type.displayName) Archive"
        case .multiFile(let artifact):
            return "Multi-File (\(artifact.files.count) files)"
        case .customStrategyID(let strategyId):
            return strategyId.isEmpty ? "Custom" : "Custom (\(strategyId))"
        case .builtIn:
            return RAModelArtifactType.builtIn.displayName
        }
    }

    var archiveArtifact: RAArchiveArtifact? {
        if case .archive(let artifact) = self { return artifact }
        return nil
    }

    var multiFileDescriptors: [RAModelFileDescriptor] {
        if case .multiFile(let artifact) = self { return artifact.files }
        return []
    }

    var expectedFiles: RAExpectedModelFiles {
        switch self {
        case .singleFile(let artifact):
            if artifact.hasExpectedFiles { return artifact.expectedFiles }
            return RAExpectedModelFiles.patterns(
                required: artifact.requiredPatterns,
                optional: artifact.optionalPatterns
            )
        case .archive(let artifact):
            if artifact.hasExpectedFiles { return artifact.expectedFiles }
            return RAExpectedModelFiles.patterns(
                required: artifact.requiredPatterns,
                optional: artifact.optionalPatterns
            )
        default:
            return .none
        }
    }
}

public extension RAModelInfo {
    static func make(
        id: String,
        name: String,
        category: ModelCategory,
        format: ModelFormat,
        framework: InferenceFramework,
        downloadURL: URL? = nil,
        localPath: URL? = nil,
        artifact: RAModelInfo.OneOf_Artifact? = nil,
        downloadSizeBytes: Int64? = nil,
        contextLength: Int? = nil,
        supportsThinking: Bool = false,
        thinkingPattern: RAModelThinkingTagPattern? = nil,
        description: String? = nil,
        source: ModelSource = .remote,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> RAModelInfo {
        var model = RAModelInfo()
        model.id = id
        model.name = name
        model.category = category
        model.format = format
        model.framework = framework
        model.setDownloadURL(downloadURL)
        model.setLocalPath(localPath)
        model.downloadSizeBytes = downloadSizeBytes ?? 0
        model.contextLength = Int32(contextLength ?? (category.requiresContextLength ? 2048 : 0))
        model.supportsThinking = category.supportsThinking ? supportsThinking : false
        if model.supportsThinking {
            model.thinkingPattern = thinkingPattern ?? .defaultPattern
        }
        model.description_p = description ?? ""
        model.source = source
        model.createdAtUnixMs = unixMilliseconds(from: createdAt)
        model.updatedAtUnixMs = unixMilliseconds(from: updatedAt)
        model.setArtifact(artifact ?? inferredArtifact(from: downloadURL, format: format))
        model.isDownloaded = model.isDownloadedOnDisk
        model.isAvailable = model.isAvailableForUse
        return model
    }

    var downloadURLValue: URL? {
        guard !downloadURL.isEmpty else { return nil }
        return URL(string: downloadURL)
    }

    var localPathURL: URL? {
        Self.registryURL(from: localPath)
    }

    var downloadSizeHint: Int64 {
        downloadSizeBytes
    }

    var isBuiltIn: Bool {
        if case .builtIn(let enabled)? = artifact, enabled {
            return true
        }
        if artifactType == .builtIn {
            return true
        }
        if localPath.hasPrefix("builtin:") {
            return true
        }
        return framework == .foundationModels || framework == .systemTts
    }

    var isDownloadedOnDisk: Bool {
        if isBuiltIn { return true }
        guard let localPath = localPathURL else { return false }

        let (exists, isDirectory) = FileOperationsUtilities.existsWithType(at: localPath)
        if exists && isDirectory {
            return FileOperationsUtilities.isNonEmptyDirectory(at: localPath)
        }
        return exists
    }

    var isAvailableForUse: Bool {
        isBuiltIn || isDownloadedOnDisk || isAvailable
    }

    var requiresExtraction: Bool {
        artifact?.requiresExtraction ?? artifactType.requiresExtraction
    }

    var requiresDownload: Bool {
        if isBuiltIn { return false }
        return artifact?.requiresDownload ?? artifactType.requiresDownload
    }

    var artifactDisplayName: String {
        artifact?.displayName ?? artifactType.displayName
    }

    var archiveArtifact: RAArchiveArtifact? {
        if let artifact = artifact?.archiveArtifact {
            return artifact
        }
        switch artifactType {
        case .archive:
            return makeArchiveArtifact(type: .zip, structure: .unknown)
        case .zipArchive:
            return makeArchiveArtifact(type: .zip, structure: .unknown)
        case .tarGzArchive:
            return makeArchiveArtifact(type: .tarGz, structure: .unknown)
        case .tarBz2Archive:
            return makeArchiveArtifact(type: .tarBz2, structure: .unknown)
        case .tarXzArchive:
            return makeArchiveArtifact(type: .tarXz, structure: .unknown)
        default:
            return nil
        }
    }

    var multiFileDescriptors: [RAModelFileDescriptor] {
        artifact?.multiFileDescriptors ?? multiFile.files
    }

    var expectedArtifactFiles: RAExpectedModelFiles {
        if hasExpectedFiles { return expectedFiles }
        return artifact?.expectedFiles ?? .none
    }

    mutating func setDownloadURL(_ url: URL?) {
        downloadURL = url?.absoluteString ?? ""
    }

    mutating func setLocalPath(_ url: URL?) {
        localPath = url.map(Self.registryPathString(from:)) ?? ""
        isDownloaded = isDownloadedOnDisk
        isAvailable = isAvailableForUse
    }

    mutating func setArtifact(_ artifact: RAModelInfo.OneOf_Artifact) {
        self.artifact = artifact
        artifactType = artifact.artifactType
        let expected = artifact.expectedFiles
        if !expected.isEmptyManifest {
            expectedFiles = expected
        }
    }

    static func inferredArtifact(from url: URL?, format _: ModelFormat) -> RAModelInfo.OneOf_Artifact {
        guard let url, let archiveType = ArchiveType.from(url: url) else {
            return .singleFile(RASingleFileArtifact())
        }
        return .archive(makeArchiveArtifact(type: archiveType, structure: .unknown))
    }
}

private extension RAExpectedModelFiles {
    static func patterns(required: [String], optional: [String]) -> RAExpectedModelFiles {
        var files = RAExpectedModelFiles()
        files.requiredPatterns = required
        files.optionalPatterns = optional
        return files
    }
}

private extension RAArchiveType {
    var artifactType: RAModelArtifactType {
        switch self {
        case .zip:
            return .zipArchive
        case .tarGz:
            return .tarGzArchive
        case .tarBz2:
            return .tarBz2Archive
        case .tarXz:
            return .tarXzArchive
        default:
            return .archive
        }
    }
}

private func makeArchiveArtifact(type: RAArchiveType, structure: RAArchiveStructure) -> RAArchiveArtifact {
    var artifact = RAArchiveArtifact()
    artifact.type = type
    artifact.structure = structure
    return artifact
}

private func unixMilliseconds(from date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
}

private extension RAModelInfo {
    static func registryPathString(from url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    static func registryURL(from value: String) -> URL? {
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: value)
    }
}
