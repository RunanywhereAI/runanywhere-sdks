//
//  KeychainServiceExtensions.swift
//  RunAnywhereAI
//
//  Extensions for KeychainService to support SDK authentication
//

import Foundation

extension KeychainService {
    // MARK: - API Key Management

    /// Retrieve API key for a specific service
    func retrieveAPIKey(for service: String) throws -> String? {
        let key = "\(service)_api_key"
        guard let data = try retrieve(key: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Store API key for a specific service
    func storeAPIKey(_ apiKey: String, for service: String) throws {
        let key = "\(service)_api_key"
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.saveFailed
        }
        try save(key: key, data: data)
    }

    // MARK: - HuggingFace Authentication

    /// Get HuggingFace token
    func getHuggingFaceToken() -> String? {
        return try? retrieveAPIKey(for: "huggingface")
    }

    /// Store HuggingFace token
    func setHuggingFaceToken(_ token: String) throws {
        try storeAPIKey(token, for: "huggingface")
    }

    // MARK: - Kaggle Authentication

    /// Get Kaggle credentials
    func getKaggleCredentials() -> (username: String, key: String)? {
        guard let username = try? retrieve(key: "kaggle_username"),
              let usernameString = String(data: username, encoding: .utf8),
              let key = try? retrieveAPIKey(for: "kaggle") else {
            return nil
        }
        return (username: usernameString, key: key)
    }

    /// Store Kaggle credentials
    func setKaggleCredentials(username: String, key: String) throws {
        // Store username
        guard let usernameData = username.data(using: .utf8) else {
            throw KeychainError.saveFailed
        }
        try save(key: "kaggle_username", data: usernameData)

        // Store API key
        try storeAPIKey(key, for: "kaggle")
    }

    // MARK: - Picovoice Authentication

    /// Get Picovoice API key
    func getPicovoiceAPIKey() -> String? {
        return try? retrieveAPIKey(for: "picovoice")
    }

    /// Store Picovoice API key
    func setPicovoiceAPIKey(_ apiKey: String) throws {
        try storeAPIKey(apiKey, for: "picovoice")
    }

    // MARK: - RunAnywhere SDK Authentication

    /// Get RunAnywhere SDK API key
    func getRunAnywhereAPIKey() -> String? {
        return try? retrieveAPIKey(for: "runanywhere")
    }

    /// Store RunAnywhere SDK API key
    func setRunAnywhereAPIKey(_ apiKey: String) throws {
        try storeAPIKey(apiKey, for: "runanywhere")
    }

    // MARK: - Utility Methods

    /// Check if credentials exist for a service
    func hasCredentials(for service: String) -> Bool {
        return (try? retrieveAPIKey(for: service)) != nil
    }

    /// Clear all API keys (useful for logout)
    func clearAllAPIKeys() throws {
        let services = ["huggingface", "kaggle", "picovoice", "runanywhere"]
        for service in services {
            try? delete(key: "\(service)_api_key")
        }
        try? delete(key: "kaggle_username")
    }
}

// MARK: - Singleton Instance

extension KeychainService {
    static let shared = KeychainService()
}
