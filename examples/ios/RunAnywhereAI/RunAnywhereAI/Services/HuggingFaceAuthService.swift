//
//  HuggingFaceAuthService.swift
//  RunAnywhereAI
//
//  Hugging Face authentication service for downloading models
//

import Foundation
import SwiftUI

// MARK: - Hugging Face Auth Error

enum HuggingFaceAuthError: LocalizedError {
    case invalidToken
    case networkError(Error)
    case authRequired
    case accessDenied
    case rateLimitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Invalid Hugging Face access token"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authRequired:
            return "Hugging Face authentication required for this model"
        case .accessDenied:
            return "Access denied. You may need to accept the model's license agreement on Hugging Face."
        case .rateLimitExceeded:
            return "Hugging Face API rate limit exceeded. Please try again later."
        }
    }
}

// MARK: - Hugging Face Credentials

struct HuggingFaceCredentials: Codable {
    let token: String
    let createdAt: Date

    var isValid: Bool {
        !token.isEmpty && token.hasPrefix("hf_")
    }

    var authorizationHeader: String {
        "Bearer \(token)"
    }
}

// MARK: - Hugging Face Auth Service

@MainActor
class HuggingFaceAuthService: ObservableObject {
    static let shared = HuggingFaceAuthService()

    @Published var isAuthenticated = false
    @Published var currentCredentials: HuggingFaceCredentials?

    private let keychain = KeychainService()
    private let huggingFaceKeychainKey = "huggingface_credentials"

    private init() {
        loadCredentials()
    }

    // MARK: - Authentication Methods

    func authenticate(token: String) async throws {
        // Validate format
        guard !token.isEmpty else {
            throw HuggingFaceAuthError.invalidToken
        }

        // HF tokens typically start with "hf_"
        guard token.hasPrefix("hf_") else {
            throw HuggingFaceAuthError.invalidToken
        }

        let credentials = HuggingFaceCredentials(
            token: token,
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
        try? keychain.delete(key: huggingFaceKeychainKey)
    }

    // MARK: - Download Methods

    func downloadModel(from url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let credentials = currentCredentials else {
            throw HuggingFaceAuthError.authRequired
        }

        var request = URLRequest(url: url)
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let session = URLSession.shared
        let (localURL, response) = try await session.download(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 401:
                throw HuggingFaceAuthError.invalidToken
            case 403:
                throw HuggingFaceAuthError.accessDenied
            case 429:
                throw HuggingFaceAuthError.rateLimitExceeded
            case 200...299:
                break // Success
            default:
                throw HuggingFaceAuthError.networkError(
                    NSError(domain: "HuggingFace", code: httpResponse.statusCode)
                )
            }
        }

        return localURL
    }

    // MARK: - Private Methods

    private func loadCredentials() {
        do {
            if let data = try keychain.retrieve(key: huggingFaceKeychainKey),
               let credentials = try? JSONDecoder().decode(HuggingFaceCredentials.self, from: data) {
                currentCredentials = credentials
                isAuthenticated = credentials.isValid
            }
        } catch {
            print("Failed to load HuggingFace credentials: \(error)")
        }
    }

    private func saveCredentials(_ credentials: HuggingFaceCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try keychain.save(key: huggingFaceKeychainKey, data: data)
    }

    private func validateCredentials(_ credentials: HuggingFaceCredentials) async throws {
        // Test with HF API whoami-v2 endpoint (the current working endpoint)
        let testURL = URL(string: "https://huggingface.co/api/whoami-v2")!

        var request = URLRequest(url: testURL)
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 401:
                    throw HuggingFaceAuthError.invalidToken
                case 200...299:
                    // Parse response to confirm it's valid
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let _ = json["type"] as? String {
                        // Valid token - has user/org type
                        print("✅ HuggingFace token validated for user: \(json["name"] as? String ?? "unknown")")
                    }
                    break
                default:
                    throw HuggingFaceAuthError.networkError(
                        NSError(domain: "HuggingFace", code: httpResponse.statusCode)
                    )
                }
            }
        } catch {
            if error is HuggingFaceAuthError {
                throw error
            }
            throw HuggingFaceAuthError.networkError(error)
        }
    }
}

// MARK: - URL Extension for HF Authentication

extension URL {
    /// Check if this URL requires Hugging Face authentication
    var requiresHuggingFaceAuth: Bool {
        guard let host = self.host else { return false }
        return host.contains("huggingface.co") &&
               (absoluteString.contains("/resolve/") || absoluteString.contains("/api/"))
    }
}
