//
//  KaggleAuthService.swift
//  RunAnywhereAI
//
//  Kaggle authentication service for downloading models
//

import Foundation
import SwiftUI

// MARK: - Kaggle Auth Error

enum KaggleAuthError: LocalizedError {
    case invalidCredentials
    case networkError(Error)
    case authRequired
    case invalidAPIKey
    case rateLimitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid Kaggle username or API key"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authRequired:
            return "Kaggle authentication required for this download"
        case .invalidAPIKey:
            return "Invalid API key format. Expected format: username:api_key"
        case .rateLimitExceeded:
            return "Kaggle API rate limit exceeded. Please try again later."
        }
    }
}

// MARK: - Kaggle Credentials

struct KaggleCredentials: Codable {
    let username: String
    let apiKey: String
    let createdAt: Date

    var isValid: Bool {
        !username.isEmpty && !apiKey.isEmpty && apiKey.count >= 32
    }

    var authorizationHeader: String {
        let credentials = "\(username):\(apiKey)"
        let encodedCredentials = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encodedCredentials)"
    }
}

// MARK: - Kaggle Auth Service

@MainActor
class KaggleAuthService: ObservableObject {
    static let shared = KaggleAuthService()

    @Published var isAuthenticated = false
    @Published var currentCredentials: KaggleCredentials?

    private let keychain = KeychainService()
    private let kaggleKeychainKey = "kaggle_credentials"

    private init() {
        loadCredentials()
    }

    // MARK: - Authentication Methods

    func authenticate(username: String, apiKey: String) async throws {
        // Validate format
        guard !username.isEmpty, !apiKey.isEmpty else {
            throw KaggleAuthError.invalidCredentials
        }

        guard apiKey.count >= 32 else {
            throw KaggleAuthError.invalidAPIKey
        }

        let credentials = KaggleCredentials(
            username: username,
            apiKey: apiKey,
            createdAt: Date()
        )

        // Test credentials with a simple API call
        try await validateCredentials(credentials)

        // Save to keychain
        try saveCredentials(credentials)

        currentCredentials = credentials
        isAuthenticated = true
    }

    func logout() {
        currentCredentials = nil
        isAuthenticated = false
        try? keychain.delete(key: kaggleKeychainKey)
    }

    private func validateCredentials(_ credentials: KaggleCredentials) async throws {
        // Test with Kaggle API to validate credentials
        let url = URL(string: "https://www.kaggle.com/api/v1/datasets/list?user=\(credentials.username)")!
        var request = URLRequest(url: url)
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    return // Success
                case 401:
                    throw KaggleAuthError.invalidCredentials
                case 429:
                    throw KaggleAuthError.rateLimitExceeded
                default:
                    throw KaggleAuthError.networkError(URLError(.badServerResponse))
                }
            }
        } catch {
            if error is KaggleAuthError {
                throw error
            }
            throw KaggleAuthError.networkError(error)
        }
    }

    // MARK: - Credential Management

    private func loadCredentials() {
        if let data = keychain.read(key: kaggleKeychainKey),
           let credentials = try? JSONDecoder().decode(KaggleCredentials.self, from: data) {
            currentCredentials = credentials
            isAuthenticated = credentials.isValid
        }
    }

    private func saveCredentials(_ credentials: KaggleCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try keychain.save(key: kaggleKeychainKey, data: data)
    }

    // MARK: - Download Methods

    func downloadModel(from url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let credentials = currentCredentials else {
            throw KaggleAuthError.authRequired
        }

        var request = URLRequest(url: url)
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("RunAnywhereAI/1.0", forHTTPHeaderField: "User-Agent")

        // Use URLSession download task with progress tracking
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: request) { tempURL, response, error in
                if let error = error {
                    continuation.resume(throwing: KaggleAuthError.networkError(error))
                    return
                }

                guard let tempURL = tempURL else {
                    continuation.resume(throwing: KaggleAuthError.networkError(URLError(.badServerResponse)))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 200...299:
                        continuation.resume(returning: tempURL)
                    case 401:
                        continuation.resume(throwing: KaggleAuthError.invalidCredentials)
                    case 429:
                        continuation.resume(throwing: KaggleAuthError.rateLimitExceeded)
                    default:
                        continuation.resume(throwing: KaggleAuthError.networkError(URLError(.badServerResponse)))
                    }
                } else {
                    continuation.resume(returning: tempURL)
                }
            }

            task.resume()
        }
    }

    // MARK: - Utility Methods

    func requiresAuth(for url: URL) -> Bool {
        url.host?.contains("kaggle") == true
    }

    func getAuthInstructions() -> [String] {
        [
            "1. Go to kaggle.com and sign in to your account",
            "2. Click on your profile picture → Account",
            "3. Scroll down to 'API' section",
            "4. Click 'Create New API Token'",
            "5. Download the kaggle.json file",
            "6. Open the file and copy your username and key",
            "7. Enter them below to authenticate"
        ]
    }
}

