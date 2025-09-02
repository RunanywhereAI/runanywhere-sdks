import Foundation

/// Simplified hardware configuration for framework adapters
public struct HardwareConfiguration: Codable, Sendable {
    /// Primary hardware accelerator to use (auto will select best available)
    public var primaryAccelerator: HardwareAcceleration = .auto

    /// Memory management mode
    public var memoryMode: MemoryMode = .balanced

    /// Number of CPU threads to use for processing
    public var threadCount: Int = ProcessInfo.processInfo.processorCount

    public enum MemoryMode: String, Codable, Sendable {
        case conservative = "conservative"
        case balanced = "balanced"
        case aggressive = "aggressive"
    }

    public init(
        primaryAccelerator: HardwareAcceleration = .auto,
        memoryMode: MemoryMode = .balanced,
        threadCount: Int = ProcessInfo.processInfo.processorCount
    ) {
        self.primaryAccelerator = primaryAccelerator
        self.memoryMode = memoryMode
        self.threadCount = threadCount
    }
}
