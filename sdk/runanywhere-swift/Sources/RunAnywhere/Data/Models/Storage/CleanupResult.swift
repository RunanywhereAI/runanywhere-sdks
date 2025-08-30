import Foundation

/// Cleanup result
public struct CleanupResult {
    public let startSize: Int64
    public let endSize: Int64
    public let freedSpace: Int64
    public let errors: [Error]

    public init(startSize: Int64, endSize: Int64, freedSpace: Int64, errors: [Error]) {
        self.startSize = startSize
        self.endSize = endSize
        self.freedSpace = freedSpace
        self.errors = errors
    }
}
