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
    @Published var storedModels: [ModelInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    /// Byte counts, formatted once here rather than at each of the call sites
    /// that used to reach for `ByteCountFormatter` themselves — the storage
    /// screen and the Settings storage pane were free to disagree.
    var formattedModelStorage: String { Self.formatBytes(modelStorageSize) }
    var formattedAvailableSpace: String { Self.formatBytes(availableSpace) }
    var formattedTotalStorage: String { Self.formatBytes(totalStorageSize) }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func loadData() async {
        isLoading = true
        errorMessage = nil

        let state = await RunAnywhere.models.state()
        totalStorageSize = state.storageUsedBytes
        availableSpace = state.storageFreeBytes
        modelStorageSize = state.storageUsedBytes

        do {
            let downloaded = try await RunAnywhere.models.list(
                filter: ModelFilter(downloadedOnly: true)
            )
            // Filter out registry-only / pseudo-model entries that have no on-disk
            // artifact (Apple system models, built-in pseudo-models, etc.).
            storedModels = downloaded.filter { $0.downloadSizeBytes > 0 }
        } catch {
            errorMessage = "Failed to load storage data: \(error.localizedDescription)"
        }

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

    func deleteModel(_ model: ModelInfo) async {
        do {
            try await RunAnywhere.models.delete(id: model.id)
        } catch {
            errorMessage = "Failed to delete model: \(error.localizedDescription)"
            return
        }

        await refreshData()
        // Keep the Models tab in sync (it's a separate singleton with cached
        // rows) so a model deleted here doesn't still show as Installed/Active
        // there and fail to load when tapped.
        await ModelListViewModel.shared.loadModelsFromRegistry()
    }
}
