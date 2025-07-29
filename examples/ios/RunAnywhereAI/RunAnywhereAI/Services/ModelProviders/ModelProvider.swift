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
        // Base implementation using standard download
        guard modelInfo.downloadURL != nil else {
            throw ModelDownloadError.noDownloadURL
        }
        
        let downloadManager = await ModelDownloadManager.shared
        return try await downloadManager.downloadModel(modelInfo, to: directory, progress: progress)
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
            requiresAuth: true,
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
        // Check if it's a directory-based model
        if modelInfo.format == .mlPackage && 
           modelInfo.downloadURL?.pathExtension == "mlpackage" {
            // Use ModelDownloadManager for HuggingFace directory download
            let downloadManager = await ModelDownloadManager.shared
            return try await downloadManager.downloadHuggingFaceDirectory(
                modelInfo,
                to: directory,
                progress: progress
            )
        } else {
            // Use standard download with HF auth
            return try await super.downloadModel(modelInfo, to: directory, progress: progress)
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
        // Check if we have stored credentials
        let keychain = KeychainService()
        if let _ = keychain.read(key: "kaggle_username"),
           let _ = keychain.read(key: "kaggle_key") {
            return true
        }
        return false
    }
    
    override func canHandle(url: URL) -> Bool {
        return url.host?.contains("kaggle.com") == true
    }
    
    override func getAuthCredentials() -> Any? {
        // Return credentials from keychain
        let keychain = KeychainService()
        if let usernameData = keychain.read(key: "kaggle_username"),
           let username = String(data: usernameData, encoding: .utf8),
           let keyData = keychain.read(key: "kaggle_key"),
           let key = String(data: keyData, encoding: .utf8) {
            return KaggleCredentials(username: username, apiKey: key, createdAt: Date())
        }
        return nil
    }
    
    override func configureAuth(credentials: Any) throws {
        guard let kaggleCredentials = credentials as? KaggleCredentials else {
            throw ModelProviderError.invalidCredentials
        }
        // Save directly to keychain
        let keychain = KeychainService()
        guard let usernameData = kaggleCredentials.username.data(using: .utf8),
              let keyData = kaggleCredentials.apiKey.data(using: .utf8) else {
            throw ModelProviderError.invalidCredentials
        }
        try keychain.save(key: "kaggle_username", data: usernameData)
        try keychain.save(key: "kaggle_key", data: keyData)
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
        // Direct download without any special handling
        guard let downloadURL = modelInfo.downloadURL else {
            throw ModelDownloadError.noDownloadURL
        }
        
        // Use URLSession directly for maximum flexibility
        let (tempURL, response) = try await URLSession.shared.download(from: downloadURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelDownloadError.networkError(URLError(.badServerResponse))
        }
        
        // Move to destination
        let fileName = modelInfo.downloadedFileName ?? downloadURL.lastPathComponent
        let destinationURL = directory.appendingPathComponent(fileName)
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        
        return destinationURL
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