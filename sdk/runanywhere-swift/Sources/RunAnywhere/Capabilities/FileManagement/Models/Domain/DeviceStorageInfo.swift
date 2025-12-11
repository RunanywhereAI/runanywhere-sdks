import Foundation

/// Device storage information
public struct DeviceStorageInfo: Sendable {
    public let totalSpace: Int64
    public let freeSpace: Int64
    public let usedSpace: Int64

    public var usagePercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace) * 100
    }

    public init(totalSpace: Int64, freeSpace: Int64, usedSpace: Int64) {
        self.totalSpace = totalSpace
        self.freeSpace = freeSpace
        self.usedSpace = usedSpace
    }
}
