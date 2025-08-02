import Foundation

/// Manages URLSession configuration and network requests
public class DownloadSession {

    // MARK: - Properties

    private var session: URLSession
    private var configuration: DownloadConfiguration
    private let logger = SDKLogger(category: "DownloadSession")

    // MARK: - Initialization

    public init(configuration: DownloadConfiguration) {
        self.configuration = configuration

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout * 2
        sessionConfig.waitsForConnectivity = true
        sessionConfig.allowsCellularAccess = true

        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Public Methods

    /// Update session configuration
    public func updateConfiguration(_ configuration: DownloadConfiguration) {
        self.configuration = configuration

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout * 2
        sessionConfig.waitsForConnectivity = true
        sessionConfig.allowsCellularAccess = true

        self.session = URLSession(configuration: sessionConfig)
    }

    /// Download data with progress tracking
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    public func downloadWithProgress(
        from url: URL,
        progressHandler: @escaping (Int64, Int64) -> Void
    ) async throws -> Data {
        let request = URLRequest(url: url, timeoutInterval: configuration.timeout)

        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DownloadError.httpError(httpResponse.statusCode)
        }

        let totalBytes = httpResponse.expectedContentLength
        var downloadedBytes: Int64 = 0
        var data = Data()

        for try await byte in asyncBytes {
            data.append(byte)
            downloadedBytes += 1

            // Report progress periodically
            if downloadedBytes % Int64(configuration.chunkSize) == 0 || downloadedBytes == totalBytes {
                progressHandler(downloadedBytes, totalBytes)
            }
        }

        // Verify complete download
        if totalBytes > 0 && downloadedBytes != totalBytes {
            throw DownloadError.partialDownload
        }

        return data
    }

    /// Download using data task (fallback for older iOS versions)
    public func downloadWithDataTask(
        from url: URL,
        progressHandler: @escaping (Int64, Int64) -> Void
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let request = URLRequest(url: url, timeoutInterval: configuration.timeout)

            let downloadTask = session.downloadTask(with: request) { tempURL, response, error in
                if let error = error {
                    continuation.resume(throwing: DownloadError.networkError(error))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: DownloadError.invalidResponse)
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    continuation.resume(throwing: DownloadError.httpError(httpResponse.statusCode))
                    return
                }

                guard let tempURL = tempURL else {
                    continuation.resume(throwing: DownloadError.invalidResponse)
                    return
                }

                do {
                    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let destinationURL = documentsDir.appendingPathComponent(url.lastPathComponent)

                    // Remove existing file if needed
                    try? FileManager.default.removeItem(at: destinationURL)

                    // Move downloaded file to destination
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)

                    continuation.resume(returning: destinationURL)
                } catch {
                    continuation.resume(throwing: DownloadError.networkError(error))
                }
            }

            // Observe progress
            let observation = downloadTask.progress.observe(\.fractionCompleted) { progress, _ in
                progressHandler(progress.completedUnitCount, progress.totalUnitCount)
            }

            downloadTask.resume()
        }
    }

    /// Check if URL is reachable
    public func isReachable(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10.0

        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return (200...299).contains(httpResponse.statusCode)
            }
        } catch {
            logger.debug("URL not reachable: \(error)")
        }

        return false
    }
}
