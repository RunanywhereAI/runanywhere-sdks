import Foundation

/// Token budget constraints for cost control
public struct TokenBudget {
    /// Maximum tokens allowed
    public let maxTokens: Int

    /// Maximum cost allowed (in cents)
    public let maxCost: Double?

    /// Fallback behavior when budget exceeded
    public let fallbackBehavior: FallbackBehavior

    /// Fallback behavior options when budget is exceeded
    public enum FallbackBehavior {
        case stop
        case switchToDevice
        case truncate
    }

    /// Initialize token budget
    /// - Parameters:
    ///   - maxTokens: Maximum tokens allowed
    ///   - maxCost: Maximum cost allowed in cents (optional)
    ///   - fallbackBehavior: Behavior when budget exceeded (default: .stop)
    public init(
        maxTokens: Int,
        maxCost: Double? = nil,
        fallbackBehavior: FallbackBehavior = .stop
    ) {
        self.maxTokens = maxTokens
        self.maxCost = maxCost
        self.fallbackBehavior = fallbackBehavior
    }
}
