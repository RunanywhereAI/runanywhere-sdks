import Foundation

/// Download task information
public struct DownloadTask {
    public let id: String
    public let modelId: String
    public let progress: AsyncStream<DownloadProgress>
    public let result: Task<URL, Error>

    public init(
        id: String,
        modelId: String,
        progress: AsyncStream<DownloadProgress>,
        result: Task<URL, Error>
    ) {
        self.id = id
        self.modelId = modelId
        self.progress = progress
        self.result = result
    }
}
