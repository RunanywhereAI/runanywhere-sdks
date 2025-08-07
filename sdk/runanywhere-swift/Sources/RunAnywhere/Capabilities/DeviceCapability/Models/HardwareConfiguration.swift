import Foundation

/// Hardware configuration for framework adapters
public struct HardwareConfiguration {
    public var primaryAccelerator: HardwareAcceleration = .auto
    public var fallbackAccelerator: HardwareAcceleration? = .cpu
    public var memoryMode: MemoryMode = .balanced
    public var threadCount: Int = ProcessInfo.processInfo.processorCount
    public var useQuantization: Bool = false
    public var quantizationBits: Int = 8

    public enum MemoryMode {
        case conservative
        case balanced
        case aggressive
    }

    public init(
        primaryAccelerator: HardwareAcceleration = .auto,
        fallbackAccelerator: HardwareAcceleration? = .cpu,
        memoryMode: MemoryMode = .balanced,
        threadCount: Int = ProcessInfo.processInfo.processorCount,
        useQuantization: Bool = false,
        quantizationBits: Int = 8
    ) {
        self.primaryAccelerator = primaryAccelerator
        self.fallbackAccelerator = fallbackAccelerator
        self.memoryMode = memoryMode
        self.threadCount = threadCount
        self.useQuantization = useQuantization
        self.quantizationBits = quantizationBits
    }
}
