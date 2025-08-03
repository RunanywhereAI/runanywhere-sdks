import Foundation

/// Detailed information about framework availability
public struct FrameworkAvailability {
    /// The framework being described
    public let framework: LLMFramework

    /// Whether this framework is available (has a registered adapter)
    public let isAvailable: Bool

    /// Reason why the framework is not available (if applicable)
    public let unavailabilityReason: String?

    /// Hardware requirements for optimal performance
    public let requirements: [HardwareRequirement]

    /// Recommended use cases for this framework
    public let recommendedFor: [String]

    /// Model formats supported by this framework
    public let supportedFormats: [ModelFormat]

    public init(
        framework: LLMFramework,
        isAvailable: Bool,
        unavailabilityReason: String? = nil,
        requirements: [HardwareRequirement] = [],
        recommendedFor: [String] = [],
        supportedFormats: [ModelFormat] = []
    ) {
        self.framework = framework
        self.isAvailable = isAvailable
        self.unavailabilityReason = unavailabilityReason
        self.requirements = requirements
        self.recommendedFor = recommendedFor
        self.supportedFormats = supportedFormats
    }
}
