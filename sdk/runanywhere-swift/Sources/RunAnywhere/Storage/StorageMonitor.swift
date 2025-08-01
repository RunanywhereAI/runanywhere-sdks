//
//  StorageMonitor.swift
//  RunAnywhere SDK
//
//  Storage monitoring infrastructure for on-device AI
//

import Foundation
import os.log

/// Storage monitoring service for tracking model storage and device capacity
public class StorageMonitor {
    public static let shared = StorageMonitor()

    // MARK: - Properties

    /// Current storage information
    public private(set) var storageInfo: StorageInfo?

    /// Whether monitoring is active
    public private(set) var isMonitoring = false

    // MARK: - Private Properties

    private let logger = os.Logger(subsystem: "com.runanywhere.sdk", category: "StorageMonitor")
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.storagemonitor", qos: .utility)
    private var monitoringTimer: Timer?
    private let updateInterval: TimeInterval = 60.0 // Update every minute

    // Storage thresholds
    private let warningThreshold: Double = 0.90 // 90% full
    private let criticalThreshold: Double = 0.95 // 95% full

    // Callbacks
    private var storageCallbacks: [(StorageInfo) -> Void] = []
    private var alertCallbacks: [(StorageAlert) -> Void] = []

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Start storage monitoring
    public func startMonitoring() {
        queue.async { [weak self] in
            guard let self = self, !self.isMonitoring else { return }

            self.isMonitoring = true
            self.logger.info("Started storage monitoring")

            // Initial update
            Task {
                await self.updateStorageInfo()
            }

            // Start periodic updates
            DispatchQueue.main.async {
                self.monitoringTimer = Timer.scheduledTimer(withTimeInterval: self.updateInterval, repeats: true) { _ in
                    Task {
                        await self.updateStorageInfo()
                    }
                }
            }
        }
    }

    /// Stop storage monitoring
    public func stopMonitoring() {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.isMonitoring = false
            DispatchQueue.main.async {
                self.monitoringTimer?.invalidate()
                self.monitoringTimer = nil
            }
            self.logger.info("Stopped storage monitoring")
        }
    }

    /// Refresh storage information immediately
    public func refreshStorageInfo() async -> StorageInfo {
        await updateStorageInfo()
        return storageInfo ?? StorageInfo.empty
    }

    /// Get storage usage for models
    public func getModelStorageUsage() async -> ModelStorageInfo {
        let modelsDirectory = getModelsDirectory()
        let modelFiles = await scanForModels(in: modelsDirectory)

        var totalSize: Int64 = 0
        var modelsByFramework: [LLMFramework: [StoredModel]] = [:]

        for model in modelFiles {
            totalSize += model.size

            if let framework = model.framework {
                if modelsByFramework[framework] == nil {
                    modelsByFramework[framework] = []
                }
                modelsByFramework[framework]?.append(model)
            }
        }

        return ModelStorageInfo(
            totalSize: totalSize,
            modelCount: modelFiles.count,
            modelsByFramework: modelsByFramework,
            largestModel: modelFiles.max { $0.size < $1.size }
        )
    }

    /// Check if there's enough storage for a model
    public func checkStorageAvailable(for modelSize: Int64, safetyMargin: Double = 1.2) -> StorageAvailability {
        let requiredSpace = Int64(Double(modelSize) * safetyMargin)
        let deviceInfo = getDeviceStorageInfo()

        let available = deviceInfo.freeSpace > requiredSpace
        let warning = Double(deviceInfo.usedSpace + requiredSpace) / Double(deviceInfo.totalSpace) > warningThreshold

        return StorageAvailability(
            isAvailable: available,
            requiredSpace: requiredSpace,
            availableSpace: deviceInfo.freeSpace,
            hasWarning: warning,
            recommendation: available ? nil : "Free up at least \(ByteCountFormatter.string(fromByteCount: requiredSpace - deviceInfo.freeSpace, countStyle: .memory))"
        )
    }

    /// Clean up cache and temporary files
    public func cleanupCache() async throws -> CleanupResult {
        let startSize = await calculateCacheSize()

        // Clean various cache locations
        let cacheURLs = getCacheDirectories()
        var cleanedSize: Int64 = 0
        var errors: [Error] = []

        for cacheURL in cacheURLs {
            do {
                let cleaned = try await cleanDirectory(at: cacheURL)
                cleanedSize += cleaned
            } catch {
                errors.append(error)
                logger.error("Failed to clean cache at \(cacheURL.path): \(error)")
            }
        }

        let endSize = await calculateCacheSize()

        return CleanupResult(
            startSize: startSize,
            endSize: endSize,
            freedSpace: cleanedSize,
            errors: errors
        )
    }

    /// Delete a specific model
    public func deleteModel(at path: URL) async throws -> Int64 {
        let size = try await calculateSize(at: path)

        try FileManager.default.removeItem(at: path)
        logger.info("Deleted model at \(path.path), freed \(ByteCountFormatter.string(fromByteCount: size, countStyle: .memory))")

        // Update storage info
        await updateStorageInfo()

        return size
    }

    /// Add storage update callback
    public func addStorageCallback(_ callback: @escaping (StorageInfo) -> Void) {
        queue.async { [weak self] in
            self?.storageCallbacks.append(callback)
        }
    }

    /// Add alert callback
    public func addAlertCallback(_ callback: @escaping (StorageAlert) -> Void) {
        queue.async { [weak self] in
            self?.alertCallbacks.append(callback)
        }
    }

    /// Get storage recommendations
    public func getRecommendations() -> [StorageRecommendation] {
        guard let info = storageInfo else { return [] }

        var recommendations: [StorageRecommendation] = []

        // Check device storage
        let deviceUsageRatio = Double(info.deviceStorage.usedSpace) / Double(info.deviceStorage.totalSpace)

        if deviceUsageRatio > criticalThreshold {
            recommendations.append(
                StorageRecommendation(
                    type: .critical,
                    message: "Device storage critically low",
                    action: "Delete unused apps or media to free space"
                )
            )
        } else if deviceUsageRatio > warningThreshold {
            recommendations.append(
                StorageRecommendation(
                    type: .warning,
                    message: "Device storage running low",
                    action: "Consider freeing up space"
                )
            )
        }

        // Check cache size
        if info.cacheSize > 1_000_000_000 { // 1GB
            recommendations.append(
                StorageRecommendation(
                    type: .suggestion,
                    message: "Large cache size detected",
                    action: "Run cache cleanup to free \(ByteCountFormatter.string(fromByteCount: info.cacheSize, countStyle: .memory))"
                )
            )
        }

        // Check for old models
        let oldModels = info.storedModels.filter { model in
            guard let lastUsed = model.lastUsed else { return false }
            return Date().timeIntervalSince(lastUsed) > 30 * 24 * 60 * 60 // 30 days
        }

        if !oldModels.isEmpty {
            let totalSize = oldModels.reduce(0) { $0 + $1.size }
            recommendations.append(
                StorageRecommendation(
                    type: .suggestion,
                    message: "\(oldModels.count) models unused for 30+ days",
                    action: "Delete to free \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .memory))"
                )
            )
        }

        return recommendations
    }

    // MARK: - Private Methods

    @discardableResult
    private func updateStorageInfo() async -> StorageInfo {
        do {
            let appStorage = try await calculateAppStorageUsage()
            let deviceStorage = getDeviceStorageInfo()
            let modelStorage = await getModelStorageUsage()
            let cacheSize = await calculateCacheSize()
            let storedModels = await scanForModels(in: getModelsDirectory())

            let info = StorageInfo(
                appStorage: appStorage,
                deviceStorage: deviceStorage,
                modelStorage: modelStorage,
                cacheSize: cacheSize,
                storedModels: storedModels,
                lastUpdated: Date()
            )

            queue.sync {
                self.storageInfo = info
            }

            // Check for alerts
            checkStorageAlerts(info: info)

            // Notify callbacks
            for callback in storageCallbacks {
                callback(info)
            }

            return info
        } catch {
            logger.error("Failed to update storage info: \(error)")
            return StorageInfo.empty
        }
    }

    private func calculateAppStorageUsage() async throws -> AppStorageInfo {
        let fileManager = FileManager.default

        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        let documentsSize = try await calculateSize(at: documentsURL)
        let cacheSize = try await calculateSize(at: cacheURL)
        let appSupportSize = try await calculateSize(at: appSupportURL)

        return AppStorageInfo(
            documentsSize: documentsSize,
            cacheSize: cacheSize,
            appSupportSize: appSupportSize,
            totalSize: documentsSize + cacheSize + appSupportSize
        )
    }

    private func calculateSize(at url: URL) async throws -> Int64 {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return 0 }

        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if resourceValues.isDirectory == false {
                    totalSize += Int64(resourceValues.fileSize ?? 0)
                }
            }
        }

        return totalSize
    }

    private func getDeviceStorageInfo() -> DeviceStorageInfo {
        let fileManager = FileManager.default

        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            let totalSpace = systemAttributes[.systemSize] as? Int64 ?? 0
            let freeSpace = systemAttributes[.systemFreeSize] as? Int64 ?? 0

            return DeviceStorageInfo(
                totalSpace: totalSpace,
                freeSpace: freeSpace,
                usedSpace: totalSpace - freeSpace
            )
        } catch {
            logger.error("Failed to get device storage info: \(error)")
            return DeviceStorageInfo(totalSpace: 0, freeSpace: 0, usedSpace: 0)
        }
    }

    private func scanForModels(in directory: URL) async -> [StoredModel] {
        let fileManager = FileManager.default
        var models: [StoredModel] = []

        guard fileManager.fileExists(atPath: directory.path) else { return models }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey]
            )

            for url in contents {
                // Check if it's a model file based on extension
                guard let format = ModelFormat(rawValue: url.pathExtension) else { continue }

                let resourceValues = try url.resourceValues(
                    forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey]
                )

                let model = StoredModel(
                    name: url.deletingPathExtension().lastPathComponent,
                    path: url,
                    size: Int64(resourceValues.fileSize ?? 0),
                    format: format,
                    framework: extractFramework(from: url),
                    createdDate: resourceValues.creationDate ?? Date(),
                    lastUsed: resourceValues.contentModificationDate
                )

                models.append(model)
            }
        } catch {
            logger.error("Failed to scan for models: \(error)")
        }

        return models
    }

    private func extractFramework(from url: URL) -> LLMFramework? {
        // Try to extract framework from directory structure or filename
        let pathComponents = url.pathComponents

        for component in pathComponents {
            if let framework = LLMFramework(rawValue: component) {
                return framework
            }
        }

        // Try format-based inference
        switch ModelFormat(rawValue: url.pathExtension) {
        case .mlmodel, .mlpackage:
            return .coreML
        case .tflite:
            return .tensorFlowLite
        case .gguf, .ggml:
            return .llamaCpp
        case .onnx, .ort:
            return .onnx
        case .pte:
            return .execuTorch
        default:
            return nil
        }
    }

    private func getModelsDirectory() -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Models")
    }

    private func getCacheDirectories() -> [URL] {
        let fileManager = FileManager.default
        var directories: [URL] = []

        if let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            directories.append(cacheURL)
        }

        let tempURL = fileManager.temporaryDirectory
        directories.append(tempURL)

        return directories
    }

    private func calculateCacheSize() async -> Int64 {
        var totalSize: Int64 = 0

        for cacheURL in getCacheDirectories() {
            do {
                let size = try await calculateSize(at: cacheURL)
                totalSize += size
            } catch {
                logger.error("Failed to calculate cache size at \(cacheURL.path): \(error)")
            }
        }

        return totalSize
    }

    private func cleanDirectory(at url: URL) async throws -> Int64 {
        let fileManager = FileManager.default
        var freedSpace: Int64 = 0

        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey]
        )

        for fileURL in contents {
            do {
                let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                try fileManager.removeItem(at: fileURL)
                freedSpace += Int64(size)
            } catch {
                // Continue with other files
                logger.warning("Failed to delete cache file at \(fileURL.path): \(error)")
            }
        }

        return freedSpace
    }

    private func checkStorageAlerts(info: StorageInfo) {
        let deviceUsageRatio = Double(info.deviceStorage.usedSpace) / Double(info.deviceStorage.totalSpace)

        if deviceUsageRatio > criticalThreshold {
            createAlert(
                type: .critical,
                message: "Device storage critical: \(Int(deviceUsageRatio * 100))% full"
            )
        } else if deviceUsageRatio > warningThreshold {
            createAlert(
                type: .warning,
                message: "Device storage warning: \(Int(deviceUsageRatio * 100))% full"
            )
        }

        // Check if models take up too much space
        let modelsRatio = Double(info.modelStorage.totalSize) / Double(info.deviceStorage.totalSpace)
        if modelsRatio > 0.2 { // Models using >20% of device storage
            createAlert(
                type: .info,
                message: "Models using \(Int(modelsRatio * 100))% of device storage"
            )
        }
    }

    private func createAlert(type: StorageAlertType, message: String) {
        let alert = StorageAlert(
            type: type,
            message: message,
            timestamp: Date()
        )

        for callback in alertCallbacks {
            callback(alert)
        }

        switch type {
        case .info:
            logger.info("Storage alert: \(message)")
        case .warning:
            logger.warning("Storage warning: \(message)")
        case .critical:
            logger.error("Storage critical: \(message)")
        }
    }
}

// MARK: - Supporting Types

/// Storage information
public struct StorageInfo {
    public let appStorage: AppStorageInfo
    public let deviceStorage: DeviceStorageInfo
    public let modelStorage: ModelStorageInfo
    public let cacheSize: Int64
    public let storedModels: [StoredModel]
    public let lastUpdated: Date

    /// Empty storage info for initialization
    public static let empty = StorageInfo(
        appStorage: AppStorageInfo(documentsSize: 0, cacheSize: 0, appSupportSize: 0, totalSize: 0),
        deviceStorage: DeviceStorageInfo(totalSpace: 0, freeSpace: 0, usedSpace: 0),
        modelStorage: ModelStorageInfo(totalSize: 0, modelCount: 0, modelsByFramework: [:], largestModel: nil),
        cacheSize: 0,
        storedModels: [],
        lastUpdated: Date()
    )
}

/// App storage breakdown
public struct AppStorageInfo {
    public let documentsSize: Int64
    public let cacheSize: Int64
    public let appSupportSize: Int64
    public let totalSize: Int64
}

/// Device storage information
public struct DeviceStorageInfo {
    public let totalSpace: Int64
    public let freeSpace: Int64
    public let usedSpace: Int64

    public var usagePercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace) * 100
    }
}

/// Model storage information
public struct ModelStorageInfo {
    public let totalSize: Int64
    public let modelCount: Int
    public let modelsByFramework: [LLMFramework: [StoredModel]]
    public let largestModel: StoredModel?
}

/// Stored model information
public struct StoredModel {
    public let name: String
    public let path: URL
    public let size: Int64
    public let format: ModelFormat
    public let framework: LLMFramework?
    public let createdDate: Date
    public let lastUsed: Date?
}

/// Storage availability check result
public struct StorageAvailability {
    public let isAvailable: Bool
    public let requiredSpace: Int64
    public let availableSpace: Int64
    public let hasWarning: Bool
    public let recommendation: String?
}

/// Cleanup result
public struct CleanupResult {
    public let startSize: Int64
    public let endSize: Int64
    public let freedSpace: Int64
    public let errors: [Error]
}

/// Storage recommendation
public struct StorageRecommendation {
    public let type: RecommendationType
    public let message: String
    public let action: String

    public enum RecommendationType {
        case critical
        case warning
        case suggestion
    }
}

/// Storage alert
public struct StorageAlert {
    public let type: StorageAlertType
    public let message: String
    public let timestamp: Date
}

/// Storage alert type
public enum StorageAlertType {
    case info
    case warning
    case critical
}
