//
//  CompatibilityResult.swift
//  RunAnywhere SDK
//
//  Compatibility result types
//

import Foundation

/// Compatibility result
public struct CompatibilityResult {
    public let isCompatible: Bool
    public let reason: String?
    public let warnings: [String]
    public let recommendations: [String]
    public let confidence: CompatibilityConfidence

    public init(
        isCompatible: Bool,
        reason: String? = nil,
        warnings: [String] = [],
        recommendations: [String] = [],
        confidence: CompatibilityConfidence = .high
    ) {
        self.isCompatible = isCompatible
        self.reason = reason
        self.warnings = warnings
        self.recommendations = recommendations
        self.confidence = confidence
    }
}

/// Compatibility confidence level
public enum CompatibilityConfidence {
    case high      // Tested and verified
    case medium    // Should work based on specs
    case low       // Might work but untested
    case unknown   // No information available
}
