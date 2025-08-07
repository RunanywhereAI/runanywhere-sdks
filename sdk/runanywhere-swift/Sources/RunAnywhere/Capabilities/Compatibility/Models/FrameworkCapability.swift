//
//  FrameworkCapability.swift
//  RunAnywhere SDK
//
//  Framework capability description
//

import Foundation

/// Framework capability description
public struct FrameworkCapability {
    public let supportedFormats: [ModelFormat]
    public let supportedQuantizations: [QuantizationType]
    public let maxModelSize: Int64
    public let requiresSpecificModels: Bool
    public let minimumOS: String
    public let supportedArchitectures: [String]

    public init(
        supportedFormats: [ModelFormat],
        supportedQuantizations: [QuantizationType],
        maxModelSize: Int64,
        requiresSpecificModels: Bool,
        minimumOS: String,
        supportedArchitectures: [String]
    ) {
        self.supportedFormats = supportedFormats
        self.supportedQuantizations = supportedQuantizations
        self.maxModelSize = maxModelSize
        self.requiresSpecificModels = requiresSpecificModels
        self.minimumOS = minimumOS
        self.supportedArchitectures = supportedArchitectures
    }
}
