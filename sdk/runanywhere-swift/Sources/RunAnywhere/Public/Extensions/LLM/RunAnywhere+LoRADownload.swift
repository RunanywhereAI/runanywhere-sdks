//
//  RunAnywhere+LoRADownload.swift
//  RunAnywhere SDK
//
//  SDK-owned LoRA adapter download and local-file import.
//
//  An adapter stays a LoRA catalog entry for apply/remove semantics, while its
//  bytes are represented as a generated model artifact so download/storage
//  policy (planning, resume, checksum, progress events, placement) runs on the
//  canonical model-download path — no app-side URLSession, no app-invented
//  on-disk layout. Mirrors the Kotlin SDK's `lora.registerArtifact` /
//  `toLoraArtifactModelInfo` helpers.
//

import Foundation

private let loraArtifactModelIDPrefix = "lora-adapter:"
private let loraArtifactTag = "lora-adapter"

// MARK: - Catalog entry → model artifact

public extension RALoraAdapterCatalogEntry {

    /// Stable model-registry id used for this adapter's download artifact.
    var loraArtifactModelID: String {
        id.hasPrefix(loraArtifactModelIDPrefix) ? id : loraArtifactModelIDPrefix + id
    }

    /// Convert this catalog entry into generated model-registry metadata used
    /// by the generic download path. Catalog filtering and completion state
    /// remain owned by the LoRA catalog ABI.
    func toLoraArtifactModelInfo() -> RAModelInfo {
        let artifactFilename: String = {
            if !filename.isEmpty { return filename }
            let last = url.split(separator: "/").last.map(String.init) ?? url
            return last.split(separator: "?").first.map(String.init) ?? last
        }()

        var descriptor = RAModelFileDescriptor(
            url: URL(string: url) ?? URL(fileURLWithPath: artifactFilename),
            filename: artifactFilename,
            isRequired: true
        )
        descriptor.role = .companion
        if sizeBytes > 0 {
            descriptor.sizeBytes = sizeBytes
        }
        if hasChecksumSha256, !checksumSha256.isEmpty {
            descriptor.checksumSha256 = checksumSha256
        }

        var expected = RAExpectedModelFiles()
        expected.files = [descriptor]
        expected.requiredPatterns = [artifactFilename]
        expected.description_p = "LoRA adapter artifact"

        var singleFile = RASingleFileArtifact()
        singleFile.requiredPatterns = [artifactFilename]
        singleFile.expectedFiles = expected

        var model = RAModelInfo.make(
            id: loraArtifactModelID,
            name: name,
            category: .unspecified,
            format: .gguf,
            framework: .unspecified,
            downloadURL: URL(string: url),
            artifact: .singleFile(singleFile),
            downloadSizeBytes: sizeBytes > 0 ? sizeBytes : nil,
            description: description_p,
            source: .remote
        )
        if hasChecksumSha256, !checksumSha256.isEmpty {
            model.checksumSha256 = checksumSha256
        }
        model.expectedFiles = expected
        model.metadata.description_p = description_p
        if hasAuthor { model.metadata.author = author }
        if hasLicense { model.metadata.license = license }
        var metadataTags = [loraArtifactTag]
        metadataTags.append(contentsOf: compatibleModels.map { "base-model:\($0)" })
        metadataTags.append(contentsOf: tags)
        var seen = Set<String>()
        model.metadata.tags = metadataTags.filter { seen.insert($0).inserted }
        model.isAvailable = true
        return model
    }
}

// MARK: - SDK-owned download

public extension RunAnywhere.LoRA {

    /// Register both the LoRA catalog entry and its downloadable artifact
    /// record. Does not fetch bytes.
    @discardableResult
    func registerArtifact(_ entry: RALoraAdapterCatalogEntry) async throws -> RAModelInfo {
        let registered = try await register(entry)
        let artifact = registered.toLoraArtifactModelInfo()
        try await CppBridge.ModelRegistry.shared.save(artifact)
        return artifact
    }

    /// Download a LoRA adapter through the canonical model-download pipeline.
    ///
    /// One call does everything the app used to hand-roll: registers the
    /// catalog entry + artifact, downloads with resume/checksum/progress via
    /// commons, records completion in the LoRA catalog, and returns the
    /// stable local path of the adapter file.
    @discardableResult
    func download(
        _ entry: RALoraAdapterCatalogEntry,
        onProgress: ((RADownloadProgress) async -> Void)? = nil
    ) async throws -> String {
        let artifact = try await registerArtifact(entry)
        let finalProgress = try await RunAnywhere.downloadModel(artifact, onProgress: onProgress)

        var localPath = finalProgress.localPath
        if localPath.isEmpty {
            // The import step persisted the path on the registry record.
            var getRequest = RAModelGetRequest()
            getRequest.modelID = artifact.id
            let lookup = await RunAnywhere.getModel(getRequest)
            if lookup.found {
                localPath = lookup.model.localPath
            }
        }
        guard !localPath.isEmpty else {
            throw SDKException(
                code: .downloadFailed,
                message: "LoRA adapter '\(entry.id)' downloaded but no local path was recorded",
                category: .network
            )
        }

        var completed = RALoraAdapterDownloadCompletedRequest()
        completed.adapterID = entry.id
        completed.localPath = localPath
        _ = try await markDownloadCompleted(completed)
        return localPath
    }
}

// MARK: - SDK-owned local-file import

/// Outcome of importing a user-picked LoRA adapter file.
public struct LoraAdapterImportResult: Sendable {
    /// Stable SDK-owned path of the imported adapter file.
    public let localPath: String
    /// Updated catalog entry when the imported file matched a registered adapter.
    public let entry: RALoraAdapterCatalogEntry?
}

public extension RunAnywhere.LoRA {

    /// Import a user-picked LoRA adapter file (document picker / share sheet)
    /// into SDK-owned storage.
    ///
    /// One call owns the whole flow: security-scoped access to the source URL,
    /// placement into the canonical adapter artifact folder (the same layout
    /// the download path uses), and catalog import completion when the file
    /// matches a registered adapter entry. Apps apply the returned
    /// `localPath`; they never construct on-disk paths themselves.
    @discardableResult
    func importAdapter(from url: URL) async throws -> LoraAdapterImportResult {
        guard RunAnywhere.isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        let filename = url.lastPathComponent
        guard !filename.isEmpty, filename != ".", filename != ".." else {
            throw SDKException(
                code: .invalidInput,
                message: "LoRA adapter import requires a file URL with a usable filename",
                category: .validation
            )
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Catalog matching is best-effort: an unhealthy catalog must not block
        // a plain file import. Match deterministically — an exact path match,
        // else a filename match only when it is unambiguous (generic adapter
        // filenames recur across base models; completing an arbitrary entry
        // would corrupt unrelated catalog state).
        let entries = (try? await listCatalog())?.entries ?? []
        let pathMatches = entries.filter { $0.hasLocalPath && $0.localPath == url.path }
        let nameMatches = entries.filter { $0.filename == filename }
        let matched = pathMatches.first ?? (nameMatches.count == 1 ? nameMatches[0] : nil)

        // The catalog entry drives the artifact identity and on-disk placement,
        // so a matched import lands exactly where the download path would put
        // the same adapter.
        var entrySnapshot: RALoraAdapterCatalogEntry
        if let matched {
            entrySnapshot = matched
        } else {
            let stem = url.deletingPathExtension().lastPathComponent
            entrySnapshot = RALoraAdapterCatalogEntry()
            entrySnapshot.id = stem.isEmpty ? filename : stem
            entrySnapshot.name = entrySnapshot.id
            entrySnapshot.filename = filename
        }

        let directory = try CppBridge.ModelPaths.getModelFolder(
            modelId: entrySnapshot.loraArtifactModelID,
            framework: .unspecified
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(filename, isDirectory: false)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)

        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let actualSizeBytes = (attributes?[.size] as? NSNumber)?.int64Value

        // Register the placed bytes as the adapter's artifact record so storage
        // accounting, deleteModel(_:), and cross-session manifest restore
        // observe them — the import counterpart of what the download path
        // persists on completion. The imported file is authoritative: its real
        // size replaces the catalog's, and any catalog checksum is dropped.
        if let actualSizeBytes {
            entrySnapshot.sizeBytes = actualSizeBytes
        }
        entrySnapshot.clearChecksumSha256()
        var artifact = entrySnapshot.toLoraArtifactModelInfo()
        artifact.localPath = destination.path
        try await CppBridge.ModelRegistry.shared.save(artifact)

        guard let matched else {
            return LoraAdapterImportResult(localPath: destination.path, entry: nil)
        }

        var completed = RALoraAdapterDownloadCompletedRequest()
        completed.adapterID = matched.id
        completed.localPath = destination.path
        completed.completedAtUnixMs = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        if let actualSizeBytes {
            completed.sizeBytes = actualSizeBytes
        }

        let result = try await markImportCompleted(completed)
        guard result.success else {
            throw SDKException(
                code: .processingFailed,
                message: result.errorMessage.isEmpty
                    ? "LoRA adapter import completion was not persisted"
                    : result.errorMessage,
                category: .internal
            )
        }
        return LoraAdapterImportResult(
            localPath: destination.path,
            entry: result.hasEntry ? result.entry : nil
        )
    }
}
