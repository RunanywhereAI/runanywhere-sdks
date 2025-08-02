import Foundation

/// Protocol for download strategies
public protocol DownloadStrategy {
    /// Execute the download
    /// - Parameters:
    ///   - url: The URL to download from
    ///   - config: Download configuration
    ///   - progressHandler: Progress callback
    /// - Returns: Downloaded data
    /// - Throws: Download errors
    func download(
        from url: URL,
        config: DownloadConfiguration,
        progressHandler: @escaping (DownloadProgress) async -> Void
    ) async throws -> Data
}
