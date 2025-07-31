//
//  ModelProvider.swift
//  RunAnywhereAI
//
//  Abstract model providers for different download sources
//

import Foundation

// MARK: - Model Provider Protocol

protocol ModelProvider {
    /// Unique identifier for this provider
    var id: String { get }

    /// Display name of the provider
    var name: String { get }

    /// Icon name for the provider
    var icon: String { get }

    /// Whether this provider requires authentication
    var requiresAuth: Bool { get }

    /// Type of authentication required
    var authType: AuthType { get }

    /// Check if authenticated
    var isAuthenticated: Bool { get }

    /// Validate a URL for this provider
    func canHandle(url: URL) -> Bool

    /// Download a model from this provider
    func downloadModel(
        _ modelInfo: ModelInfo,
        to directory: URL,
        progress: @escaping (DownloadProgress) -> Void
    ) async throws -> URL

    /// Get authentication credentials if needed
    func getAuthCredentials() -> Any?

    /// Configure authentication
    func configureAuth(credentials: Any) throws
}

// MARK: - Base Model Provider

class BaseModelProvider: ModelProvider {
    let id: String
    let name: String
    let icon: String
    let requiresAuth: Bool
    let authType: AuthType

    init(id: String, name: String, icon: String, requiresAuth: Bool = false, authType: AuthType = .none) {
        self.id = id
        self.name = name
        self.icon = icon
        self.requiresAuth = requiresAuth
        self.authType = authType
    }

    var isAuthenticated: Bool {
        return !requiresAuth // Base provider doesn't require auth
    }

    func canHandle(url: URL) -> Bool {
        // Override in subclasses
        return false
    }

    func downloadModel(
        _ modelInfo: ModelInfo,
        to directory: URL,
        progress: @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        // Base implementation should not use ModelDownloadManager to avoid circular dependency
        // Subclasses should override this method with actual download logic
        throw ModelProviderError.providerNotFound
    }

    func getAuthCredentials() -> Any? {
        return nil
    }

    func configureAuth(credentials: Any) throws {
        // Override in subclasses that need auth
    }
}

// MARK: - HuggingFace Provider

class HuggingFaceProvider: BaseModelProvider {

    init() {
        super.init(
            id: "huggingface",
            name: "Hugging Face",
            icon: "face.smiling",
            requiresAuth: false,  // Public models don't require auth
            authType: .huggingFace
        )
    }

    override var isAuthenticated: Bool {
        // Check if we have stored credentials
        let keychain = KeychainService()
        if let _ = keychain.read(key: "huggingface_token") {
            return true
        }
        return false
    }

    override func canHandle(url: URL) -> Bool {
        return url.host?.contains("huggingface.co") == true
    }

    override func downloadModel(
        _ modelInfo: ModelInfo,
        to directory: URL,
        progress: @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        // For HuggingFace, we need to handle downloads directly with proper auth
        guard let downloadURL = modelInfo.downloadURL else {
            throw ModelDownloadError.noDownloadURL
        }

        // Create a proper download request
        var request = URLRequest(url: downloadURL)
        request.setValue("RunAnywhereAI/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 3600 // 1 hour for large models

        // Add HuggingFace auth if available
        let keychain = KeychainService()
        if let tokenData = keychain.read(key: "huggingface_token"),
           let token = String(data: tokenData, encoding: .utf8) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Use continuation to bridge delegate callbacks to async/await
        return try await withCheckedThrowingContinuation { continuation in
            print("Starting HuggingFace download for: \(downloadURL.absoluteString)")

            let delegate = DirectURLDownloadDelegate()
            delegate.progressHandler = progress
            delegate.destinationDirectory = directory
            delegate.fileName = modelInfo.downloadedFileName ?? downloadURL.lastPathComponent
            delegate.completionHandler = { result in
                switch result {
                case .success(let url):
                    continuation.resume(returning: url)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = session  // Keep reference to prevent deallocation
            let task = session.downloadTask(with: request)

            task.resume()
        }
    }

    override func getAuthCredentials() -> Any? {
        // Return credentials from keychain
        let keychain = KeychainService()
        if let tokenData = keychain.read(key: "huggingface_token"),
           let token = String(data: tokenData, encoding: .utf8) {
            return HuggingFaceCredentials(token: token, createdAt: Date())
        }
        return nil
    }

    override func configureAuth(credentials: Any) throws {
        guard let hfCredentials = credentials as? HuggingFaceCredentials else {
            throw ModelProviderError.invalidCredentials
        }
        // Save directly to keychain
        let keychain = KeychainService()
        guard let tokenData = hfCredentials.token.data(using: .utf8) else {
            throw ModelProviderError.invalidCredentials
        }
        try keychain.save(key: "huggingface_token", data: tokenData)
    }
}

// MARK: - Kaggle Provider

class KaggleProvider: BaseModelProvider {

    init() {
        super.init(
            id: "kaggle",
            name: "Kaggle",
            icon: "person.badge.key",
            requiresAuth: true,
            authType: .kaggle
        )
    }

    override var isAuthenticated: Bool {
        // Check if we have stored credentials in keychain
        // Can't access MainActor properties from here
        let keychain = KeychainService()
        if let data = keychain.read(key: "kaggle_credentials"),
           let credentials = try? JSONDecoder().decode(KaggleCredentials.self, from: data) {
            return credentials.isValid
        }
        return false
    }

    override func canHandle(url: URL) -> Bool {
        return url.host?.contains("kaggle.com") == true
    }

    override func downloadModel(
        _ modelInfo: ModelInfo,
        to directory: URL,
        progress: @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        // Use KaggleAuthService for downloading
        let authService = await KaggleAuthService.shared

        guard await authService.isAuthenticated else {
            throw ModelDownloadError.authRequired
        }

        guard let downloadURL = modelInfo.downloadURL else {
            throw ModelDownloadError.noDownloadURL
        }

        // Parse the Kaggle URL to get model details
        // The URL can be in two formats:
        // 1. API format: https://www.kaggle.com/api/v1/models/{owner}/{model}/{framework}/{variation}/{version}/download
        // 2. Web format: https://www.kaggle.com/models/{owner}/{model}/{framework}/{variation}/{version}/download
        let pathComponents = downloadURL.pathComponents.filter { $0 != "/" }

        var apiURL: URL

        if pathComponents.count >= 9 && pathComponents[0] == "api" && pathComponents[1] == "v1" && pathComponents[2] == "models" {
            // Already in API format, use as-is
            apiURL = downloadURL
        } else if pathComponents.count >= 7 && pathComponents[0] == "models" {
            // Web format, convert to API format
            let owner = pathComponents[1]
            let model = pathComponents[2]
            let framework = pathComponents[3]
            let variation = pathComponents[4]
            let version = pathComponents[5]

            apiURL = URL(string: "https://www.kaggle.com/api/v1/models/\(owner)/\(model)/\(framework)/\(variation)/\(version)/download")!
        } else {
            // Unknown format, fall back to standard download
            return try await super.downloadModel(modelInfo, to: directory, progress: progress)
        }

        // Download using KaggleAuthService
        let tempURL = try await authService.downloadModel(from: apiURL) { downloadProgress in
            // Convert to DownloadProgress
            let downloadInfo = DownloadProgress(
                bytesWritten: Int64(downloadProgress * 100_000_000), // Estimate
                totalBytes: 100_000_000, // Estimate
                fractionCompleted: downloadProgress,
                estimatedTimeRemaining: nil,
                downloadSpeed: 0
            )
            progress(downloadInfo)
        }

        // Move to final location
        let fileName = modelInfo.downloadedFileName ?? modelInfo.name
        let finalURL = directory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }

        try FileManager.default.moveItem(at: tempURL, to: finalURL)

        return finalURL
    }

    override func getAuthCredentials() -> Any? {
        // Get credentials from keychain directly
        let keychain = KeychainService()
        if let data = keychain.read(key: "kaggle_credentials"),
           let credentials = try? JSONDecoder().decode(KaggleCredentials.self, from: data) {
            return credentials
        }
        return nil
    }

    override func configureAuth(credentials: Any) throws {
        guard let kaggleCredentials = credentials as? KaggleCredentials else {
            throw ModelProviderError.invalidCredentials
        }
        // This would need to be async to use KaggleAuthService.authenticate
        // For now, we'll save directly following the same pattern as KaggleAuthService
        let keychain = KeychainService()
        let data = try JSONEncoder().encode(kaggleCredentials)
        try keychain.save(key: "kaggle_credentials", data: data)

        // Update KaggleAuthService state
        Task { @MainActor in
            KaggleAuthService.shared.currentCredentials = kaggleCredentials
            KaggleAuthService.shared.isAuthenticated = true
        }
    }
}

// MARK: - Download Delegate for Progress Tracking

private class DirectURLDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var progressHandler: ((DownloadProgress) -> Void)?
    var completionHandler: ((Result<URL, Error>) -> Void)?
    var destinationDirectory: URL?
    var fileName: String?
    var session: URLSession?
    private var startTime = Date()
    private var lastBytesWritten: Int64 = 0

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = DownloadProgress(
            bytesWritten: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite,
            fractionCompleted: totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0,
            estimatedTimeRemaining: calculateTimeRemaining(totalBytesWritten: totalBytesWritten, totalBytes: totalBytesExpectedToWrite),
            downloadSpeed: calculateSpeed(bytesWritten: totalBytesWritten)
        )

        // Debug logging
        print("Download progress: \(Int(progress.fractionCompleted * 100))% - \(totalBytesWritten)/\(totalBytesExpectedToWrite) bytes")

        DispatchQueue.main.async {
            self.progressHandler?(progress)
        }
        lastBytesWritten = totalBytesWritten
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        print("Download finished, file at: \(location.path)")

        // Move file to destination
        guard let destinationDirectory = destinationDirectory,
              let fileName = fileName else {
            completionHandler?(.failure(ModelDownloadError.networkError(NSError(domain: "Download", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing destination info"]))))
            return
        }

        do {
            // Create directory if needed
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

            let destinationURL = destinationDirectory.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: location, to: destinationURL)
            print("File moved to: \(destinationURL.path)")

            completionHandler?(.success(destinationURL))
        } catch {
            print("Error moving file: \(error)")
            completionHandler?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Download failed with error: \(error)")
            completionHandler?(.failure(ModelDownloadError.networkError(error)))
        }
    }

    private func calculateSpeed(bytesWritten: Int64) -> Double {
        let elapsed = Date().timeIntervalSince(startTime)
        return elapsed > 0 ? Double(bytesWritten) / elapsed : 0
    }

    private func calculateTimeRemaining(totalBytesWritten: Int64, totalBytes: Int64) -> TimeInterval? {
        guard totalBytes > 0 && totalBytesWritten > 0 else { return nil }
        let elapsed = Date().timeIntervalSince(startTime)
        let speed = Double(totalBytesWritten) / elapsed
        guard speed > 0 else { return nil }
        let remaining = Double(totalBytes - totalBytesWritten) / speed
        return remaining > 0 ? remaining : nil
    }
}

// MARK: - Direct URL Provider

class DirectURLProvider: BaseModelProvider {

    init() {
        super.init(
            id: "direct",
            name: "Direct URL",
            icon: "link",
            requiresAuth: false,
            authType: .none
        )
    }

    override func canHandle(url: URL) -> Bool {
        // Can handle any URL that other providers don't claim
        return true
    }

    override func downloadModel(
        _ modelInfo: ModelInfo,
        to directory: URL,
        progress: @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        // Direct download with progress tracking
        guard let downloadURL = modelInfo.downloadURL else {
            throw ModelDownloadError.noDownloadURL
        }

        // Create a proper download request
        var request = URLRequest(url: downloadURL)
        request.setValue("RunAnywhereAI/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 3600 // 1 hour for large models

        // For HuggingFace URLs, check if we need auth
        if downloadURL.host?.contains("huggingface.co") == true {
            let keychain = KeychainService()
            if let tokenData = keychain.read(key: "huggingface_token"),
               let token = String(data: tokenData, encoding: .utf8) {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        // Use continuation to bridge delegate callbacks to async/await
        return try await withCheckedThrowingContinuation { continuation in
            print("Starting direct URL download for: \(downloadURL.absoluteString)")

            let delegate = DirectURLDownloadDelegate()
            delegate.progressHandler = progress
            delegate.destinationDirectory = directory
            delegate.fileName = modelInfo.downloadedFileName ?? downloadURL.lastPathComponent
            delegate.completionHandler = { result in
                switch result {
                case .success(let url):
                    continuation.resume(returning: url)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = session  // Keep reference to prevent deallocation
            let task = session.downloadTask(with: request)

            task.resume()
        }
    }
}

// MARK: - Model Provider Manager

class ModelProviderManager {
    static let shared = ModelProviderManager()

    private let providers: [ModelProvider]

    private init() {
        self.providers = [
            HuggingFaceProvider(),
            KaggleProvider(),
            DirectURLProvider() // Must be last as it's the fallback
        ]
    }

    /// Get all available providers
    var allProviders: [ModelProvider] {
        return providers
    }

    /// Get authenticated providers
    var authenticatedProviders: [ModelProvider] {
        return providers.filter { $0.isAuthenticated || !$0.requiresAuth }
    }

    /// Find the appropriate provider for a URL
    func provider(for url: URL) -> ModelProvider {
        // Find the first provider that can handle this URL
        return providers.first { $0.canHandle(url: url) } ?? providers.last!
    }

    /// Find provider by ID
    func provider(withId id: String) -> ModelProvider? {
        return providers.first { $0.id == id }
    }

    /// Download a model using the appropriate provider
    func downloadModel(
        _ modelInfo: ModelInfo,
        to directory: URL,
        progress: @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        guard let downloadURL = modelInfo.downloadURL else {
            throw ModelDownloadError.noDownloadURL
        }

        let provider = self.provider(for: downloadURL)

        // Check authentication if required
        if provider.requiresAuth && !provider.isAuthenticated {
            throw ModelDownloadError.authRequired
        }

        return try await provider.downloadModel(modelInfo, to: directory, progress: progress)
    }
}

// MARK: - Errors

enum ModelProviderError: LocalizedError {
    case invalidCredentials
    case providerNotFound
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid credentials provided"
        case .providerNotFound:
            return "Model provider not found"
        case .authenticationFailed:
            return "Authentication failed"
        }
    }
}
