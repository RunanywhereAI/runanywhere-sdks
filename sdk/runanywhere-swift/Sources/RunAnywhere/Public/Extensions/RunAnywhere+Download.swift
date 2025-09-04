import Foundation

// MARK: - Download Extensions

public extension RunAnywhere {

    /// Register a custom download strategy
    /// - Parameter strategy: The download strategy to register
    static func registerDownloadStrategy(_ strategy: DownloadStrategy) {
        // Register with the download service
        RunAnywhere.serviceContainer.downloadService.registerStrategy(strategy)
    }
}
