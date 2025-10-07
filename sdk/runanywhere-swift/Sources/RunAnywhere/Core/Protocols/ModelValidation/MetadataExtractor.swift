import Foundation

/// Protocol for extracting metadata from model files
public protocol MetadataExtractor {
    /// Extracts metadata from a model file
    /// - Parameters:
    ///   - url: The URL of the model file
    ///   - format: The format of the model
    /// - Returns: The extracted metadata
    func extractMetadata(from url: URL, format: ModelFormat) async -> ModelMetadata
}
