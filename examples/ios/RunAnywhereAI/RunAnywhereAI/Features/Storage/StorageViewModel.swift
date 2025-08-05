//
//  StorageViewModel.swift
//  RunAnywhereAI
//
//  Simplified ViewModel that uses SDK storage methods
//

import Foundation
import SwiftUI
import RunAnywhereSDK

@MainActor
class StorageViewModel: ObservableObject {
    @Published var totalStorageSize: Int64 = 0
    @Published var availableSpace: Int64 = 0
    @Published var modelStorageSize: Int64 = 0
    @Published var storedModels: [StoredModel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sdk = RunAnywhereSDK.shared

    func loadData() async {
        isLoading = true
        errorMessage = nil

        // Use public API to get storage info
        let storageInfo = await sdk.getStorageInfo()

        // Update storage sizes from the public API
        totalStorageSize = storageInfo.appStorage.totalSize
        availableSpace = storageInfo.deviceStorage.freeSpace
        modelStorageSize = storageInfo.modelStorage.totalSize

        // Use StoredModel directly from SDK
        storedModels = storageInfo.storedModels

        isLoading = false
    }

    func refreshData() async {
        await loadData()
    }

    func clearCache() async {
        do {
            try await sdk.clearCache()
            await refreshData()
        } catch {
            errorMessage = "Failed to clear cache: \(error.localizedDescription)"
        }
    }

    func cleanTempFiles() async {
        do {
            try await sdk.cleanTempFiles()
            await refreshData()
        } catch {
            errorMessage = "Failed to clean temporary files: \(error.localizedDescription)"
        }
    }

    func deleteModel(_ modelId: String) async {
        do {
            try await sdk.deleteStoredModel(modelId)
            await refreshData()
        } catch {
            errorMessage = "Failed to delete model: \(error.localizedDescription)"
        }
    }

}
