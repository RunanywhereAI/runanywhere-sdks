import Foundation

/// Result of a text generation request
public struct GenerationResult {
    /// Generated text
    public let text: String
    
    /// Number of tokens used
    public let tokensUsed: Int
    
    /// Model used for generation
    public let modelUsed: String
    
    /// Latency in milliseconds
    public let latencyMs: TimeInterval
    
    /// Execution target (device/cloud/hybrid)
    public let executionTarget: ExecutionTarget
    
    /// Amount saved by using on-device execution
    public let savedAmount: Double
    
    /// Additional metadata
    public let metadata: [String: Any]?
    
    /// Initializer
    internal init(
        text: String,
        tokensUsed: Int,
        modelUsed: String,
        latencyMs: TimeInterval,
        executionTarget: ExecutionTarget,
        savedAmount: Double,
        metadata: [String: Any]? = nil
    ) {
        self.text = text
        self.tokensUsed = tokensUsed
        self.modelUsed = modelUsed
        self.latencyMs = latencyMs
        self.executionTarget = executionTarget
        self.savedAmount = savedAmount
        self.metadata = metadata
    }
}