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
//  `lora.download` helpers.
//
//  `RALoraAdapterCatalogEntry` no longer carries url/filename/size/checksum
//  metadata (idl/lora_options.proto: "everything generic about the artifact
//  ... lives on the ModelInfo record for this adapter"), so the artifact can
//  no longer be derived from the entry alone — callers supply the `artifact`
//  `RAModelInfo` describing where/how to fetch the adapter bytes (e.g. built
//  via `RAModelInfo.make(...)`).
//

import Foundation

// MARK: - Catalog entry → model artifact

public extension RALoraAdapterCatalogEntry {

    /// Stable model-registry id used for this adapter's download artifact.
    var loraArtifactModelID: String {
        id.hasPrefix(LoRAArtifactMetadata.modelIDPrefix) ? id : LoRAArtifactMetadata.modelIDPrefix + id
    }
}

// MARK: - SDK-owned download

public extension RunAnywhere.LoRA {

    /// Register both the LoRA catalog entry and its caller-supplied
    /// downloadable artifact record. Does not fetch bytes.
    ///
    /// - Parameter artifact: Generated model metadata describing where/how to
    ///   fetch the adapter bytes (e.g. built via `RAModelInfo.make(...)`).
    ///   Tagged with `LoRAArtifactMetadata.adapterTag` before being saved so
    ///   `RAModelInfo.isLoRAAdapterArtifact` recognizes it.
    @discardableResult
    func registerArtifact(_ entry: RALoraAdapterCatalogEntry, artifact: RAModelInfo) async throws -> RAModelInfo {
        _ = try await register(entry)
        var tagged = artifact
        var tags = tagged.metadata.tags
        if !tags.contains(LoRAArtifactMetadata.adapterTag) {
            tags.append(LoRAArtifactMetadata.adapterTag)
        }
        tagged.metadata.tags = tags
        try await CppBridge.ModelRegistry.shared.save(tagged)
        return tagged
    }

    /// Download a LoRA adapter through the canonical model-download pipeline.
    ///
    /// One call does everything the app used to hand-roll: registers the
    /// catalog entry + artifact, downloads with resume/checksum/progress via
    /// commons, and returns the stable local path of the adapter file.
    ///
    /// `LoraAdapterDownloadCompletedRequest`/`Result` were deleted outright
    /// (idl/lora_options.proto, lora-delete-download-import-bookkeeping) with
    /// no replacement message, and nothing in commons ever wrote a fresh
    /// value onto `RALoraAdapterCatalogEntry.localPath` even before that
    /// deletion — the field is query/filter-only there (`downloadedOnly`
    /// filtering), never consumed at LoRA-apply time. `RunAnywhere.lora.apply`
    /// takes the resolved `localPath` directly (see
    /// `RunAnywhere+LoRA.swift`'s `apply(_:localPath:scale:replaceExisting:)`),
    /// so there is nothing left to "mark completed" — the model-registry
    /// artifact record (keyed by `loraArtifactModelID`) is the sole source of
    /// truth for the downloaded path.
    @discardableResult
    func download(
        _ entry: RALoraAdapterCatalogEntry,
        artifact: RAModelInfo,
        onProgress: ((RADownloadProgress) async -> Void)? = nil
    ) async throws -> String {
        let registeredArtifact = try await registerArtifact(entry, artifact: artifact)
        let finalProgress = try await RunAnywhere.performDownload(registeredArtifact, onProgress: onProgress)

        var localPath = finalProgress.localPath
        if localPath.isEmpty {
            // The download step persisted the path on the registry record.
            var getRequest = RAModelGetRequest()
            getRequest.modelID = registeredArtifact.id
            let lookup = await RunAnywhere.performGet(getRequest)
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
        return localPath
    }
}

// MARK: - SDK-owned local-file import

public extension RunAnywhere.LoRA {

    /// Import a user-picked LoRA adapter file (document picker / share sheet)
    /// into SDK-owned storage.
    ///
    /// `LoraAdapterImportRequest`/`Result` were deleted outright
    /// (idl/lora_options.proto, lora-delete-download-import-bookkeeping):
    /// the LoRA-domain import verb — which used to do deterministic catalog
    /// matching, canonical `{Models}/{framework}/lora-adapter:{id}/`
    /// placement, and catalog `imported=true` completion — has no
    /// replacement in that domain. Adapter files are now acquired
    /// exclusively through the models domain's generic import verb
    /// (`RunAnywhere.importModel`, `RAModelImportRequest`/`Result`), so this
    /// resolves platform access and imports as a plain model artifact
    /// tagged `lora-adapter`. Unlike the retired ABI, this does NOT
    /// automatically match the import against an existing LoRA catalog
    /// entry — callers that need the catalog association call
    /// `register(_:)`/`registerArtifact(_:)` with the matching entry
    /// themselves once they know which adapter this file corresponds to.
    @discardableResult
    func importAdapter(from url: URL) async throws -> RAModelImportResult {
        guard RunAnywhere.isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var model = RAModelInfo()
        model.metadata.tags = [LoRAArtifactMetadata.adapterTag]

        var request = RAModelImportRequest()
        request.model = model
        request.sourcePath = url.path
        request.copyIntoManagedStorage = true
        request.validateBeforeRegister = true

        return try await RunAnywhere.importModel(request)
    }
}
