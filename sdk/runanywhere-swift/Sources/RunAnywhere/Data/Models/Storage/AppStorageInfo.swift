import Foundation

/// App storage breakdown
public struct AppStorageInfo: Sendable {
    public let documentsSize: Int64
    public let cacheSize: Int64
    public let appSupportSize: Int64
    public let totalSize: Int64

    public init(documentsSize: Int64, cacheSize: Int64, appSupportSize: Int64, totalSize: Int64) {
        self.documentsSize = documentsSize
        self.cacheSize = cacheSize
        self.appSupportSize = appSupportSize
        self.totalSize = totalSize
    }
}
