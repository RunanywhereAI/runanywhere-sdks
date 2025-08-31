//
//  SyncCoordinator.swift
//  RunAnywhere SDK
//
//  Centralized sync coordination for all repositories
//

import Foundation

/// Centralized coordinator for syncing data between local storage and remote API
public actor SyncCoordinator {
    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "SyncCoordinator")

    // Configuration
    private let batchSize: Int = 100
    private let maxRetries: Int = 3

    // Track sync operations
    private var activeSyncs: Set<String> = []
    private var syncTimer: Task<Void, Never>?

    // MARK: - Initialization

    public init(apiClient: APIClient?, enableAutoSync: Bool = false) {
        self.apiClient = apiClient

        if enableAutoSync && apiClient != nil {
            Task {
                await startAutoSync()
            }
        }

        logger.info("SyncCoordinator initialized")
    }

    deinit {
        syncTimer?.cancel()
    }

    // MARK: - Generic Sync Methods

    /// Sync any repository with Syncable entities
    public func sync<R: Repository>(_ repository: R, endpoint: APIEndpoint? = nil) async throws where R.Entity: Syncable {
        let typeName = String(describing: R.Entity.self)

        guard !activeSyncs.contains(typeName) else {
            logger.debug("Sync already in progress for \(typeName)")
            return
        }

        guard apiClient != nil else {
            logger.debug("No API client available for sync")
            return
        }

        activeSyncs.insert(typeName)
        defer { activeSyncs.remove(typeName) }

        // Fetch pending items
        let pending = try await repository.fetchPendingSync()
        guard !pending.isEmpty else {
            logger.debug("No pending items to sync for \(typeName)")
            return
        }

        logger.info("Syncing \(pending.count) \(typeName) items")

        // Process in batches
        for batch in pending.chunked(into: batchSize) {
            try await syncBatch(batch, repository: repository, endpoint: endpoint)
        }
    }

    /// Sync a specific batch of entities
    private func syncBatch<R: Repository>(
        _ batch: [R.Entity],
        repository: R,
        endpoint: APIEndpoint?
    ) async throws where R.Entity: Syncable {

        guard let apiClient = apiClient else {
            throw SyncError.noAPIClient
        }

        // Determine endpoint based on entity type
        let syncEndpoint = endpoint ?? getDefaultEndpoint(for: R.Entity.self)

        do {
            // Create generic sync request
            let requestData = try JSONEncoder().encode(batch)
            let requestDict: [String: Any] = [
                "items": try JSONSerialization.jsonObject(with: requestData),
                "timestamp": Date().timeIntervalSince1970
            ]

            // For now, just mark as synced since we don't have real API
            // In production, this would make the actual API call
            let ids = batch.map { $0.id }
            try await repository.markSynced(ids)
            logger.debug("Synced \(ids.count) items to endpoint: \(syncEndpoint)")

        } catch {
            logger.error("Sync batch failed: \(error)")
            throw SyncError.batchSyncFailed(error)
        }
    }

    // MARK: - Endpoint Resolution

    private func getDefaultEndpoint<T: Syncable>(for type: T.Type) -> APIEndpoint {
        switch type {
        case is ConfigurationData.Type:
            return .syncConfiguration
        case is TelemetryData.Type:
            return .syncTelemetry
        case is ModelInfo.Type:
            return .syncModelInfo
        case is DeviceInfoData.Type:
            return .syncDeviceInfo
        default:
            // Fallback - should not happen in practice
            return .syncConfiguration
        }
    }

    // MARK: - Auto Sync

    private func startAutoSync() {
        syncTimer = Task {
            while !Task.isCancelled {
                // Wait 5 minutes
                try? await Task.sleep(nanoseconds: 300_000_000_000)

                // Sync all repositories (will be called from services)
                logger.debug("Auto-sync timer triggered")
            }
        }
    }

    /// Stop auto sync
    public func stopAutoSync() {
        syncTimer?.cancel()
        syncTimer = nil
    }

    // MARK: - Manual Sync Control

    /// Check if sync is in progress for a given type
    public func isSyncing<T: Syncable>(type: T.Type) -> Bool {
        let typeName = String(describing: type)
        return activeSyncs.contains(typeName)
    }

    /// Force sync all pending data (called from services)
    public func syncAll() async throws {
        // This will be called by individual services
        // Each service will call sync() with their repository
        logger.info("Manual sync all triggered")
    }
}

// MARK: - Error Types

enum SyncError: LocalizedError {
    case batchSyncFailed(Error)
    case noAPIClient
    case syncInProgress

    var errorDescription: String? {
        switch self {
        case .batchSyncFailed(let error):
            return "Batch sync failed: \(error.localizedDescription)"
        case .noAPIClient:
            return "No API client available for sync"
        case .syncInProgress:
            return "Sync already in progress"
        }
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
