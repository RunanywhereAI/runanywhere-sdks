import Foundation
import GRDB
import Combine

/// Observes configuration changes in the database
public final class ConfigurationObserver {
    private let database: DatabaseManager
    private var cancellables = Set<AnyCancellable>()

    /// Publisher for configuration changes
    public let configurationPublisher = PassthroughSubject<ConfigurationData, Never>()

    /// Publisher for routing policy changes
    public let routingPolicyPublisher = PassthroughSubject<RoutingPolicy, Never>()

    /// Publisher for analytics configuration changes
    public let analyticsConfigPublisher = PassthroughSubject<AnalyticsConfiguration, Never>()

    /// Publisher for storage configuration changes
    public let storageConfigPublisher = PassthroughSubject<StorageConfiguration, Never>()

    private var observation: DatabaseCancellable?

    public init(database: DatabaseManager) {
        self.database = database
    }

    /// Start observing configuration changes
    public func startObserving() {
        guard observation == nil else { return }

        let observation = ValueObservation
            .tracking { db in
                try ConfigurationRecord
                    .filter(ConfigurationRecord.Columns.id == SDKConstants.ConfigurationDefaults.configurationId)
                    .fetchOne(db)
            }
            .removeDuplicates()

        self.observation = observation.start(
            in: database.dbQueue,
            scheduling: .async(onQueue: .main),
            onError: { error in
                print("Configuration observation error: \(error)")
            },
            onChange: { [weak self] record in
                self?.handleConfigurationChange(record)
            }
        )

        // Also observe related tables
        observeRoutingPolicies()
        observeAnalyticsConfig()
        observeStorageConfig()
    }

    /// Stop observing configuration changes
    public func stopObserving() {
        observation?.cancel()
        observation = nil
        cancellables.removeAll()
    }

    private func handleConfigurationChange(_ record: ConfigurationRecord?) {
        guard let record = record else { return }

        Task {
            do {
                let entity = try await database.fetchConfiguration(id: record.id)
                if let config = entity {
                    await MainActor.run {
                        configurationPublisher.send(config)
                    }
                }
            } catch {
                print("Error converting configuration record: \(error)")
            }
        }
    }

    private func observeRoutingPolicies() {
        let observation = ValueObservation
            .tracking { db in
                try RoutingPolicyRecord
                    .filter(RoutingPolicyRecord.Columns.configurationId == SDKConstants.ConfigurationDefaults.configurationId)
                    .fetchOne(db)
            }
            .removeDuplicates()

        observation.start(
            in: database.dbQueue,
            scheduling: .async(onQueue: .main),
            onError: { error in
                print("Routing policy observation error: \(error)")
            },
            onChange: { [weak self] record in
                guard let record = record else { return }

                Task {
                    let policy = await self?.mapRoutingPolicy(from: record)
                    if let policy = policy {
                        await MainActor.run {
                            self?.routingPolicyPublisher.send(policy)
                        }
                    }
                }
            }
        )
        .store(in: &cancellables)
    }

    private func observeAnalyticsConfig() {
        let observation = ValueObservation
            .tracking { db in
                try AnalyticsConfigRecord
                    .filter(AnalyticsConfigRecord.Columns.configurationId == SDKConstants.ConfigurationDefaults.configurationId)
                    .fetchOne(db)
            }
            .removeDuplicates()

        observation.start(
            in: database.dbQueue,
            scheduling: .async(onQueue: .main),
            onError: { error in
                print("Analytics config observation error: \(error)")
            },
            onChange: { [weak self] record in
                guard let record = record else { return }

                Task {
                    let config = await self?.mapAnalyticsConfig(from: record)
                    if let config = config {
                        await MainActor.run {
                            self?.analyticsConfigPublisher.send(config)
                        }
                    }
                }
            }
        )
        .store(in: &cancellables)
    }

    private func observeStorageConfig() {
        let observation = ValueObservation
            .tracking { db in
                try StorageConfigRecord
                    .filter(StorageConfigRecord.Columns.configurationId == SDKConstants.ConfigurationDefaults.configurationId)
                    .fetchOne(db)
            }
            .removeDuplicates()

        observation.start(
            in: database.dbQueue,
            scheduling: .async(onQueue: .main),
            onError: { error in
                print("Storage config observation error: \(error)")
            },
            onChange: { [weak self] record in
                guard let record = record else { return }

                Task {
                    let config = await self?.mapStorageConfig(from: record)
                    if let config = config {
                        await MainActor.run {
                            self?.storageConfigPublisher.send(config)
                        }
                    }
                }
            }
        )
        .store(in: &cancellables)
    }

    // MARK: - Mapping Functions

    private func mapRoutingPolicy(from record: RoutingPolicyRecord) async -> RoutingPolicy {
        let policyType: RoutingPolicy
        switch record.policyType {
        case "costOptimized":
            policyType = .costOptimized
        case "latencyOptimized":
            policyType = .latencyOptimized
        case "privacyFirst":
            policyType = .privacyFirst
        case "balanced":
            policyType = .balanced
        default:
            policyType = .deviceOnly
        }
        return policyType
    }

    private func mapAnalyticsConfig(from record: AnalyticsConfigRecord) async -> AnalyticsConfiguration {
        let level: AnalyticsLevel
        switch record.analyticsLevel {
        case SDKConstants.AnalyticsDefaults.levelBasic:
            level = .basic
        case SDKConstants.AnalyticsDefaults.levelDetailed:
            level = .detailed
        case SDKConstants.AnalyticsDefaults.levelDebug:
            level = .verbose
        default:
            level = .basic
        }

        return AnalyticsConfiguration(
            enabled: record.metricsEnabled,
            level: level,
            enablePerformanceMetrics: record.performanceTrackingEnabled,
            enableErrorReporting: record.errorReportingEnabled
        )
    }

    private func mapStorageConfig(from record: StorageConfigRecord) async -> StorageConfiguration {
        return StorageConfiguration(
            maxCacheSizeMB: record.maxCacheSizeMB,
            autoCleanupEnabled: record.autoCleanupEnabled,
            cleanupThresholdPercentage: record.cleanupThresholdPercentage,
            modelRetentionDays: record.modelRetentionDays
        )
    }
}

// MARK: - Storage Configuration

public struct StorageConfiguration {
    public let maxCacheSizeMB: Int
    public let autoCleanupEnabled: Bool
    public let cleanupThresholdPercentage: Int
    public let modelRetentionDays: Int
}

// MARK: - Analytics Configuration

public struct AnalyticsConfiguration {
    public let enabled: Bool
    public let level: AnalyticsLevel
    public let enablePerformanceMetrics: Bool
    public let enableErrorReporting: Bool
}

// MARK: - Cancellable Storage

extension DatabaseCancellable {
    func store(in set: inout Set<AnyCancellable>) {
        AnyCancellable { self.cancel() }.store(in: &set)
    }
}
