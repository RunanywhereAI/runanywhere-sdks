//
//  ComparisonResult.swift
//  RunAnywhere SDK
//
//  Service comparison result
//

import Foundation

/// Service comparison result
public struct ComparisonResult {
    public let service1Name: String
    public let service2Name: String
    public let result1: SingleRunResult
    public let result2: SingleRunResult
    public let winner: String
}
