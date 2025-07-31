//
//  StorageMonitorService.swift
//  RunAnywhereAI
//
//  Service for monitoring app storage usage
//

import Foundation

@MainActor
class StorageMonitorService: ObservableObject {
    static let shared = StorageMonitorService()

    @Published var storageInfo: StorageInfo?

    private init() {}

    func refreshStorageInfo() async {
        do {
            let info = try await calculateStorageUsage()
            self.storageInfo = info
        } catch {
            print("Failed to calculate storage usage: \(error)")
            // Provide a fallback with minimal info
            let fileManager = FileManager.default
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

            self.storageInfo = StorageInfo(
                totalAppSize: 0,
                documentsSize: 0,
                cacheSize: 0,
                appSupportSize: 0,
                modelsSize: 0,
                downloadedModels: [],
                totalDeviceStorage: (try? deviceStorageCapacity()) ?? 0,
                freeDeviceStorage: (try? deviceFreeStorage()) ?? 0
            )
        }
    }

    private func calculateStorageUsage() async throws -> StorageInfo {
        let fileManager = FileManager.default

        // Get app directories
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        // Calculate sizes with simpler approach
        let documentsSize = quickDirectorySize(at: documentsURL)
        let cacheSize = quickDirectorySize(at: cacheURL)
        let appSupportSize = quickDirectorySize(at: appSupportURL)
        let totalAppSize = documentsSize + cacheSize + appSupportSize

        // Get models directory specifically
        let modelsURL = documentsURL.appendingPathComponent("Models")
        let modelsSize = quickDirectorySize(at: modelsURL)

        // Get downloaded models info (simplified)
        let downloadedModels = getDownloadedModelsSimple(at: modelsURL)

        // Get device storage info
        let totalDeviceStorage = try deviceStorageCapacity()
        let freeDeviceStorage = try deviceFreeStorage()

        return StorageInfo(
            totalAppSize: totalAppSize,
            documentsSize: documentsSize,
            cacheSize: cacheSize,
            appSupportSize: appSupportSize,
            modelsSize: modelsSize,
            downloadedModels: downloadedModels,
            totalDeviceStorage: totalDeviceStorage,
            freeDeviceStorage: freeDeviceStorage
        )
    }

    private func quickDirectorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        guard fileManager.fileExists(atPath: url.path) else { return 0 }

        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])

            for fileURL in contents {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])

                if resourceValues.isDirectory == true {
                    // For directories, recursively calculate size (but limit depth to avoid hanging)
                    totalSize += quickDirectorySize(at: fileURL)
                } else {
                    // For files, add the size
                    totalSize += Int64(resourceValues.fileSize ?? 0)
                }
            }
        } catch {
            print("Error calculating directory size for \(url.path): \(error)")
            return 0
        }

        return totalSize
    }

    private func getDownloadedModelsSimple(at modelsURL: URL) -> [DownloadedModelInfo] {
        let fileManager = FileManager.default
        var models: [DownloadedModelInfo] = []

        guard fileManager.fileExists(atPath: modelsURL.path) else { return models }

        do {
            let frameworkDirectories = try fileManager.contentsOfDirectory(at: modelsURL, includingPropertiesForKeys: [.isDirectoryKey])

            for frameworkURL in frameworkDirectories {
                let resourceValues = try frameworkURL.resourceValues(forKeys: [.isDirectoryKey])
                guard resourceValues.isDirectory == true else { continue }

                let frameworkName = frameworkURL.lastPathComponent

                do {
                    let modelFiles = try fileManager.contentsOfDirectory(at: frameworkURL, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .isDirectoryKey])

                    for modelFile in modelFiles {
                        let resourceValues = try modelFile.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .isDirectoryKey])

                        // Use ModelFormatManager to determine if this should be included
                        let isDirectory = resourceValues.isDirectory ?? false
                        let format = ModelFormat.from(extension: modelFile.pathExtension)
                        let formatManager = ModelFormatManager.shared
                        let handler = formatManager.getHandler(for: modelFile, format: format)

                        // Skip if it's a directory that's not a model format
                        if isDirectory && !handler.isDirectoryBasedModel(url: modelFile) {
                            continue
                        }

                        // Calculate size using the appropriate handler
                        let fileSize = handler.calculateModelSize(at: modelFile)

                        let creationDate = resourceValues.creationDate ?? Date()

                        let modelInfo = DownloadedModelInfo(
                            name: modelFile.lastPathComponent,
                            framework: frameworkName,
                            size: fileSize,
                            downloadDate: creationDate,
                            path: modelFile.path
                        )
                        models.append(modelInfo)
                    }
                } catch {
                    print("Error reading framework directory \(frameworkName): \(error)")
                    continue
                }
            }
        } catch {
            print("Error reading models directory: \(error)")
        }

        return models.sorted { $0.downloadDate > $1.downloadDate }
    }

    private func deviceStorageCapacity() throws -> Int64 {
        let fileManager = FileManager.default
        let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
        return systemAttributes[.systemSize] as? Int64 ?? 0
    }

    private func deviceFreeStorage() throws -> Int64 {
        let fileManager = FileManager.default
        let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
        return systemAttributes[.systemFreeSize] as? Int64 ?? 0
    }
}

struct StorageInfo {
    let totalAppSize: Int64
    let documentsSize: Int64
    let cacheSize: Int64
    let appSupportSize: Int64
    let modelsSize: Int64
    let downloadedModels: [DownloadedModelInfo]
    let totalDeviceStorage: Int64
    let freeDeviceStorage: Int64

    var usedDeviceStorage: Int64 {
        totalDeviceStorage - freeDeviceStorage
    }

    var appPercentageOfDevice: Double {
        guard totalDeviceStorage > 0 else { return 0 }
        return Double(totalAppSize) / Double(totalDeviceStorage) * 100
    }

    var modelsPercentageOfApp: Double {
        guard totalAppSize > 0 else { return 0 }
        return Double(modelsSize) / Double(totalAppSize) * 100
    }
}

struct DownloadedModelInfo {
    let name: String
    let framework: String
    let size: Int64
    let downloadDate: Date
    let path: String

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: downloadDate)
    }
}

extension Int64 {
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
