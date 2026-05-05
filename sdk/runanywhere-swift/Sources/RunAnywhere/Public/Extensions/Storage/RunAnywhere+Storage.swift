//
//  RunAnywhere+Storage.swift
//  RunAnywhere SDK
//
//  Public API for storage and download operations.
//

import Foundation

public extension RunAnywhere {
    /// Download a registered model with the generated download plan/start/progress
    /// contracts. Commons owns planning and registry updates; Swift owns the
    /// native URLSession transfer behind the C++ download adapter.
    @discardableResult
    static func downloadModel(
        _ model: RAModelInfo,
        onProgress: ((RADownloadProgress) async -> Void)? = nil
    ) async throws -> RADownloadProgress {
        guard isInitialized else {
            throw SDKException.download(.notInitialized, "SDK not initialized")
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
            throw SDKException.download(
                .downloadFailed,
                plan.errorMessage.isEmpty ? "Unable to create a download plan" : plan.errorMessage
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
            throw SDKException.download(
                .downloadFailed,
                startResult.errorMessage.isEmpty ? "The download could not be started" : startResult.errorMessage
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
            throw SDKException.general(.notInitialized, "SDK not initialized")
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
            throw SDKException.download(
                .downloadFailed,
                progress.errorMessage.isEmpty ? "Download failed" : progress.errorMessage
            )
        case .cancelled:
            throw SDKException.download(.cancelled, "Download cancelled")
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
            throw SDKException.download(
                .invalidState,
                "Download completed without a local_path; cannot import completion into the model registry"
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
            throw SDKException.download(
                .downloadFailed,
                result.errorMessage.isEmpty
                    ? "Downloaded model could not be imported into the registry"
                    : result.errorMessage
            )
        }

        return progress
    }
}
