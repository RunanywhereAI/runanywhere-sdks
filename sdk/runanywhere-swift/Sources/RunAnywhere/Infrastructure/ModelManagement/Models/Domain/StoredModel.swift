//
//  StoredModel.swift
//  RunAnywhere SDK
//
//  Represents a model that is stored on disk.
//  Located in ModelManagement as it is a core model domain type.
//

import Foundation

/// Stored model information representing a downloaded/stored model on disk
public struct StoredModel: Sendable {
    /// Model ID used for operations like deletion
    public let id: String

    /// Human-readable name
    public let name: String

    /// Path to the model on disk
    public let path: URL

    /// Size in bytes
    public let size: Int64

    /// Model file format
    public let format: ModelFormat

    /// Inference framework this model is compatible with
    public let framework: InferenceFramework?

    /// Date the model was downloaded/created
    public let createdDate: Date

    /// Date the model was last used
    public let lastUsed: Date?

    /// Tags for categorization
    public let tags: [String]

    /// Optional description
    public let description: String?

    /// Context length for language models
    public let contextLength: Int?

    /// Checksum for integrity verification
    public let checksum: String?

    public init(
        id: String,
        name: String,
        path: URL,
        size: Int64,
        format: ModelFormat,
        framework: InferenceFramework?,
        createdDate: Date,
        lastUsed: Date?,
        tags: [String] = [],
        description: String? = nil,
        contextLength: Int? = nil,
        checksum: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.format = format
        self.framework = framework
        self.createdDate = createdDate
        self.lastUsed = lastUsed
        self.tags = tags
        self.description = description
        self.contextLength = contextLength
        self.checksum = checksum
    }
}
