//
//  ModelTypes+Artifacts.swift
//  RunAnywhere SDK
//
//  Artifact/archive/expected-files helpers for the generated model contract
//  types. Heavy logic (factory defaults, expected-files derivation, on-disk
//  probe, archive inference) lives in commons; this file is now a thin
//  shim that routes through `rac_model_info_make_proto` (P2-T4),
//  `rac_artifact_expected_files_proto` (P2-T7) and
//  `rac_path_is_non_empty_directory`.
//

import CRACommons
import Foundation

// MARK: - Native ABI bindings (P2-T4 / P2-T7)

private enum ArtifactProtoABI {
    static let makeModelInfo = NativeProtoABI.load(
        "rac_model_info_make_proto",
        as: NativeProtoABI.ProtoRequest.self
    )
    static let expectedFiles = NativeProtoABI.load(
        "rac_artifact_expected_files_proto",
        as: NativeProtoABI.ProtoRequest.self
    )
}

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
        case .singleFile:       return "Single File"
        case .archive:          return "Archive"
        case .zipArchive:       return "ZIP Archive"
        case .tarGzArchive:     return "TAR.GZ Archive"
        case .tarBz2Archive:    return "TAR.BZ2 Archive"
        case .tarXzArchive:     return "TAR.XZ Archive"
        case .directory:        return "Directory"
        case .multiFile:        return "Multi-File"
        case .custom:           return "Custom"
        case .builtIn:          return "Built-in"
        default:                return "Unspecified"
        }
    }
}

public extension RAModelInfo.OneOf_Artifact {
    var artifactType: RAModelArtifactType {
        switch self {
        case .singleFile:               return .singleFile
        case .archive(let archive):     return archive.type.artifactType
        case .multiFile:                return .multiFile
        case .customStrategyID:         return .custom
        case .builtIn(let enabled):     return enabled ? .builtIn : .unspecified
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
}

public extension RAModelInfo {
    /// Build a fully-populated `RAModelInfo`. Defaults (id/name/format/
    /// framework/category/source/context-length/thinking-pattern/artifact/
    /// artifact_type) come from the canonical commons factory
    /// (`rac_model_info_make_proto`, P2-T4); caller-supplied non-request
    /// fields are layered on top.
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
        thinkingPattern: RAThinkingTagPattern? = nil,
        description: String? = nil,
        source: ModelSource = .remote,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> RAModelInfo {
        var request = RAModelInfoMakeRequest()
        request.url = downloadURL?.absoluteString ?? ""
        request.name = name
        request.framework = framework
        request.category = category
        request.source = source

        var model = (try? NativeProtoABI.invoke(
            request,
            symbol: ArtifactProtoABI.makeModelInfo,
            symbolName: "rac_model_info_make_proto",
            responseType: RAModelInfo.self
        )) ?? RAModelInfo()

        // Caller-supplied id always wins (matches the legacy Swift contract);
        // commons would otherwise derive it from the URL via rac_model_generate_id.
        model.id = id
        // Caller-supplied scalar fields not part of the make request.
        model.format = format
        model.downloadSizeBytes = downloadSizeBytes ?? 0
        if let contextLength {
            // Clamp into Int32 — the proto field is i32 and callers may pass
            // an `Int` that doesn't fit (e.g. `Int.max` on a 64-bit host),
            // which `Int32.init(_:)` would trap on. Cap at `Int32.max` /
            // floor at `Int32.min` so we surface a saturated value instead.
            model.contextLength = Int32(clamping: contextLength)
        }
        // Thinking is gated by category; the commons factory leaves the
        // per-call flag false, so honor the caller override here. Match the
        // legacy contract: when thinking is enabled and the caller did not
        // supply a pattern, fall back to the default pattern.
        model.supportsThinking = category.supportsThinking ? supportsThinking : false
        if model.supportsThinking {
            model.thinkingPattern = thinkingPattern ?? .defaultPattern
        }
        model.description_p = description ?? ""
        model.createdAtUnixMs = unixMilliseconds(from: createdAt)
        model.updatedAtUnixMs = unixMilliseconds(from: updatedAt)
        // Caller-supplied artifact override re-runs the artifact-type sync.
        if let artifact {
            model.setArtifact(artifact)
        }
        // Caller-supplied local path runs the disk probe via setLocalPath.
        model.setLocalPath(localPath)
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
        if case .builtIn(let enabled)? = artifact, enabled { return true }
        if artifactType == .builtIn { return true }
        if localPath.hasPrefix("builtin:") { return true }
        return framework == .foundationModels || framework == .systemTts
    }

    /// Disk-probe via `rac_path_is_non_empty_directory` for directories,
    /// falling back to `FileManager` for single-file artifacts.
    var isDownloadedOnDisk: Bool {
        if isBuiltIn { return true }
        guard let localPath = localPathURL else { return false }
        let (exists, isDirectory) = FileOperationsUtilities.existsWithType(at: localPath)
        if exists && isDirectory {
            return localPath.path.withCString { rac_path_is_non_empty_directory($0) == RAC_TRUE }
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
        if let archive = artifact?.archiveArtifact { return archive }
        guard let archiveType = artifactType.legacyArchiveType else { return nil }
        var fallback = RAArchiveArtifact()
        fallback.type = archiveType
        fallback.structure = .unknown
        return fallback
    }

    var multiFileDescriptors: [RAModelFileDescriptor] {
        artifact?.multiFileDescriptors ?? multiFile.files
    }

    /// Canonical expected-files manifest. Routes through
    /// `rac_artifact_expected_files_proto` (P2-T7) which mirrors the legacy
    /// Swift fall-through (top-level manifest → artifact-attached manifest →
    /// pattern shorthand → multi-file descriptor seed).
    var expectedArtifactFiles: RAExpectedModelFiles {
        if hasExpectedFiles { return expectedFiles }
        return (try? NativeProtoABI.invoke(
            self,
            symbol: ArtifactProtoABI.expectedFiles,
            symbolName: "rac_artifact_expected_files_proto",
            responseType: RAExpectedModelFiles.self
        )) ?? .none
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
        // Derive strictly from the new artifact (clear top-level so the ABI
        // skips its hasExpectedFiles short-circuit and walks the artifact
        // branch). Restore previous manifest if the artifact yields nothing.
        let prior = hasExpectedFiles ? expectedFiles : nil
        clearExpectedFiles()
        let derived = expectedArtifactFiles
        if !derived.isEmptyManifest {
            expectedFiles = derived
        } else if let prior {
            expectedFiles = prior
        }
    }

    /// Pure-Swift archive-type inference. Wraps `RAArchiveType.from(url:)`
    /// (which calls `rac_archive_type_from_path`) so callers can derive the
    /// artifact oneof without going through the full make-proto path.
    static func inferredArtifact(from url: URL?, format _: ModelFormat) -> RAModelInfo.OneOf_Artifact {
        guard let url, let archiveType = ArchiveType.from(url: url) else {
            return .singleFile(RASingleFileArtifact())
        }
        var artifact = RAArchiveArtifact()
        artifact.type = archiveType
        artifact.structure = .unknown
        return .archive(artifact)
    }
}

// MARK: - Private helpers

private extension RAModelArtifactType {
    /// Map the legacy archive enum cases to their equivalent `RAArchiveType`.
    /// Returns `nil` for non-archive cases.
    var legacyArchiveType: RAArchiveType? {
        switch self {
        case .archive, .zipArchive: return .zip
        case .tarGzArchive:         return .tarGz
        case .tarBz2Archive:        return .tarBz2
        case .tarXzArchive:         return .tarXz
        default:                    return nil
        }
    }
}

private extension RAArchiveType {
    var artifactType: RAModelArtifactType {
        switch self {
        case .zip:      return .zipArchive
        case .tarGz:    return .tarGzArchive
        case .tarBz2:   return .tarBz2Archive
        case .tarXz:    return .tarXzArchive
        default:        return .archive
        }
    }
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
