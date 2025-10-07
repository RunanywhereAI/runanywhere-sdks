import Foundation

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
