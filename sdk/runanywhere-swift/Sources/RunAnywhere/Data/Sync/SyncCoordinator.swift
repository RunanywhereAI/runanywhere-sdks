//
//  SyncCoordinator.swift
//  RunAnywhere SDK
//
//  Centralized sync coordination for all repositories
//

import Foundation

/// Centralized coordinator for syncing data between local storage and remote API
public actor SyncCoordinator {
    private let logger = SDKLogger(category: "SyncCoordinator")

    // Configuration
    private let batchSize: Int = 100
    private let maxRetries: Int = 3

    // Track sync operations
    private var activeSyncs: Set<String> = []
    private var syncTimer: Task<Void, Never>?

    // MARK: - Initialization

    public init(enableAutoSync: Bool = false) {
        if enableAutoSync {
            Task {
                await startAutoSync()
            }
        }

        // SyncCoordinator initialized
    }

    deinit {
        syncTimer?.cancel()
    }

    // MARK: - Generic Sync Methods

    /// Sync any repository with RepositoryEntity entities
    /// Uses the repository's remote data source to handle the actual sync
    public func sync<R: Repository>(_ repository: R) async throws where R.Entity: RepositoryEntity {
        let typeName = String(describing: R.Entity.self)

        guard !activeSyncs.contains(typeName) else {
            logger.debug("Sync already in progress for \(typeName)")
            return
        }

        // Check if remote data source is available
        guard let remoteDataSource = repository.remoteDataSource else {
            logger.debug("No remote data source available for \(typeName)")
            return
        }

        activeSyncs.insert(typeName)
        defer { activeSyncs.remove(typeName) }

        // Fetch pending items from repository
        let pending = try await repository.fetchPendingSync()
        guard !pending.isEmpty else {
            logger.debug("No pending items to sync for \(typeName)")
            return
        }

        logger.info("Syncing \(pending.count) \(typeName) items")

        var successCount = 0
        var failedIds: [String] = []

        // Process in batches
        for batch in pending.chunked(into: batchSize) {
            do {
                // Use the remote data source to sync
                let syncedIds = try await remoteDataSource.syncBatch(batch)

                // Mark successfully synced items
                if !syncedIds.isEmpty {
                    try await repository.markSynced(syncedIds)
                    successCount += syncedIds.count
                }

                // Track any that didn't sync
                let batchIds = Set(batch.map { $0.id })
                let failedInBatch = batchIds.subtracting(syncedIds)
                failedIds.append(contentsOf: failedInBatch)

            } catch {
                logger.error("Failed to sync batch: \(error)")
                failedIds.append(contentsOf: batch.map { $0.id })
            }
        }

        if successCount > 0 {
            logger.info("Successfully synced \(successCount) \(typeName) items")
        }

        if !failedIds.isEmpty {
            logger.warning("Failed to sync \(failedIds.count) \(typeName) items")
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
    public func isSyncing<T: RepositoryEntity>(type: T.Type) -> Bool {
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
    case syncInProgress

    var errorDescription: String? {
        switch self {
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
