//
//  ModelsNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.models` — registry, download, and load/unload. Generation
//  verbs auto-load, so `load` is for callers who want to choose when the cost
//  is paid.
//

import Foundation

public extension RunAnywhere {

    /// Model registry and lifecycle.
    static var models: Models { Models() }

    /// List, register, download, load, and delete models.
    struct Models: Sendable {

        /// List registry entries, optionally narrowed by `filter`.
        ///
        /// ```swift
        /// let llms = try await RunAnywhere.models.list(filter: .init(category: .language))
        /// print(llms.count)
        /// ```
        ///
        /// - Throws: `SDKException` when the registry cannot be read.
        public func list(filter: ModelFilter? = nil) async throws -> [ModelInfo] {
            var request = RAModelListRequest()
            if let filter { request.query = filter.toProto() }
            let result = await RunAnywhere.performList(request)
            guard !result.hasError else {
                throw SDKException(proto: result.error)
            }
            return result.models.models
        }

        /// Fetch one registry entry, or `nil` when the id is unknown.
        public func get(id: String) async -> ModelInfo? {
            var request = RAModelGetRequest()
            request.modelID = id
            let result = await RunAnywhere.performGet(request)
            return result.found ? result.model : nil
        }

        /// Add a model to the registry from a URL, an archive, or a file set.
        ///
        /// - Throws: `SDKException` when registration is rejected.
        @discardableResult
        public func register(_ registration: ModelRegistration) async throws -> ModelInfo {
            switch registration.payload {
            case .url(let url):
                return try await RunAnywhere.registerFromURL(
                    id: registration.id,
                    name: registration.name,
                    url: url,
                    framework: registration.framework,
                    modality: registration.category,
                    memoryRequirement: registration.memoryRequirementBytes,
                    supportsThinking: registration.supportsThinking,
                    supportsLora: registration.supportsLora,
                    cuaProfile: registration.cuaProfile
                )
            case .archive(let url, let structure, let type):
                return try await RunAnywhere.registerArchive(
                    url: url,
                    structure: structure,
                    id: registration.id,
                    name: registration.name,
                    framework: registration.framework,
                    modality: registration.category,
                    archiveType: type,
                    memoryRequirement: registration.memoryRequirementBytes,
                    supportsThinking: registration.supportsThinking,
                    supportsLora: registration.supportsLora,
                    cuaProfile: registration.cuaProfile
                )
            case .multiFile(let files):
                guard let id = registration.id else {
                    throw SDKException(
                        code: .invalidArgument,
                        message: "Multi-file registration needs an explicit model id",
                        category: .validation
                    )
                }
                return try await RunAnywhere.registerMultiFile(
                    descriptors: files,
                    id: id,
                    name: registration.name,
                    framework: registration.framework,
                    modality: registration.category,
                    memoryRequirement: registration.memoryRequirementBytes,
                    contextLength: registration.contextLength,
                    supportsThinking: registration.supportsThinking,
                    downloadSize: registration.downloadSizeBytes,
                    cuaProfile: registration.cuaProfile
                )
            }
        }

        /// Download a registered model, reporting progress until it completes.
        ///
        /// `DownloadEvent.progress.percent` is 0–100, matching the other SDKs.
        /// Every event on this stream carries the same `operationId`, and
        /// `sequence` is monotonically increasing within that operation.
        ///
        /// The stream ends in `completed`, `failed`, or `cancelled` — never a
        /// silent finish, and `completed` is only ever emitted when the
        /// download genuinely finished.
        ///
        /// - Throws: `SDKException` when the id is unknown.
        public func download(id: String) async throws -> AsyncThrowingStream<DownloadEvent, Error> {
            guard let model = await get(id: id) else {
                throw SDKException(
                    code: .modelNotFound,
                    message: "Model '\(id)' is not registered",
                    category: .validation
                )
            }

            return AsyncThrowingStream { continuation in
                let task = Task {
                    var operationId = id
                    var sequence: Int64 = 0
                    var sawStarted = false
                    func nextSequence() -> Int64 {
                        sequence += 1
                        return sequence
                    }

                    do {
                        _ = try await RunAnywhere.performDownload(model) { progress in
                            if !progress.taskID.isEmpty { operationId = progress.taskID }
                            if !sawStarted {
                                sawStarted = true
                                continuation.yield(.started(operationId: operationId, sequence: nextSequence()))
                            }
                            // RADownloadStage was folded into RADownloadState
                            // (idl/download_service.proto) — switch on
                            // `.state` directly.
                            //
                            // The terminal states are named so they cannot fall
                            // into the progress branch: `performDownload`
                            // reports each of them again a few lines below as
                            // the stream's own terminal event, and a progress
                            // snapshot emitted alongside would announce a live
                            // byte count for a transfer that has already
                            // stopped. Everything else — pending, downloading,
                            // retrying, paused, resuming — is a transfer still
                            // in motion and reads as progress.
                            switch progress.state {
                            case .validating:
                                continuation.yield(.verifying(operationId: operationId, sequence: nextSequence()))
                            case .extracting:
                                continuation.yield(.extracting(
                                    operationId: operationId,
                                    sequence: nextSequence(),
                                    percent: progress.stageProgress * 100
                                ))
                            case .completed, .failed, .cancelled:
                                break
                            default:
                                continuation.yield(.progress(DownloadProgressSnapshot(
                                    operationId: operationId,
                                    sequence: nextSequence(),
                                    bytesDone: progress.bytesDownloaded,
                                    bytesTotal: progress.totalBytes,
                                    file: progress.currentFileName.isEmpty ? nil : progress.currentFileName,
                                    // C++ reports 0 for "not measured yet" and
                                    // the proto leaves eta absent (or -1) for
                                    // "unknown". Both are normalised to nil so a
                                    // UI can tell missing from genuinely zero
                                    // and show nothing rather than "0 B/s"
                                    // while the transfer spins up.
                                    bytesPerSecond: progress.bytesPerSecond > 0 ? progress.bytesPerSecond : nil,
                                    etaSeconds: progress.hasEtaSeconds && progress.etaSeconds >= 0
                                        ? progress.etaSeconds : nil,
                                    retryAttempt: Int(progress.retryAttempt),
                                    currentFileIndex: Int(progress.currentFileIndex),
                                    totalFiles: max(Int(progress.totalFiles), 1),
                                    overallProgress: progress.overallProgress > 0
                                        ? progress.overallProgress : nil
                                )))
                            }
                        }
                        let refreshed = await self.get(id: id) ?? model
                        continuation.yield(.completed(operationId: operationId, sequence: nextSequence(), model: refreshed))
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.yield(.cancelled(operationId: operationId, sequence: nextSequence()))
                        continuation.finish()
                    } catch {
                        continuation.yield(.failed(
                            operationId: operationId,
                            sequence: nextSequence(),
                            error: SDKException.from(error, category: .network)
                        ))
                        continuation.finish()
                    }
                }
                continuation.onTermination = { @Sendable termination in
                    if case .cancelled = termination { task.cancel() }
                }
            }
        }

        /// Whether a previous, unfinished download for `id` left bytes that the
        /// next `download(id:)` will continue from instead of re-fetching.
        ///
        /// Starting a download *is* resuming it (see `download_service.proto`),
        /// so this reports nothing about how to resume — only whether resuming
        /// would actually save work. It exists so a UI can label the action
        /// honestly: offering "Resume" when the bytes are gone is a lie, and
        /// offering "Get" when 90% of a 3 GB file is on disk understates it.
        ///
        /// Answered from disk, not from session state, so it stays correct
        /// across an app relaunch — which is the case that matters, because an
        /// interrupted multi-gigabyte download is usually discovered on the next
        /// launch rather than in the session that started it.
        public func isResumable(id: String) async -> Bool {
            await RunAnywhere.resumableDownloadBytes(modelID: id) > 0
        }

        /// Delete a downloaded model's files and reset its registry path.
        ///
        /// - Throws: `SDKException` when deletion fails.
        public func delete(id: String) async throws {
            let result = await RunAnywhere.performDelete(id)
            guard !result.hasError else {
                throw SDKException(proto: result.error)
            }
        }

        /// Load a model now instead of waiting for the first generation call.
        ///
        /// Only `LoadOptions.backendPreferences.first` (equivalently the
        /// deprecated `framework`) reaches commons today. `contextLength`,
        /// `threads`, `accelerator`, and additional ordered `backendPreferences`
        /// are not yet carried by the native load ABI, so passing them throws
        /// rather than being silently dropped.
        ///
        /// - Throws: `SDKException` when the model cannot be loaded, or when
        ///   `options` sets a placement knob the load ABI cannot honor yet.
        @discardableResult
        public func load(id: String, options: LoadOptions? = nil) async throws -> LoadedModel {
            guard let model = await get(id: id) else {
                throw SDKException(
                    code: .modelNotFound,
                    message: "Model '\(id)' is not registered",
                    category: .validation
                )
            }
            let category = model.category == .unspecified ? .language : model.category
            let result = try await RunAnywhere.loadResolved(model: model, category: category, options: options)

            let resolvedId = result.modelID.isEmpty ? model.id : result.modelID
            let resolvedCategory = result.category == .unspecified ? category : result.category
            let actualBackend = result.framework != .unspecified ? result.framework : model.framework
            let requestedBackend = options?.backendPreferences.first?.backend

            return LoadedModel(
                id: resolvedId,
                category: resolvedCategory,
                requestedBackend: requestedBackend,
                actualBackend: actualBackend,
                actualDevice: DevicePlacement(),
                runtimeVersion: nil,
                abiVersion: nil,
                fallbackReason: result.warnings.first,
                closeHandler: { modelId in
                    try await RunAnywhere.models.unload(id: modelId)
                }
            )
        }

        /// Release one resident model by id. Idempotent: unloading a model
        /// that is not resident is not an error.
        ///
        /// - Throws: `SDKException` when the unload is rejected.
        public func unload(id: String) async throws {
            var request = RAModelUnloadRequest()
            request.modelID = id
            let result = await RunAnywhere.performUnload(request)
            guard !result.hasError else {
                throw SDKException(proto: result.error)
            }
        }

        /// Unload one category, or everything when `category` is `nil`. This is
        /// the only category/global unload; `unload(id:)` releases one model.
        ///
        /// - Throws: `SDKException` when the unload is rejected.
        public func unloadAll(category: ModelCategory? = nil) async throws {
            var request = RAModelUnloadRequest()
            if let category {
                request.category = category
                let snapshot = RunAnywhere.loadedModelSnapshot(category: category)
                guard snapshot.found else { return }
                request.modelID = snapshot.modelID
            } else {
                request.unloadAll = true
            }
            let result = await RunAnywhere.performUnload(request)
            guard !result.hasError else {
                throw SDKException(proto: result.error)
            }
        }

        /// Deprecated: unload one category, or everything when `category` is `nil`.
        @available(*, deprecated, renamed: "unloadAll(category:)")
        public func unload(category: ModelCategory? = nil) async throws {
            try await unloadAll(category: category)
        }

        /// Remove `id` from the registry. Registration metadata only — this
        /// never touches downloaded files or a resident load.
        ///
        /// - Throws: `SDKException` when `id` is unknown, still loaded, or
        ///   still has local artifacts. Unload or delete first.
        public func unregister(id: String) async throws {
            guard let info = await get(id: id) else {
                throw SDKException(
                    code: .modelNotFound,
                    message: "Model '\(id)' is not registered",
                    category: .validation
                )
            }

            let stillLoaded = Models.trackedCategories.contains { category in
                let snapshot = RunAnywhere.loadedModelSnapshot(category: category)
                return snapshot.found && snapshot.modelID == id
            }
            guard !stillLoaded else {
                throw SDKException(
                    code: .invalidState,
                    message: "Model '\(id)' is still loaded; call models.unload(id:) first",
                    category: .validation
                )
            }

            // ModelInfo.isDownloaded was deleted outright
            // (idl/model_types.proto: "reserved 32; // was is_downloaded: a
            // bool cannot express DOWNLOADING"). registry_status is the
            // sole downloaded-ness signal now; a non-empty localPath is the
            // simplest local proxy for it, same as everywhere else in this SDK.
            let hasLocalArtifacts = !info.localPath.isEmpty
            guard !hasLocalArtifacts else {
                throw SDKException(
                    code: .invalidState,
                    message: "Model '\(id)' still has local artifacts; call models.delete(id:) first",
                    category: .validation
                )
            }

            try await CppBridge.ModelRegistry.shared.remove(modelId: id)
        }

        /// Report what is loaded per category and how much storage is left.
        public func state() async -> ModelsState {
            var loaded: [ModelCategory: ModelInfo] = [:]
            for category in Models.trackedCategories {
                let snapshot = RunAnywhere.loadedModelSnapshot(category: category, includeModelMetadata: true)
                guard snapshot.found else { continue }
                if snapshot.hasModel {
                    loaded[category] = snapshot.model
                } else {
                    var stub = ModelInfo()
                    stub.id = snapshot.modelID
                    stub.category = category
                    loaded[category] = stub
                }
            }

            var request = RAStorageInfoRequest()
            request.includeDevice = true
            request.includeApp = true
            request.includeModels = true
            let storage = await RunAnywhere.storageInfo(request)
            let info = storage.hasInfo ? storage.info : RAStorageInfo()

            return ModelsState(
                loaded: loaded,
                storageUsedBytes: info.totalModelsBytes,
                storageFreeBytes: info.hasDevice ? info.device.freeBytes : 0
            )
        }

        /// Rescan managed model directories and reconcile downloaded state.
        public func refresh(
            rescanLocal: Bool = true,
            includeRemoteCatalog: Bool = false,
            pruneOrphans: Bool = false
        ) async {
            await RunAnywhere.performRegistryRefresh(
                rescanLocal: rescanLocal,
                includeRemoteCatalog: includeRemoteCatalog,
                pruneOrphans: pruneOrphans
            )
        }

        private static let trackedCategories: [ModelCategory] = [
            .language, .multimodal, .vision, .speechRecognition, .speechSynthesis,
            .voiceActivityDetection, .embedding, .imageGeneration,
            .speakerDiarization, .semanticSegmentation
        ]
    }
}

// MARK: - Auto-load resolver shared by the generation namespaces

extension RunAnywhere {

    /// Make sure `category` has a resident model and return its id.
    ///
    /// When `modelId` is nil the already-loaded model is used. When it names a
    /// different model, the model is downloaded if absent and then loaded.
    internal static func ensureLoaded(
        modelId: String?,
        category: ModelCategory,
        fallbackCategories: [ModelCategory] = [],
        downloadIfNeeded: Bool = true,
        loadOptions: LoadOptions? = nil
    ) async throws -> String {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        let categories = [category] + fallbackCategories
        let resident = firstLoadedModelSnapshot(categories: categories)

        guard let modelId, !modelId.isEmpty else {
            guard let resident, !resident.modelID.isEmpty else {
                throw SDKException(
                    code: .modelNotLoaded,
                    message: "No \(category.wireString) model is loaded; pass options.model or call models.load(id:)",
                    category: .component
                )
            }
            return resident.modelID
        }

        if let resident, resident.modelID == modelId {
            return modelId
        }

        var getRequest = RAModelGetRequest()
        getRequest.modelID = modelId
        let lookup = await performGet(getRequest)
        guard lookup.found else {
            throw SDKException(
                code: .modelNotFound,
                message: "Model '\(modelId)' is not registered",
                category: .validation
            )
        }

        var model = lookup.model
        // ModelInfo.isDownloaded deleted outright — see the comment on the
        // sibling check in `unregister` above.
        let alreadyDownloaded = !model.localPath.isEmpty
        if !alreadyDownloaded {
            guard downloadIfNeeded else {
                throw SDKException(
                    code: .modelNotFound,
                    message: "Model '\(modelId)' is registered but not downloaded",
                    category: .validation
                )
            }
            _ = try await performDownload(model)
            var refetch = RAModelGetRequest()
            refetch.modelID = modelId
            let refreshed = await performGet(refetch)
            if refreshed.found { model = refreshed.model }
        }

        let effectiveCategory = model.category == .unspecified ? category : model.category
        try await loadResolved(model: model, category: effectiveCategory, options: loadOptions)
        return modelId
    }

    @discardableResult
    internal static func loadResolved(
        model: ModelInfo,
        category: ModelCategory,
        options: LoadOptions?
    ) async throws -> RAModelLoadResult {
        if let options {
            try options.requireCarriableByLoadABI()
        }

        var request = RAModelLoadRequest()
        request.modelID = model.id
        request.category = category == .unspecified ? category.defaultLoadCategory : category
        request.forceReload = options?.forceReload ?? false
        if let backend = options?.backendPreferences.first?.backend, backend != .unspecified {
            request.framework = backend
        } else if model.framework != .unspecified {
            request.framework = model.framework
        }
        request.validateAvailability = true

        let result = await performLoad(request)
        guard !result.hasError else {
            throw SDKException(
                code: .modelLoadFailed,
                message: "Model '\(model.id)': \(result.error.message)",
                category: .component
            )
        }
        return result
    }
}

private extension LoadOptions {
    /// `backendPreferences.first` reaches commons through the same
    /// `RAModelLoadRequest.framework` field the deprecated `framework:`
    /// property already uses. Everything else the native load ABI cannot
    /// carry yet — honoring it silently would violate the "every accepted
    /// field is implemented end to end or fails preflight" contract.
    func requireCarriableByLoadABI() throws {
        var unsupported: [String] = []
        if contextLength != nil { unsupported.append("contextLength") }
        if threads != nil { unsupported.append("threads") }
        if accelerator != nil { unsupported.append("accelerator") }
        if backendPreferences.count > 1 {
            unsupported.append("backendPreferences (only the first preference reaches commons; ordered fallback is not carried)")
        }
        guard unsupported.isEmpty else {
            throw SDKException.invalidConfiguration(
                "LoadOptions.\(unsupported.joined(separator: ", ")) cannot be carried by the native load ABI yet"
            )
        }
    }
}

private extension ModelCategory {
    /// `.unspecified` is not a loadable slot; treat it as a language model.
    var defaultLoadCategory: ModelCategory { self == .unspecified ? .language : self }
}
