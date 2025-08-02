import Foundation

/// Cost breakdown for generation
public struct CostBreakdown {
    /// Total cost in USD
    public let totalCost: Double

    /// Savings achieved by using on-device execution
    public let savingsAchieved: Double

    /// Cloud cost if it had been used
    public let cloudCost: Double?

    /// Device execution cost
    public let deviceCost: Double?

    public init(
        totalCost: Double,
        savingsAchieved: Double,
        cloudCost: Double? = nil,
        deviceCost: Double? = nil
    ) {
        self.totalCost = totalCost
        self.savingsAchieved = savingsAchieved
        self.cloudCost = cloudCost
        self.deviceCost = deviceCost
    }
}
