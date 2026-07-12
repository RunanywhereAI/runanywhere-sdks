//
//  StorageViewModel.swift
//  RunAnywhereAI
//
//  Simplified ViewModel that uses SDK storage methods
//

import Foundation
import SwiftUI
import RunAnywhere
import Combine

@MainActor
class StorageViewModel: ObservableObject {
    /// Single owner of storage state + SDK storage calls. The Storage screen
    /// and the Settings storage section both consume this instance.
    static let shared = StorageViewModel()

    @Published var totalStorageSize: Int64 = 0
    @Published var availableSpace: Int64 = 0
    @Published var modelStorageSize: Int64 = 0
    @Published var storedModels: [RAModelStorageMetrics] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    func loadData() async {
        isLoading = true
        errorMessage = nil

        // Use public API to get storage info
        var request = RAStorageInfoRequest()
        request.includeDevice = true
        request.includeApp = true
        request.includeModels = true
        request.includeCache = true

        let storageResult = await RunAnywhere.getStorageInfo(request)
        guard storageResult.success else {
            errorMessage = storageResult.errorMessage.isEmpty
                ? "Failed to load storage data"
                : storageResult.errorMessage
            isLoading = false
            return
        }

        let storageInfo = storageResult.info

        // Update storage sizes from the public API
        totalStorageSize = storageInfo.appStorage.totalBytes
        availableSpace = storageInfo.deviceStorage.freeBytes
        modelStorageSize = storageInfo.totalModelsSize

        // Filter out registry-only / pseudo-model entries that have no on-disk
        // artifact (Apple system models, built-in pseudo-models, etc.).
        storedModels = storageInfo.models.filter { $0.sizeOnDiskBytes > 0 }

        isLoading = false
    }

    func refreshData() async {
        await loadData()
    }

    func clearCache() async {
        do {
            try await RunAnywhere.clearCache()
            await refreshData()
        } catch {
            errorMessage = "Failed to clear cache: \(error.localizedDescription)"
        }
    }

    func cleanTempFiles() async {
        do {
            try await RunAnywhere.cleanTempFiles()
            await refreshData()
        } catch {
            errorMessage = "Failed to clean temporary files: \(error.localizedDescription)"
        }
    }

    func deleteModel(_ model: RAModelStorageMetrics) async {
        let result = await RunAnywhere.deleteModel(model.modelID)
        guard result.success else {
            errorMessage = result.errorMessage.isEmpty
                ? "Failed to delete model"
                : result.errorMessage
            return
        }

        await refreshData()
    }
}
