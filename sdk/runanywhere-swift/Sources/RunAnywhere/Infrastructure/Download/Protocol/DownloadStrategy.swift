import Foundation

/// Protocol for custom download strategies provided by host app
/// Allows extending download behavior without modifying core SDK logic
public protocol DownloadStrategy {
    /// Check if this strategy can handle the given model
    func canHandle(model: ModelInfo) -> Bool

    /// Download the model (can be multi-file, ZIP, etc.)
    /// - Parameters:
    ///   - model: The model to download
    ///   - destinationFolder: Where to save the downloaded files
    ///   - progressHandler: Optional progress callback (0.0 to 1.0)
    /// - Returns: URL to the downloaded model folder
    func download(
        model: ModelInfo,
        to destinationFolder: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws -> URL
}
