//
//  RunAnywhere+Storage.swift
//  RunAnywhere SDK
//
//  Public API for storage and download operations.
//

import CRACommons
import Foundation

extension RunAnywhere {
    /// Register a remote model with the in-memory model registry from a
    /// download URL or Hugging Face reference, through the canonical commons
    /// factory (`rac_register_model_from_url_proto`). Commons derives
    /// id/name/format/artifact, resolves `hf.co/org/repo[:quant]` refs (quant
    /// selection, mmproj pairing, sharded GGUF sets, per-file checksums), and
    /// preserves prior download state when a catalog re-seeds on launch.
    ///
    /// Pass `cuaProfile` (e.g. `RunAnywhere.CUA.faraProfile`) for a computer-use
    /// agent model; it lands on `RAModelInfo.cuaProfile` so callers can discover
    /// which registered models are drivable through `RunAnywhere.CUA`.
    @discardableResult
    @available(*, deprecated, renamed: "models.register(_:)")
    public static func registerModel(
        id: String? = nil,
        name: String,
        url: String,
        framework: InferenceFramework,
        modality: ModelCategory = .language,
        artifactType: RAModelArtifactType? = nil,
        memoryRequirement: Int64? = nil,
        supportsThinking: Bool = false,
        supportsLora: Bool = false,
        cuaProfile: String? = nil
    ) async throws -> RAModelInfo {
        try await registerFromURL(
            id: id,
            name: name,
            url: url,
            framework: framework,
            modality: modality,
            artifactType: artifactType,
            memoryRequirement: memoryRequirement,
            supportsThinking: supportsThinking,
            supportsLora: supportsLora,
            cuaProfile: cuaProfile
        )
    }

    @discardableResult
    internal static func registerFromURL(
        id: String? = nil,
        name: String,
        url: String,
        framework: InferenceFramework,
        modality: ModelCategory = .language,
        artifactType: RAModelArtifactType? = nil,
        memoryRequirement: Int64? = nil,
        supportsThinking: Bool = false,
        supportsLora: Bool = false,
        cuaProfile: String? = nil
    ) async throws -> RAModelInfo {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        var request = RARegisterModelFromUrlRequest()
        request.url = url
        request.name = name
        request.framework = framework
        request.category = modality
        if let id {
            request.id = id
        }
        if let cuaProfile, !cuaProfile.isEmpty {
            request.cuaProfile = cuaProfile
        }
        if let memoryRequirement {
            request.memoryRequiredBytes = memoryRequirement
        }
        if modality.requiresContextLength {
            request.contextLength = Int32(RADefaults.Storage.contextLength)
        }
        if supportsThinking {
            request.supportsThinking = true
        }
        if supportsLora {
            request.supportsLora = true
        }
        if let artifactType {
            request.artifactType = artifactType
        }

        return try await CppBridge.ModelRegistry.shared.registerFromUrl(request)
    }

    /// Register an archive-packaged model (tar.gz / tar.bz2 / tar.xz / zip)
    /// where the caller needs to specify the on-disk layout (`directoryBased`,
    /// `nestedDirectory`, etc.) the URL-form `registerModel` cannot infer.
    ///
    /// Builds the archive artifact (type + caller-specified structure) inline,
    /// layers on the caller-supplied capability fields, and persists through the
    /// registry's proto save path in a single `save(...)`.
    @discardableResult
    @available(*, deprecated, renamed: "models.register(_:)")
    public static func registerModel(
        archive url: String,
        structure: RAArchiveStructure,
        id: String? = nil,
        name: String,
        framework: InferenceFramework,
        modality: ModelCategory = .language,
        archiveType: RAArchiveType? = nil,
        memoryRequirement: Int64? = nil,
        supportsThinking: Bool = false,
        supportsLora: Bool = false,
        cuaProfile: String? = nil
    ) async throws -> RAModelInfo {
        try await registerArchive(
            url: url,
            structure: structure,
            id: id,
            name: name,
            framework: framework,
            modality: modality,
            archiveType: archiveType,
            memoryRequirement: memoryRequirement,
            supportsThinking: supportsThinking,
            supportsLora: supportsLora,
            cuaProfile: cuaProfile
        )
    }

    @discardableResult
    internal static func registerArchive(
        url: String,
        structure: RAArchiveStructure,
        id: String? = nil,
        name: String,
        framework: InferenceFramework,
        modality: ModelCategory = .language,
        archiveType: RAArchiveType? = nil,
        memoryRequirement: Int64? = nil,
        supportsThinking: Bool = false,
        supportsLora: Bool = false,
        cuaProfile: String? = nil
    ) async throws -> RAModelInfo {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        let downloadURL = URL(string: url)

        // Resolve the archive type (caller override → inference from the URL),
        // then build the archive artifact carrying the caller-specified layout
        // structure that the URL alone cannot infer.
        var archiveArtifact = RAArchiveArtifact()
        if let archiveType {
            archiveArtifact.type = archiveType
        } else if let downloadURL, let inferred = ArchiveType.from(url: downloadURL) {
            archiveArtifact.type = inferred
        }
        archiveArtifact.structure = structure

        var model = RAModelInfo.make(
            id: id ?? generatedModelID(from: url, name: name),
            name: name,
            category: modality,
            format: .unspecified,
            framework: framework,
            downloadURL: downloadURL,
            artifact: .archive(archiveArtifact),
            downloadSizeBytes: nil,
            contextLength: modality.requiresContextLength ? 2048 : nil,
            supportsThinking: supportsThinking
        )
        if let memoryRequirement {
            model.memoryRequiredBytes = memoryRequirement
        }
        if supportsLora {
            model.supportsLora = true
        }
        if let cuaProfile, !cuaProfile.isEmpty {
            model.cuaProfile = cuaProfile
        }

        try await CppBridge.ModelRegistry.shared.save(model)
        return model
    }

    /// Register a multi-file model (e.g., VLMs with a separate mmproj, MiniLM
    /// embedding with vocab.txt) through the canonical commons factory
    /// (`rac_register_multi_file_model_proto`) — no URL is involved at the
    /// model level because each `RAModelFileDescriptor` carries its own URL.
    @discardableResult
    @available(*, deprecated, renamed: "models.register(_:)")
    public static func registerModel(
        multiFile descriptors: [RAModelFileDescriptor],
        id: String,
        name: String,
        framework: InferenceFramework,
        modality: ModelCategory = .language,
        memoryRequirement: Int64? = nil,
        contextLength: Int? = nil,
        supportsThinking: Bool = false,
        source: RAModelSource = .remote,
        downloadSize: Int64? = nil,
        cuaProfile: String? = nil
    ) async throws -> RAModelInfo {
        try await registerMultiFile(
            descriptors: descriptors,
            id: id,
            name: name,
            framework: framework,
            modality: modality,
            memoryRequirement: memoryRequirement,
            contextLength: contextLength,
            supportsThinking: supportsThinking,
            source: source,
            downloadSize: downloadSize,
            cuaProfile: cuaProfile
        )
    }

    @discardableResult
    internal static func registerMultiFile(
        descriptors: [RAModelFileDescriptor],
        id: String,
        name: String,
        framework: InferenceFramework,
        modality: ModelCategory = .language,
        memoryRequirement: Int64? = nil,
        contextLength: Int? = nil,
        supportsThinking: Bool = false,
        source: RAModelSource = .remote,
        downloadSize: Int64? = nil,
        cuaProfile: String? = nil
    ) async throws -> RAModelInfo {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        var request = RARegisterMultiFileModelRequest()
        request.id = id
        request.name = name
        request.framework = framework
        request.category = modality
        request.files = descriptors
        request.source = source
        applyMultiFileRegistrationSizes(
            memoryRequirement: memoryRequirement,
            downloadSize: downloadSize,
            to: &request
        )
        if let contextLength {
            request.contextLength = Int32(contextLength)
        } else if modality.requiresContextLength {
            request.contextLength = Int32(RADefaults.Storage.contextLength)
        }
        if supportsThinking {
            request.supportsThinking = true
        }
        if let cuaProfile, !cuaProfile.isEmpty {
            request.cuaProfile = cuaProfile
        }

        return try await CppBridge.ModelRegistry.shared.registerMultiFile(request)
    }

    /// Keeps runtime memory planning independent from the final download
    /// footprint. The RAM requirement never stands in for the download size:
    /// a nil download size is left unset so commons resolves the real payload
    /// size from the server (Content-Length) instead of trusting a RAM hint.
    internal static func applyMultiFileRegistrationSizes(
        memoryRequirement: Int64?,
        downloadSize: Int64?,
        to request: inout RARegisterMultiFileModelRequest
    ) {
        if let memoryRequirement {
            request.memoryRequiredBytes = memoryRequirement
        }
        if let downloadSize {
            request.downloadSizeBytes = downloadSize
        }
    }

    /// Download a registered model. Commons owns planning, transfer (via the
    /// URLSession HTTP adapter), extraction, and validation; Swift owns the
    /// plan → start → poll → import orchestration loop and surfaces the
    /// generated proto progress events to the caller.
    @discardableResult
    @available(*, deprecated, renamed: "models.download(id:)")
    public static func downloadModel(
        _ model: RAModelInfo,
        onProgress: ((RADownloadProgress) async -> Void)? = nil
    ) async throws -> RADownloadProgress {
        try await performDownload(model, onProgress: onProgress)
    }

    @discardableResult
    internal static func performDownload(
        _ model: RAModelInfo,
        onProgress: ((RADownloadProgress) async -> Void)? = nil
    ) async throws -> RADownloadProgress {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .network)
        }
        try await ensureServicesReady()

        let resolvedModel = await resolveModelForDownload(model)
        SDKLogger.download.info("Planning download for \(resolvedModel.id)")

        let plan = await planDownload(downloadPlanRequest(for: resolvedModel))
        guard plan.canStart else {
            let message = plan.hasError ? plan.error.message : "Unable to create a download plan"
            SDKLogger.download.error("Download plan rejected for \(resolvedModel.id): \(message)")
            throw SDKException(code: .downloadFailed, message: message, category: .network)
        }

        // Background-eligible transfers stream to their final paths via a
        // background URLSession that survives app suspension. The commons
        // start+poll below then finds the files already complete on disk and
        // finalizes the registry without re-downloading. Non-eligible plans
        // (extraction, unknown sizes) fall straight through to commons.
        if BackgroundDownloadCoordinator.shared.shouldHandle(plan) {
            try await BackgroundDownloadCoordinator.shared.prefetch(
                plan: plan,
                model: resolvedModel,
                onProgress: onProgress
            )
        }

        return try await startAndPollDownload(plan: plan, model: resolvedModel, onProgress: onProgress)
    }

    /// Bytes an interrupted download left behind that a restart would continue
    /// from, or 0 when a restart would begin from scratch.
    ///
    /// Reads the plan the coordinator persisted for the interrupted attempt, so
    /// the answer survives an app relaunch. No plan on disk means no interrupted
    /// transfer to resume.
    internal static func resumableDownloadBytes(modelID: String) async -> Int64 {
        BackgroundDownloadCoordinator.shared.resumableBytes(modelID: modelID)
    }

    /// Drive the commons start+poll finalize for a model whose files a background
    /// transfer already placed on disk. Used by the coordinator when the app was
    /// relaunched to deliver background session events and no caller is awaiting.
    @discardableResult
    internal static func finalizeBackgroundDownload(modelID: String) async throws -> RADownloadProgress {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .network)
        }
        try await ensureServicesReady()

        var getRequest = RAModelGetRequest()
        getRequest.modelID = modelID
        let getResult = await performGet(getRequest)
        guard getResult.found else {
            throw SDKException(code: .modelNotFound, message: "Model '\(modelID)' is not registered", category: .validation)
        }
        let model = getResult.model
        let plan = await planDownload(downloadPlanRequest(for: model))
        guard plan.canStart else {
            if model.isAvailableForUse {
                var done = RADownloadProgress()
                done.modelID = modelID
                done.state = .completed
                return done
            }
            let message = plan.hasError ? plan.error.message : "Unable to finalize download"
            throw SDKException(code: .downloadFailed, message: message, category: .network)
        }
        return try await startAndPollDownload(plan: plan, model: model, onProgress: nil)
    }

    /// Stream download progress for a registered model.
    @available(*, deprecated, renamed: "models.download(id:)")
    public static func downloadModelStream(_ model: RAModelInfo) -> AsyncThrowingStream<RADownloadProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await performDownload(model) { progress in
                        continuation.yield(progress)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination {
                    task.cancel()
                }
            }
        }
    }

    /// Import a stable, platform-normalized local model path into the generated
    /// registry. This is also the public local-import entry point for file
    /// picker/bookmark flows after Swift has handled sandbox access.
    public static func importModel(_ request: RAModelImportRequest) async throws -> RAModelImportResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        return try await CppBridge.ModelRegistry.shared.importModel(request)
    }

    /// Get storage information as the canonical generated proto result.
    @available(*, deprecated, renamed: "models.state()")
    public static func getStorageInfo(_ request: RAStorageInfoRequest = RAStorageInfoRequest()) async -> RAStorageInfoResult {
        await storageInfo(request)
    }

    internal static func storageInfo(
        _ request: RAStorageInfoRequest = RAStorageInfoRequest()
    ) async -> RAStorageInfoResult {
        await CppBridge.Storage.shared.info(request)
    }

    /// Execute or dry-run storage deletion as canonical generated proto data.
    public static func deleteStorage(_ request: RAStorageDeleteRequest) async -> RAStorageDeleteResult {
        await CppBridge.Storage.shared.delete(request)
    }

    /// Delete one downloaded model end-to-end.
    @discardableResult
    @available(*, deprecated, renamed: "models.delete(id:)")
    public static func deleteModel(_ modelId: String) async -> RAStorageDeleteResult {
        await performDelete(modelId)
    }

    @discardableResult
    internal static func performDelete(_ modelId: String) async -> RAStorageDeleteResult {
        var request = RAStorageDeleteRequest()
        request.modelIds = [modelId]
        // deleteFiles was deleted and replaced by the inverted
        // keepFilesOnDisk (idl/storage_types.proto): files are deleted by
        // default now, so the old "delete files" intent is simply the
        // proto3 zero value (leave keepFilesOnDisk unset/false).
        request.clearRegistryPaths_p = true
        request.unloadIfLoaded = true
        request.allowPlatformDelete = true
        return await deleteStorage(request)
    }

    /// Empty the SDK's cache directory.
    public static func clearCache() async throws {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        guard CppBridge.FileManager.clearCache() else {
            throw SDKException(code: .deleteFailed, message: "Failed to clear cache", category: .io)
        }
    }

    /// Empty the SDK's temp directory.
    public static func cleanTempFiles() async throws {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        guard CppBridge.FileManager.clearTemp() else {
            throw SDKException(code: .deleteFailed, message: "Failed to clean temp files", category: .io)
        }
    }
}

private extension RunAnywhere {
    /// Prefer the registry's canonical metadata when the caller passes a list-row
    /// snapshot that may be missing download_url, archive layout, or checksum fields.
    /// Mirrors Kotlin TC-07 which re-fetches `RAModelInfo` from `listModels()` before
    /// `downloadModel(...)`.
    static func resolveModelForDownload(_ model: RAModelInfo) async -> RAModelInfo {
        var request = RAModelGetRequest()
        request.modelID = model.id
        let getResult = await performGet(request)
        if getResult.found {
            let registryModel = getResult.model
            if !registryModel.downloadURL.isEmpty || model.downloadURL.isEmpty {
                return registryModel
            }
            return model
        }

        let listResult = await performList()
        guard !listResult.hasError else { return model }
        if let listed = listResult.models.models.first(where: { $0.id == model.id }) {
            if !listed.downloadURL.isEmpty || model.downloadURL.isEmpty {
                return listed
            }
        }
        return model
    }

    /// Plan a download. Oversize-partial self-healing happens inside the
    /// commons planner (validate_existing_bytes deletes stale partials and
    /// replans as a fresh download), so no Swift-side retry loop is needed.
    static func planDownload(_ request: RADownloadPlanRequest) async -> RADownloadPlanResult {
        await CppBridge.Download.shared.plan(request)
    }

    static func downloadPlanRequest(for model: RAModelInfo) -> RADownloadPlanRequest {
        var request = RADownloadPlanRequest()
        request.modelID = model.id
        request.model = model
        // resumeExisting was deleted outright (idl/download_service.proto):
        // resume is now planner-driven, not a caller opt-in flag.
        request.validateExistingBytes = true
        // verifyChecksums -> skipChecksumVerification, inverted to opt-OUT.
        // The proto3 zero value (false, left unset here) already means
        // "verify whenever the catalog has one" — the exact old intent of
        // `verifyChecksums = !model.checksumSha256.isEmpty` — so there is
        // nothing to opt out of.
        return request
    }

    /// Start the commons download worker for `plan` and poll it to a terminal
    /// state. When a background transfer has already placed the files, the worker
    /// detects them as complete and finalizes the registry without network I/O.
    static func startAndPollDownload(
        plan: RADownloadPlanResult,
        model: RAModelInfo,
        onProgress: ((RADownloadProgress) async -> Void)?
    ) async throws -> RADownloadProgress {
        var startRequest = RADownloadStartRequest()
        startRequest.modelID = model.id
        startRequest.plan = plan
        // resume/resumeToken were deleted outright (idl/download_service.proto)
        // — resume is now planner-driven from `plan` alone.
        //
        // Commons owns the completion registry mutation: the orchestrator's
        // self-heal calls rac_model_registry_update_download_status, which
        // also persists the durable .rac-manifest.binpb sidecar that restores
        // the entry on the next cold launch. updateRegistryOnCompletion=true
        // was renamed+inverted to skipRegistryUpdate, whose zero-value
        // default (false) already means "update the registry", so leaving
        // it unset preserves the old behavior with no line needed.

        let startResult = await CppBridge.Download.shared.start(startRequest)
        guard startResult.accepted else {
            let message = startResult.hasError ? startResult.error.message : "The download could not be started"
            SDKLogger.download.error("Download start rejected for \(model.id): \(message)")
            throw SDKException(code: .downloadFailed, message: message, category: .network)
        }

        SDKLogger.download.info("Download accepted for \(model.id) (task=\(startResult.taskID))")

        if startResult.hasInitialProgress {
            let progress = startResult.initialProgress
            if try await reportDownloadProgress(progress, onProgress: onProgress) {
                return progress
            }
        }

        var subscribeRequest = RADownloadSubscribeRequest()
        subscribeRequest.modelID = startResult.modelID.isEmpty ? model.id : startResult.modelID
        subscribeRequest.taskID = startResult.taskID

        // Swift owns the polling loop, so a Swift task cancellation must also
        // tear down the native download worker — otherwise the commons
        // download keeps running after the caller's Task ends.
        do {
            while true {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 250_000_000)

                let progress = await CppBridge.Download.shared.pollProgress(subscribeRequest)
                if try await reportDownloadProgress(progress, onProgress: onProgress) {
                    return progress
                }
            }
        } catch is CancellationError {
            await cancelNativeDownload(taskID: subscribeRequest.taskID, modelID: subscribeRequest.modelID)
            throw CancellationError()
        }
    }

    /// Derive a stable model id from a download URL via commons
    /// `rac_model_id_from_url`. Used by the archive overload, whose
    /// caller-specified layout structure the from-url factory cannot express.
    static func generatedModelID(from url: String, name: String) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let status = url.withCString { urlPtr in
            rac_model_id_from_url(urlPtr, &buffer, buffer.count)
        }
        if status == RAC_SUCCESS {
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let derived = String(bytes: bytes, encoding: .utf8) ?? ""
            if !derived.isEmpty { return derived }
        }
        return name
    }

    /// Tear down the commons download worker for `taskID` / `modelID` so a
    /// Swift `Task.cancel()` propagates through `rac_download_cancel_proto`.
    /// `deletePartialBytes: false` preserves resume tokens for callers that
    /// retry the same model after cancelling.
    static func cancelNativeDownload(taskID: String, modelID: String) async {
        guard !taskID.isEmpty else { return }
        var cancelRequest = RADownloadCancelRequest()
        cancelRequest.taskID = taskID
        cancelRequest.modelID = modelID
        cancelRequest.deletePartialBytes = false
        _ = await CppBridge.Download.shared.cancel(cancelRequest)
    }

    static func reportDownloadProgress(
        _ progress: RADownloadProgress,
        onProgress: ((RADownloadProgress) async -> Void)?
    ) async throws -> Bool {
        if let onProgress {
            await onProgress(progress)
        }

        switch progress.state {
        case .completed:
            return true
        case .failed:
            throw SDKException(
                code: .downloadFailed,
                message: progress.hasError ? progress.error.message : "Download failed",
                category: .network
            )
        case .cancelled:
            throw SDKException(code: .cancelled, message: "Download cancelled", category: .network)
        default:
            // RADownloadStage was folded into RADownloadState — `.completed`
            // is already handled above, so no other state means "done".
            return false
        }
    }

}
