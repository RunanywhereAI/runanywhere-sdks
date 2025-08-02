import Foundation

/// Storage availability check result
public struct StorageAvailability {
    public let isAvailable: Bool
    public let requiredSpace: Int64
    public let availableSpace: Int64
    public let hasWarning: Bool
    public let recommendation: String?

    public init(isAvailable: Bool, requiredSpace: Int64, availableSpace: Int64, hasWarning: Bool, recommendation: String?) {
        self.isAvailable = isAvailable
        self.requiredSpace = requiredSpace
        self.availableSpace = availableSpace
        self.hasWarning = hasWarning
        self.recommendation = recommendation
    }
}
