//
//  RunAnywhere+Storage.swift
//  RunAnywhere SDK
//
//  Public API for storage and download operations.
//

import CRACommons
import Foundation

public extension RunAnywhere {
    /// Register a remote model with the in-memory model registry from a
    /// download URL. Delegates the full build-and-save flow to the canonical
    /// `rac_register_model_from_url_proto` C ABI (P2-T6); only the parameters
    /// the proto request does not yet model (id override, memory hint, thinking
    /// flag, LoRA flag, explicit artifact type) are patched onto the saved
    /// `RAModelInfo` and re-persisted through the registry's proto save path.
    @discardableResult
    static func registerModel(
        id: String? = nil,
        name: String,
        url: String,
        framework: InferenceFramework,
        modality: ModelCategory = .language,
        artifactType: RAModelArtifactType? = nil,
        memoryRequirement: Int64? = nil,
        supportsThinking: Bool = false,
        supportsLora: Bool = false
    ) async throws -> RAModelInfo {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        var request = RARegisterModelFromUrlRequest()
        request.url = url
        request.name = name
        request.framework = framework
        request.category = modality

        var model = try registerModelFromUrl(request)

        var needsResave = false
        if let id, id != model.id {
            model.id = id
            needsResave = true
        }
        if let memoryRequirement {
            model.downloadSizeBytes = memoryRequirement
            model.memoryRequiredBytes = memoryRequirement
            needsResave = true
        }
        if supportsThinking {
            model.supportsThinking = true
            model.thinkingPattern = .defaultPattern
            needsResave = true
        }
        if supportsLora {
            model.supportsLora = true
            needsResave = true
        }
        if let artifactType {
            model.artifactType = artifactType
            needsResave = true
        }

        if needsResave {
            model.updatedAtUnixMs = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
            try await CppBridge.ModelRegistry.shared.save(model)
        }

        return model
    }

    /// Register an archive-packaged model (tar.gz / tar.bz2 / tar.xz / zip)
    /// where the caller needs to specify the on-disk layout (`directoryBased`,
    /// `nestedDirectory`, etc.) the URL-form `registerModel` cannot infer.
    ///
    /// Composes the canonical URL-form `registerModel(...)` (which delegates
    /// to `rac_register_model_from_url_proto`) and then patches the resolved
    /// `RAArchiveArtifact.structure` before re-saving through the registry.
    @discardableResult
    static func registerModel(
        archive url: String,
        structure: RAArchiveStructure,
        id: String? = nil,
        name: String,
        framework: InferenceFramework,
        modality: ModelCategory = .language,
        archiveType: RAArchiveType? = nil,
        memoryRequirement: Int64? = nil,
        supportsThinking: Bool = false,
        supportsLora: Bool = false
    ) async throws -> RAModelInfo {
        let resolvedArtifactType: RAModelArtifactType? = archiveType.map { type in
            switch type {
            case .zip:      return .zipArchive
            case .tarGz:    return .tarGzArchive
            case .tarBz2:   return .tarBz2Archive
            case .tarXz:    return .tarXzArchive
            default:        return .archive
            }
        }

        var model = try await registerModel(
            id: id,
            name: name,
            url: url,
            framework: framework,
            modality: modality,
            artifactType: resolvedArtifactType,
            memoryRequirement: memoryRequirement,
            supportsThinking: supportsThinking,
            supportsLora: supportsLora
        )

        // Preserve structure on the archive artifact. `inferredArtifact` only
        // captures the archive type, not the nested/directory layout, so we
        // patch it here and re-persist through the registry's proto save path.
        guard var archiveArtifact = model.archiveArtifact else {
            return model
        }
        archiveArtifact.structure = structure
        model.setArtifact(.archive(archiveArtifact))
        model.updatedAtUnixMs = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        try await CppBridge.ModelRegistry.shared.save(model)
        return model
    }

    /// Register a multi-file model (e.g., VLMs with a separate mmproj, MiniLM
    /// embedding with vocab.txt). Builds `RAModelInfo` via the canonical
    /// `RAModelInfo.make(...)` factory and persists through the registry's
    /// proto save path — no URL is involved at the model level because each
    /// `RAModelFileDescriptor` carries its own URL.
    @discardableResult
    static func registerModel(
        multiFile descriptors: [RAModelFileDescriptor],
        id: String,
        name: String,
        framework: InferenceFramework,
        modality: ModelCategory = .language,
        memoryRequirement: Int64? = nil,
        contextLength: Int? = nil,
        supportsThinking: Bool = false,
        source: RAModelSource = .remote
    ) async throws -> RAModelInfo {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        var artifact = RAMultiFileArtifact()
        artifact.files = descriptors

        var model = RAModelInfo.make(
            id: id,
            name: name,
            category: modality,
            format: .unspecified,
            framework: framework,
            artifact: .multiFile(artifact),
            downloadSizeBytes: memoryRequirement,
            contextLength: contextLength ?? (modality.requiresContextLength ? 2048 : nil),
            supportsThinking: supportsThinking,
            source: source
        )
        if let memoryRequirement {
            model.memoryRequiredBytes = memoryRequirement
        }
        try await CppBridge.ModelRegistry.shared.save(model)
        return model
    }

    /// Download a registered model. Commons owns planning, transfer (via the
    /// URLSession HTTP adapter), extraction, and validation; Swift owns the
    /// plan → start → poll → import orchestration loop and surfaces the
    /// generated proto progress events to the caller.
    @discardableResult
    static func downloadModel(
        _ model: RAModelInfo,
        onProgress: ((RADownloadProgress) async -> Void)? = nil
    ) async throws -> RADownloadProgress {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .network)
        }
        try await ensureServicesReady()

        let resolvedModel = await resolveModelForDownload(model)
        SDKLogger.download.info("Planning download for \(resolvedModel.id)")

        var planRequest = RADownloadPlanRequest()
        planRequest.modelID = resolvedModel.id
        planRequest.model = resolvedModel
        planRequest.resumeExisting = true
        planRequest.validateExistingBytes = true
        planRequest.verifyChecksums = !resolvedModel.checksumSha256.isEmpty

        let plan = await planDownload(planRequest)
        guard plan.canStart else {
            let message = plan.errorMessage.isEmpty ? "Unable to create a download plan" : plan.errorMessage
            SDKLogger.download.error("Download plan rejected for \(resolvedModel.id): \(message)")
            throw SDKException(
                code: .downloadFailed,
                message: message,
                category: .network
            )
        }

        var startRequest = RADownloadStartRequest()
        startRequest.modelID = resolvedModel.id
        startRequest.plan = plan
        startRequest.resume = plan.canResume
        startRequest.resumeToken = plan.resumeToken
        // Commons currently owns planning/progress but not the final registry
        // mutation behind this flag. Persist completion explicitly through the
        // generated model import contract below.
        startRequest.updateRegistryOnCompletion = false

        let startResult = await CppBridge.Download.shared.start(startRequest)
        guard startResult.accepted else {
            let message = startResult.errorMessage.isEmpty
                ? "The download could not be started"
                : startResult.errorMessage
            SDKLogger.download.error("Download start rejected for \(resolvedModel.id): \(message)")
            throw SDKException(
                code: .downloadFailed,
                message: message,
                category: .network
            )
        }

        SDKLogger.download.info(
            "Download accepted for \(resolvedModel.id) (task=\(startResult.taskID))"
        )

        if startResult.hasInitialProgress {
            let progress = startResult.initialProgress
            if try await reportDownloadProgress(progress, onProgress: onProgress) {
                return try await persistDownloadCompletion(model: resolvedModel, progress: progress)
            }
        }

        var subscribeRequest = RADownloadSubscribeRequest()
        subscribeRequest.modelID = startResult.modelID.isEmpty ? resolvedModel.id : startResult.modelID
        subscribeRequest.taskID = startResult.taskID

        // Swift owns the polling/import loop, so a Swift task cancellation
        // must also tear down the native download worker — otherwise the
        // commons download keeps running after the caller's Task ends and
        // updateRegistryOnCompletion=false leaves the registry inconsistent.
        do {
            while true {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 250_000_000)

                let progress = await CppBridge.Download.shared.pollProgress(subscribeRequest)
                if try await reportDownloadProgress(progress, onProgress: onProgress) {
                    return try await persistDownloadCompletion(model: resolvedModel, progress: progress)
                }
            }
        } catch is CancellationError {
            await cancelNativeDownload(taskID: subscribeRequest.taskID, modelID: subscribeRequest.modelID)
            throw CancellationError()
        }
    }

    /// Import a stable, platform-normalized local model path into the generated
    /// registry. This is also the public local-import entry point for file
    /// picker/bookmark flows after Swift has handled sandbox access.
    static func importModel(_ request: RAModelImportRequest) async throws -> RAModelImportResult {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        return try await CppBridge.ModelRegistry.shared.importModel(request)
    }

    /// Get storage information as the canonical generated proto result.
    static func getStorageInfo(_ request: RAStorageInfoRequest = RAStorageInfoRequest()) async -> RAStorageInfoResult {
        await CppBridge.Storage.shared.info(request)
    }

    /// Execute or dry-run storage deletion as canonical generated proto data.
    static func deleteStorage(_ request: RAStorageDeleteRequest) async -> RAStorageDeleteResult {
        await CppBridge.Storage.shared.delete(request)
    }

    /// Clear the SDK's Cache directory. Forwards to `CppBridge.FileManager.clearCache()`,
    /// matching Kotlin's top-level `RunAnywhere.clearCache()` entry point.
    static func clearCache() async throws {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        guard CppBridge.FileManager.clearCache() else {
            throw SDKException(code: .deleteFailed, message: "Failed to clear cache", category: .io)
        }
    }

    /// Clear the SDK's Temp directory. Forwards to `CppBridge.FileManager.clearTemp()`,
    /// matching Kotlin's top-level `RunAnywhere.cleanTempFiles()` entry point.
    static func cleanTempFiles() async throws {
        guard isInitialized else {
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
        let getResult = await getModel(request)
        if getResult.found {
            let registryModel = getResult.model
            if !registryModel.downloadURL.isEmpty || model.downloadURL.isEmpty {
                return registryModel
            }
            return model
        }

        let listResult = await listModels()
        guard listResult.success else { return model }
        if let listed = listResult.models.models.first(where: { $0.id == model.id }) {
            if !listed.downloadURL.isEmpty || model.downloadURL.isEmpty {
                return listed
            }
        }
        return model
    }

    /// Plan a download and retry once after clearing oversize partial bytes.
    static func planDownload(_ request: RADownloadPlanRequest) async -> RADownloadPlanResult {
        var plan = await CppBridge.Download.shared.plan(request)
        guard !plan.canStart,
              plan.errorMessage.contains("existing partial bytes exceed") else {
            return plan
        }

        for file in plan.files where !file.destinationPath.isEmpty {
            let partialURL = URL(fileURLWithPath: file.destinationPath)
            if FileManager.default.fileExists(atPath: partialURL.path) {
                try? FileManager.default.removeItem(at: partialURL)
                SDKLogger.download.warning(
                    "Removed oversize partial download at \(file.destinationPath) for \(request.modelID)"
                )
            }
        }

        return await CppBridge.Download.shared.plan(request)
    }

    /// Single-call URL → saved ModelInfo via `rac_register_model_from_url_proto`.
    static func registerModelFromUrl(_ request: RARegisterModelFromUrlRequest) throws -> RAModelInfo {
        var outBuffer = rac_proto_buffer_t()
        defer { rac_proto_buffer_free(&outBuffer) }

        let data = try request.serializedData()
        let status = data.withUnsafeBytes { rawBuffer -> rac_result_t in
            let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            return rac_register_model_from_url_proto(bytes, rawBuffer.count, &outBuffer)
        }

        guard status == RAC_SUCCESS, outBuffer.status == RAC_SUCCESS else {
            let message = outBuffer.error_message.map { String(cString: $0) }
                ?? "rac_register_model_from_url_proto rc=\(status)"
            throw SDKException(code: .processingFailed, message: message, category: .internal)
        }
        guard let bytes = outBuffer.data, outBuffer.size > 0 else {
            throw SDKException(
                code: .processingFailed,
                message: "rac_register_model_from_url_proto returned empty payload",
                category: .internal
            )
        }
        return try RAModelInfo(serializedBytes: Data(bytes: bytes, count: outBuffer.size))
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
                message: progress.errorMessage.isEmpty ? "Download failed" : progress.errorMessage,
                category: .network
            )
        case .cancelled:
            throw SDKException(code: .cancelled, message: "Download cancelled", category: .network)
        default:
            return progress.stage == .completed
        }
    }

    static func persistDownloadCompletion(
        model: RAModelInfo,
        progress: RADownloadProgress
    ) async throws -> RADownloadProgress {
        let localPath = progress.localPath.isEmpty ? model.localPath : progress.localPath
        guard !localPath.isEmpty else {
            throw SDKException(
                code: .invalidState,
                message: "Download completed without a local_path; cannot import completion into the model registry",
                category: .network
            )
        }

        var importedModel = model
        importedModel.localPath = localPath
        importedModel.isDownloaded = true
        importedModel.isAvailable = true
        importedModel.updatedAtUnixMs = Int64((Date().timeIntervalSince1970 * 1_000).rounded())

        var request = RAModelImportRequest()
        request.model = importedModel
        request.sourcePath = localPath
        request.overwriteExisting = true
        request.copyIntoManagedStorage = false
        request.validateBeforeRegister = false
        request.files = importedModel.multiFileDescriptors

        let result = try await importModel(request)
        guard result.success else {
            throw SDKException(
                code: .downloadFailed,
                message: result.errorMessage.isEmpty
                    ? "Downloaded model could not be imported into the registry"
                    : result.errorMessage,
                category: .network
            )
        }

        return progress
    }
}
