import Foundation

/// Storage alert
public struct StorageAlert {
    public let type: StorageAlertType
    public let message: String
    public let timestamp: Date

    public init(type: StorageAlertType, message: String, timestamp: Date) {
        self.type = type
        self.message = message
        self.timestamp = timestamp
    }
}

/// Storage alert type
public enum StorageAlertType {
    case info
    case warning
    case critical
}
