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

// MARK: - Catalog entry → model artifact

public extension RALoraAdapterCatalogEntry {

    /// Stable model-registry id used for this adapter's download artifact.
    var loraArtifactModelID: String {
        id.hasPrefix(LoRAArtifactMetadata.modelIDPrefix) ? id : LoRAArtifactMetadata.modelIDPrefix + id
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
        model.category = .unspecified
        model.framework = .unspecified
        if hasChecksumSha256, !checksumSha256.isEmpty {
            model.checksumSha256 = checksumSha256
        }
        model.expectedFiles = expected
        model.metadata.description_p = description_p
        if hasAuthor { model.metadata.author = author }
        if hasLicense { model.metadata.license = license }
        var metadataTags = [LoRAArtifactMetadata.adapterTag]
        metadataTags.append(contentsOf: compatibleModels.map {
            "\(LoRAArtifactMetadata.baseModelTagPrefix)\($0)"
        })
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

public extension RunAnywhere.LoRA {

    /// Import a user-picked LoRA adapter file (document picker / share sheet)
    /// into SDK-owned storage.
    ///
    /// Swift only resolves the platform-specific access (security-scoped URL);
    /// commons owns everything past the readable source path: deterministic
    /// catalog matching, canonical placement, artifact registry record +
    /// manifest persistence, and catalog completion for matched entries.
    /// Apps apply the returned `localPath`; they never construct on-disk
    /// paths themselves.
    @discardableResult
    func importAdapter(from url: URL) async throws -> RALoraAdapterImportResult {
        guard RunAnywhere.isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var request = RALoraAdapterImportRequest()
        request.sourcePath = url.path

        let result = try await CppBridge.LoraRegistry.shared.importAdapter(request)
        guard result.success else {
            throw SDKException(
                code: .processingFailed,
                message: result.errorMessage.isEmpty
                    ? "LoRA adapter import failed"
                    : result.errorMessage,
                category: .internal
            )
        }
        return result
    }
}
