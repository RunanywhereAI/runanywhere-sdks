//
//  ModelFileInfo.swift
//  RunAnywhere SDK
//
//  Basic information about a model file on disk.
//  Located in ModelManagement as it represents model file metadata.
//

import Foundation

/// Basic information about a model file on disk
public struct ModelFileInfo: Sendable {
    /// The model identifier
    public let modelId: String

    /// The model file format
    public let format: ModelFormat

    /// File size in bytes
    public let size: Int64

    /// The inference framework this model is for (nil for legacy/unknown)
    public let framework: InferenceFramework?

    public init(
        modelId: String,
        format: ModelFormat,
        size: Int64,
        framework: InferenceFramework?
    ) {
        self.modelId = modelId
        self.format = format
        self.size = size
        self.framework = framework
    }
}
