import Foundation

/// Simple sync manager that handles syncing entities to network
public actor SyncManager {
    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "SyncManager")
    private var syncTimer: Timer?
    private var isSyncing = false

    /// Queue of pending sync operations
    private var pendingSyncQueue: Set<String> = []

    public init(apiClient: APIClient?) {
        self.apiClient = apiClient
        Task {
            await setupAppLifecycleObservers()
        }
    }

    deinit {
        syncTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Queue an entity for sync
    public func queueForSync(entityId: String) {
        pendingSyncQueue.insert(entityId)

        // Trigger immediate sync in background
        Task {
            try? await performSync()
        }
    }

    /// Perform sync for all pending entities
    public func performSync() async throws {
        guard !isSyncing else {
            logger.debug("Sync already in progress")
            return
        }

        guard apiClient != nil else {
            logger.debug("No API client available for sync")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        let entitiesToSync = pendingSyncQueue
        pendingSyncQueue.removeAll()

        if !entitiesToSync.isEmpty {
            logger.info("Syncing \(entitiesToSync.count) entities")
            // Actual sync implementation would go here
            // For now, just log
        }
    }

    /// Force sync all pending changes
    public func syncAll() async throws {
        try await performSync()
    }

    // MARK: - Private Methods

    private func setupAppLifecycleObservers() {
        // Listen for app termination
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                try? await self.syncAll()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                try? await self.syncAll()
            }
        }
        #elseif os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                try? await self.syncAll()
            }
        }
        #endif
    }
}

// MARK: - UIKit/AppKit imports for lifecycle notifications
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
