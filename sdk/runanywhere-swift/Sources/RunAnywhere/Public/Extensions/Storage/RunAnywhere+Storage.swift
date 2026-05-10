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
    /// download URL. Cross-SDK convenience surface that matches Kotlin's
    /// `RunAnywhere.registerModel(id, name, url, framework, ...)`
    /// (`sdk/runanywhere-kotlin/.../public/extensions/RunAnywhere+ModelManagement.kt:51`).
    ///
    /// The format is inferred from the URL extension via the commons
    /// `rac_model_detect_format_from_extension` helper; the artifact oneof
    /// (single-file vs archive) is inferred via
    /// `RAModelInfo.inferredArtifact(from:format:)`. The resulting
    /// `RAModelInfo` is persisted to the registry through
    /// `CppBridge.ModelRegistry.shared.save(...)`, matching Kotlin's
    /// `registerModelInternal()` path.
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

        let logger = SDKLogger(category: "RunAnywhere.registerModel")
        let modelId = id ?? generateModelId(fromURL: url)
        let format = detectFormat(fromURL: url)
        let now = Int64((Date().timeIntervalSince1970 * 1_000).rounded())

        logger.debug("Registering model: \(modelId) (name: \(name))")
        logger.debug("Detected format: \(format.wireString) for model: \(modelId)")

        var model = RAModelInfo()
        model.id = modelId
        model.name = name
        model.category = modality
        model.format = format
        model.framework = framework
        model.downloadURL = url
        model.downloadSizeBytes = memoryRequirement ?? 0
        if let memoryRequirement {
            model.memoryRequiredBytes = memoryRequirement
        }
        model.contextLength = modality.requiresContextLength ? 2048 : 0
        model.supportsThinking = supportsThinking
        model.supportsLora = supportsLora
        if supportsThinking {
            model.thinkingPattern = .defaultPattern
        }
        model.description_p = "User-added model"
        model.source = .local
        model.createdAtUnixMs = now
        model.updatedAtUnixMs = now

        let urlValue = URL(string: url)
        let inferred = RAModelInfo.inferredArtifact(from: urlValue, format: format)
        model.setArtifact(inferred)
        if let artifactType {
            model.artifactType = artifactType
        }
        model.isDownloaded = model.isDownloadedOnDisk
        model.isAvailable = model.isAvailableForUse

        try await CppBridge.ModelRegistry.shared.save(model)

        logger.info(
            "Registered model: \(modelId) (category: \(modality.wireString), framework: \(framework.wireString))"
        )
        return model
    }

    /// Download a registered model with the generated download plan/start/progress
    /// contracts. Commons owns planning and registry updates; Swift owns the
    /// native URLSession transfer behind the C++ download adapter.
    @discardableResult
    static func downloadModel(
        _ model: RAModelInfo,
        onProgress: ((RADownloadProgress) async -> Void)? = nil
    ) async throws -> RADownloadProgress {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .network)
        }
        try await ensureServicesReady()

        var planRequest = RADownloadPlanRequest()
        planRequest.modelID = model.id
        planRequest.model = model
        planRequest.resumeExisting = true
        planRequest.validateExistingBytes = true
        planRequest.verifyChecksums = !model.checksumSha256.isEmpty

        let plan = await downloadPlan(planRequest)
        guard plan.canStart else {
            throw SDKException(
                code: .downloadFailed,
                message: plan.errorMessage.isEmpty ? "Unable to create a download plan" : plan.errorMessage,
                category: .network
            )
        }

        var startRequest = RADownloadStartRequest()
        startRequest.modelID = model.id
        startRequest.plan = plan
        startRequest.resume = plan.canResume
        startRequest.resumeToken = plan.resumeToken
        // Commons currently owns planning/progress but not the final registry
        // mutation behind this flag. Persist completion explicitly through the
        // generated model import contract below.
        startRequest.updateRegistryOnCompletion = false

        let startResult = await startDownload(startRequest)
        guard startResult.accepted else {
            throw SDKException(
                code: .downloadFailed,
                message: startResult.errorMessage.isEmpty ? "The download could not be started" : startResult.errorMessage,
                category: .network
            )
        }

        if startResult.hasInitialProgress {
            let progress = startResult.initialProgress
            if try await reportDownloadProgress(progress, onProgress: onProgress) {
                return try await persistDownloadCompletion(model: model, progress: progress)
            }
        }

        var subscribeRequest = RADownloadSubscribeRequest()
        subscribeRequest.modelID = startResult.modelID.isEmpty ? model.id : startResult.modelID
        subscribeRequest.taskID = startResult.taskID

        while true {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 250_000_000)

            let progress = await pollDownloadProgress(subscribeRequest)
            if try await reportDownloadProgress(progress, onProgress: onProgress) {
                return try await persistDownloadCompletion(model: model, progress: progress)
            }
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

    /// Build a native download plan using canonical generated proto data.
    static func downloadPlan(_ request: RADownloadPlanRequest) async -> RADownloadPlanResult {
        await CppBridge.Download.shared.plan(request)
    }

    /// Start a native download workflow using canonical generated proto data.
    static func startDownload(_ request: RADownloadStartRequest) async -> RADownloadStartResult {
        await CppBridge.Download.shared.start(request)
    }

    /// Cancel a native download workflow using canonical generated proto data.
    static func cancelDownload(_ request: RADownloadCancelRequest) async -> RADownloadCancelResult {
        await CppBridge.Download.shared.cancel(request)
    }

    /// Resume a native download workflow using canonical generated proto data.
    static func resumeDownload(_ request: RADownloadResumeRequest) async -> RADownloadResumeResult {
        await CppBridge.Download.shared.resume(request)
    }

    /// Poll the latest native download progress as canonical generated proto data.
    static func pollDownloadProgress(_ request: RADownloadSubscribeRequest) async -> RADownloadProgress {
        await CppBridge.Download.shared.pollProgress(request)
    }

    /// Subscribe to native download progress proto events.
    static func downloadProgressEvents() -> AsyncStream<RADownloadProgress> {
        CppBridge.Download.shared.progressEvents()
    }

    /// Get storage information as the canonical generated proto result.
    static func getStorageInfo(_ request: RAStorageInfoRequest = RAStorageInfoRequest()) async -> RAStorageInfoResult {
        await CppBridge.Storage.shared.info(request)
    }

    /// Check storage availability as the canonical generated proto result.
    static func checkStorageAvailability(
        _ request: RAStorageAvailabilityRequest
    ) async -> RAStorageAvailabilityResult {
        await CppBridge.Storage.shared.availability(request)
    }

    /// Build a storage delete plan as canonical generated proto data.
    static func planStorageDelete(_ request: RAStorageDeletePlanRequest) async -> RAStorageDeletePlan {
        await CppBridge.Storage.shared.deletePlan(request)
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
        let reportedPath = progress.localPath.isEmpty ? model.localPath : progress.localPath
        guard !reportedPath.isEmpty else {
            throw SDKException(
                code: .invalidState,
                message: "Download completed without a local_path; cannot import completion into the model registry",
                category: .network
            )
        }

        // For multi-file downloads (VLM primary + mmproj, MiniLM model.onnx +
        // vocab.txt, etc.) the commons download worker reports `local_path` as
        // the last file's destination. Downstream VLM lifecycle resolution
        // walks the path as a directory and fails when it's actually the
        // mmproj file. Normalize to the parent folder so
        // `rac_model_paths_resolve_artifact` can scan all sibling files and
        // discover primary_model, vision_projector, tokenizer, etc.
        let localPath = Self.normalizedCompletionPath(reportedPath, model: model)

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

    /// Collapse a multi-file completion `local_path` to the model folder when
    /// the reported path is actually one of the child files. Mirrors the
    /// commons-side fix in `run_proto_download_worker` so every flow (the
    /// prebuilt xcframework still in circulation + the next rebuild) persists
    /// the correct artifact root in the registry.
    static func normalizedCompletionPath(_ reportedPath: String, model: RAModelInfo) -> String {
        let hasMultipleDescriptors = model.multiFileDescriptors.count > 1
        guard hasMultipleDescriptors else { return reportedPath }

        let reportedURL = URL(fileURLWithPath: reportedPath)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: reportedURL.path,
                                                     isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            return reportedPath
        }
        let parent = reportedURL.deletingLastPathComponent()
        guard !parent.path.isEmpty, parent.path != "/" else { return reportedPath }
        return parent.path
    }

    /// URL → model-format inference via the commons extension-detection helper
    /// (`rac_model_detect_format_from_extension`). Matches the Kotlin
    /// `formatFromUrl(...)` path which delegates to commons as well. Returns
    /// `.unknown` when no known extension is found on the URL path.
    static func detectFormat(fromURL url: String) -> ModelFormat {
        let filename = trailingFilename(fromURL: url)
        let ext = (filename as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return .unknown }

        var cFormat: rac_model_format_t = RAC_MODEL_FORMAT_UNKNOWN
        let detected = ext.withCString { rac_model_detect_format_from_extension($0, &cFormat) }
        guard detected == RAC_TRUE else { return .unknown }
        return ModelFormat(from: cFormat)
    }

    /// Derive a stable model id from a URL by stripping trailing known
    /// extensions. Mirrors Kotlin `generateModelIdFromUrl(...)` so ids agree
    /// across SDKs for URL-registered models.
    static func generateModelId(fromURL url: String) -> String {
        var filename = trailingFilename(fromURL: url)
        let knownExtensions: Set<String> = [
            "gz", "bz2", "tar", "zip", "gguf", "onnx", "ort", "bin",
        ]
        while true {
            let ext = (filename as NSString).pathExtension.lowercased()
            if !ext.isEmpty, knownExtensions.contains(ext) {
                filename = (filename as NSString).deletingPathExtension
            } else {
                break
            }
        }
        return filename
    }

    static func trailingFilename(fromURL url: String) -> String {
        if let parsed = URL(string: url), !parsed.lastPathComponent.isEmpty {
            return parsed.lastPathComponent
        }
        return url.split(separator: "/").last.map(String.init) ?? url
    }
}
