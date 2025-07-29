//
//  KaggleAuthService.swift
//  RunAnywhereAI
//
//  Kaggle authentication service for downloading models
//

import Foundation
import SwiftUI

// MARK: - Kaggle Auth Error

enum KaggleAuthError: LocalizedError, Equatable {
    case invalidCredentials
    case networkError(Error)
    case authRequired
    case invalidAPIKey
    case rateLimitExceeded
    case termsNotAccepted
    case modelNotFound
    
    static func == (lhs: KaggleAuthError, rhs: KaggleAuthError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidCredentials, .invalidCredentials),
             (.authRequired, .authRequired),
             (.invalidAPIKey, .invalidAPIKey),
             (.rateLimitExceeded, .rateLimitExceeded),
             (.termsNotAccepted, .termsNotAccepted),
             (.modelNotFound, .modelNotFound):
            return true
        case (.networkError(let lhsError), .networkError(let rhsError)):
            return (lhsError as NSError) == (rhsError as NSError)
        default:
            return false
        }
    }

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
        case .termsNotAccepted:
            return "You need to accept the model's terms of use on Kaggle.com before downloading. Please visit the model page and click 'Accept' on the terms."
        case .modelNotFound:
            return "Model not found. The model may have been removed or the URL may be incorrect."
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

        print("Downloading from Kaggle URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("RunAnywhereAI/1.0", forHTTPHeaderField: "User-Agent")
        request.httpMethod = "GET"
        request.timeoutInterval = 300 // 5 minutes for large models
        
        // Create a proper download session with delegation for progress
        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        
        // Use download task to handle redirects properly
        do {
            let (tempURL, response) = try await session.download(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Kaggle Response Status: \(httpResponse.statusCode)")
                print("Response Headers: \(httpResponse.allHeaderFields)")
                
                switch httpResponse.statusCode {
                case 200...299:
                    // Success - move to persistent location
                    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let downloadsDir = documentsDir.appendingPathComponent("KaggleDownloads", isDirectory: true)
                    
                    try FileManager.default.createDirectory(
                        at: downloadsDir,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    
                    let savedURL = downloadsDir.appendingPathComponent(UUID().uuidString + ".tmp")
                    try FileManager.default.moveItem(at: tempURL, to: savedURL)
                    
                    progress(1.0)
                    return savedURL
                    
                case 401:
                    throw KaggleAuthError.invalidCredentials
                    
                case 403, 404:
                    // For error responses, we need to fetch the error details
                    // Try to read the error from the temp file
                    if let errorData = try? Data(contentsOf: tempURL),
                       let json = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any] {
                        print("Error details: \(json)")
                        
                        if let message = json["message"] as? String {
                            if message.contains("terms of use") || message.contains("consent") {
                                throw KaggleAuthError.termsNotAccepted
                            }
                        }
                        
                        // Sometimes Kaggle returns 404 with embedded error codes
                        if httpResponse.statusCode == 404,
                           let code = json["code"] as? Int,
                           code == 403 {
                            throw KaggleAuthError.termsNotAccepted
                        }
                    }
                    
                    if httpResponse.statusCode == 403 {
                        throw KaggleAuthError.authRequired
                    } else {
                        throw KaggleAuthError.modelNotFound
                    }
                    
                case 429:
                    throw KaggleAuthError.rateLimitExceeded
                    
                default:
                    print("Unexpected status code: \(httpResponse.statusCode)")
                    throw KaggleAuthError.networkError(URLError(.badServerResponse))
                }
            } else {
                throw KaggleAuthError.networkError(URLError(.badServerResponse))
            }
        } catch {
            print("Download error: \(error)")
            if error is KaggleAuthError {
                throw error
            }
            throw KaggleAuthError.networkError(error)
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
    
    /// Get the Kaggle model page URL from a download URL
    func getModelPageURL(from downloadURL: URL) -> URL? {
        // Parse the API URL to construct the web URL
        // API: https://www.kaggle.com/api/v1/models/{owner}/{model}/{framework}/{variation}/{version}/download
        // Web: https://www.kaggle.com/models/{owner}/{model}/frameworks/{framework}/variations/{variation}/versions/{version}
        
        let pathComponents = downloadURL.pathComponents.filter { $0 != "/" }
        
        // Check if it's a valid API URL
        guard pathComponents.count >= 7,
              pathComponents[0] == "api",
              pathComponents[1] == "v1",
              pathComponents[2] == "models" else {
            return nil
        }
        
        let owner = pathComponents[3]
        let model = pathComponents[4]
        let framework = pathComponents[5]
        let variation = pathComponents[6]
        let version = pathComponents[7]
        
        // Construct the web URL
        let webURL = "https://www.kaggle.com/models/\(owner)/\(model)/frameworks/\(framework)/variations/\(variation)/versions/\(version)"
        return URL(string: webURL)
    }
}

