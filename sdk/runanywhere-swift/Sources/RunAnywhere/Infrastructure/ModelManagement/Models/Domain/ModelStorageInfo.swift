//
//  ModelStorageInfo.swift
//  RunAnywhere SDK
//
//  Aggregate information about all stored models.
//  Located in ModelManagement as it aggregates model-specific data.
//

import Foundation

/// Aggregate information about all stored models
public struct ModelStorageInfo: Sendable {
    /// Total size of all stored models in bytes
    public let totalSize: Int64

    /// Number of stored models
    public let modelCount: Int

    /// Models grouped by inference framework
    public let modelsByFramework: [InferenceFramework: [StoredModel]]

    /// The largest model by size
    public let largestModel: StoredModel?

    public init(
        totalSize: Int64,
        modelCount: Int,
        modelsByFramework: [InferenceFramework: [StoredModel]],
        largestModel: StoredModel?
    ) {
        self.totalSize = totalSize
        self.modelCount = modelCount
        self.modelsByFramework = modelsByFramework
        self.largestModel = largestModel
    }
}
