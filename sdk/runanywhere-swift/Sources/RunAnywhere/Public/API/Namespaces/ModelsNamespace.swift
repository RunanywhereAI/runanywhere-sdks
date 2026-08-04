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
        ///
        /// - Throws: `SDKException` from this call when the id is unknown, and
        ///   into the returned stream when the transfer fails.
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
                    var sawExtracting = false
                    do {
                        _ = try await RunAnywhere.performDownload(model) { progress in
                            if progress.stage == .extracting, !sawExtracting {
                                sawExtracting = true
                                continuation.yield(.extracting)
                            }
                            continuation.yield(.progress(
                                bytesDone: progress.bytesDownloaded,
                                bytesTotal: progress.totalBytes,
                                percent: progress.overallProgress * 100
                            ))
                        }
                        let refreshed = await self.get(id: id) ?? model
                        continuation.yield(.completed(refreshed))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable termination in
                    if case .cancelled = termination { task.cancel() }
                }
            }
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
        /// Only `LoadOptions.framework` reaches commons today; the remaining
        /// placement knobs are logged and ignored until the load ABI carries them.
        ///
        /// - Throws: `SDKException` when the model cannot be loaded.
        public func load(id: String, options: LoadOptions? = nil) async throws {
            guard let model = await get(id: id) else {
                throw SDKException(
                    code: .modelNotFound,
                    message: "Model '\(id)' is not registered",
                    category: .validation
                )
            }
            try await RunAnywhere.loadResolved(
                model: model,
                category: model.category,
                options: options
            )
        }

        /// Unload one category, or everything when `category` is `nil`.
        ///
        /// - Throws: `SDKException` when the unload is rejected.
        public func unload(category: ModelCategory? = nil) async throws {
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
        let alreadyDownloaded = model.hasIsDownloaded ? model.isDownloaded : !model.localPath.isEmpty
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

    internal static func loadResolved(
        model: ModelInfo,
        category: ModelCategory,
        options: LoadOptions?
    ) async throws {
        if let options {
            let ignored = [
                options.contextLength != nil ? "contextLength" : nil,
                options.threads != nil ? "threads" : nil,
                options.useGpu != nil ? "useGpu" : nil
            ].compactMap { $0 }
            if !ignored.isEmpty {
                SDKLogger.models.warning(
                    "LoadOptions \(ignored.joined(separator: ", ")) are not carried by the commons load ABI yet"
                )
            }
        }

        var request = RAModelLoadRequest()
        request.modelID = model.id
        request.category = category == .unspecified ? category.defaultLoadCategory : category
        if let framework = options?.framework, framework != .unspecified {
            request.framework = framework
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
    }
}

private extension ModelCategory {
    /// `.unspecified` is not a loadable slot; treat it as a language model.
    var defaultLoadCategory: ModelCategory { self == .unspecified ? .language : self }
}
