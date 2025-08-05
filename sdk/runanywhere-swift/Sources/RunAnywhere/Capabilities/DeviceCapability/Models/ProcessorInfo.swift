import Foundation

/// Processor information
public struct ProcessorInfo {
    public let coreCount: Int
    public let performanceCores: Int
    public let efficiencyCores: Int
    public let architecture: String
    public let hasARM64E: Bool
    public let clockFrequency: Double // GHz
    public let l2CacheSize: Int64 // bytes
    public let l3CacheSize: Int64 // bytes

    public init(
        coreCount: Int,
        performanceCores: Int = 0,
        efficiencyCores: Int = 0,
        architecture: String,
        hasARM64E: Bool = false,
        clockFrequency: Double = 0.0,
        l2CacheSize: Int64 = 0,
        l3CacheSize: Int64 = 0
    ) {
        self.coreCount = coreCount
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.architecture = architecture
        self.hasARM64E = hasARM64E
        self.clockFrequency = clockFrequency
        self.l2CacheSize = l2CacheSize
        self.l3CacheSize = l3CacheSize
    }

    /// Whether this is an Apple Silicon processor
    public var isAppleSilicon: Bool {
        return architecture.lowercased().contains("arm") && hasARM64E
    }

    /// Whether this is an Intel processor
    public var isIntel: Bool {
        return architecture.lowercased().contains("x86")
    }

    /// Total cache size
    public var totalCacheSize: Int64 {
        return l2CacheSize + l3CacheSize
    }
}
