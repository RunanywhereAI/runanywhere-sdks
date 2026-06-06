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
    /// download URL. Builds a complete `RAModelInfo` via the canonical
    /// `RAModelInfo.make(...)` factory (which derives id/format/artifact via
    /// `rac_model_info_make_proto`), layers on the caller-supplied capability
    /// fields, and persists through the registry's proto save path in a single
    /// `save(...)` — `rac_model_registry_register_proto` already persists every
    /// capability field, so no from-url call + re-save dance is required.
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

        let downloadURL = URL(string: url)
        var model = RAModelInfo.make(
            id: id ?? generatedModelID(from: url, name: name),
            name: name,
            category: modality,
            format: .unspecified,
            framework: framework,
            downloadURL: downloadURL,
            downloadSizeBytes: memoryRequirement,
            contextLength: modality.requiresContextLength ? 2048 : nil,
            supportsThinking: supportsThinking
        )
        if let memoryRequirement {
            model.memoryRequiredBytes = memoryRequirement
        }
        if supportsLora {
            model.supportsLora = true
        }
        // Apply the explicit artifact-type override last: `make(...)` derives
        // the artifact (and its artifact_type) from the URL, so the caller's
        // override has to win after that derivation runs.
        if let artifactType {
            model.artifactType = artifactType
        }

        try await CppBridge.ModelRegistry.shared.save(model)
        return model
    }

    /// Register an archive-packaged model (tar.gz / tar.bz2 / tar.xz / zip)
    /// where the caller needs to specify the on-disk layout (`directoryBased`,
    /// `nestedDirectory`, etc.) the URL-form `registerModel` cannot infer.
    ///
    /// Builds the archive artifact (type + caller-specified structure) inline,
    /// layers on the caller-supplied capability fields, and persists through the
    /// registry's proto save path in a single `save(...)`.
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
        guard isInitialized else {
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
            downloadSizeBytes: memoryRequirement,
            contextLength: modality.requiresContextLength ? 2048 : nil,
            supportsThinking: supportsThinking
        )
        if let memoryRequirement {
            model.memoryRequiredBytes = memoryRequirement
        }
        if supportsLora {
            model.supportsLora = true
        }

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

    /// Derive a stable model id from a download URL via commons
    /// `rac_model_id_from_url` (the same extension-stripping logic the legacy
    /// from-url register path used). Falls back to the human-readable name when
    /// the URL yields nothing usable.
    static func generatedModelID(from url: String, name: String) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let status = url.withCString { urlPtr in
            rac_model_id_from_url(urlPtr, &buffer, buffer.count)
        }
        if status == RAC_SUCCESS {
            let derived = String(cString: buffer)
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
