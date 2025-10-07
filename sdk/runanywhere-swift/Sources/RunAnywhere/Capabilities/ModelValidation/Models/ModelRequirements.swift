import Foundation

/// Model requirements specification
public struct ModelRequirements {
    public let minOSVersion: String?
    public let minMemory: Int64?
    public let requiredFrameworks: [String]
    public let requiredAccelerators: [HardwareAcceleration]
    public let recommendedMemory: Int64?
    public let maxBatchSize: Int?

    public init(
        minOSVersion: String? = nil,
        minMemory: Int64? = nil,
        requiredFrameworks: [String] = [],
        requiredAccelerators: [HardwareAcceleration] = [],
        recommendedMemory: Int64? = nil,
        maxBatchSize: Int? = nil
    ) {
        self.minOSVersion = minOSVersion
        self.minMemory = minMemory
        self.requiredFrameworks = requiredFrameworks
        self.requiredAccelerators = requiredAccelerators
        self.recommendedMemory = recommendedMemory
        self.maxBatchSize = maxBatchSize
    }
}
