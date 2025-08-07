import Foundation

/// Processor information
public struct ProcessorInfo: Codable, Sendable {
    public let chipName: String
    public let coreCount: Int
    public let performanceCores: Int
    public let efficiencyCores: Int
    public let architecture: String
    public let hasARM64E: Bool
    public let clockFrequency: Double // GHz
    public let l2CacheSize: Int64 // bytes
    public let l3CacheSize: Int64 // bytes
    public let neuralEngineCores: Int
    public let estimatedTops: Float
    public let generation: ProcessorGeneration
    public let hasNeuralEngine: Bool

    public init(
        chipName: String = "Unknown",
        coreCount: Int,
        performanceCores: Int = 0,
        efficiencyCores: Int = 0,
        architecture: String,
        hasARM64E: Bool = false,
        clockFrequency: Double = 0.0,
        l2CacheSize: Int64 = 0,
        l3CacheSize: Int64 = 0,
        neuralEngineCores: Int = 0,
        estimatedTops: Float = 0.0
    ) {
        self.chipName = chipName
        self.coreCount = coreCount
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.architecture = architecture
        self.hasARM64E = hasARM64E
        self.clockFrequency = clockFrequency
        self.l2CacheSize = l2CacheSize
        self.l3CacheSize = l3CacheSize
        self.neuralEngineCores = neuralEngineCores
        self.estimatedTops = estimatedTops
        self.hasNeuralEngine = neuralEngineCores > 0

        // Determine generation based on chip name
        if chipName.contains("A18") || chipName.contains("M4") {
            self.generation = .generation5
        } else if chipName.contains("A17") || chipName.contains("M3") {
            self.generation = .generation4
        } else if chipName.contains("A16") || chipName.contains("M2") {
            self.generation = .generation3
        } else if chipName.contains("A15") || chipName.contains("M1") {
            self.generation = .generation2
        } else if chipName.contains("A14") {
            self.generation = .generation1
        } else {
            self.generation = .unknown
        }
    }

    // Backward compatibility initializer
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
        self.init(
            chipName: "Unknown",
            coreCount: coreCount,
            performanceCores: performanceCores,
            efficiencyCores: efficiencyCores,
            architecture: architecture,
            hasARM64E: hasARM64E,
            clockFrequency: clockFrequency,
            l2CacheSize: l2CacheSize,
            l3CacheSize: l3CacheSize,
            neuralEngineCores: 0,
            estimatedTops: 0.0
        )
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

    // New computed properties
    public var performanceTier: PerformanceTier {
        switch estimatedTops {
        case 35...: return .flagship
        case 15...: return .high
        case 10...: return .medium
        default: return .entry
        }
    }

    public var recommendedBatchSize: Int {
        switch performanceTier {
        case .flagship: return 8
        case .high: return 4
        case .medium: return 2
        case .entry: return 1
        }
    }

    public var supportsConcurrentInference: Bool {
        performanceCores >= 4 && neuralEngineCores >= 16
    }
}

// MARK: - Supporting Types

public enum ProcessorGeneration: String, Codable, CaseIterable, Sendable {
    case generation1 = "gen1" // A14, M1
    case generation2 = "gen2" // A15, M2
    case generation3 = "gen3" // A16, M3
    case generation4 = "gen4" // A17 Pro, M4
    case generation5 = "gen5" // A18, A18 Pro
    case unknown = "unknown"
}

public enum PerformanceTier: String, Codable, Sendable {
    case flagship
    case high
    case medium
    case entry
}
