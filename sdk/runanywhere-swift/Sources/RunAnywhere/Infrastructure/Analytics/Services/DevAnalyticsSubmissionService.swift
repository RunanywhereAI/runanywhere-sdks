//
//  DevAnalyticsSubmissionService.swift
//  RunAnywhere SDK
//
//  Service responsible for submitting development analytics to Supabase/backend
//

import Foundation

// MARK: - Parameter Structs

/// Parameters for generation analytics submission
public struct GenerationAnalyticsParams {
    public let generationId: String
    public let modelId: String
    public let latencyMs: Double
    public let tokensPerSecond: Double
    public let inputTokens: Int
    public let outputTokens: Int
    public let success: Bool

    public init(
        generationId: String,
        modelId: String,
        latencyMs: Double,
        tokensPerSecond: Double,
        inputTokens: Int,
        outputTokens: Int,
        success: Bool
    ) {
        self.generationId = generationId
        self.modelId = modelId
        self.latencyMs = latencyMs
        self.tokensPerSecond = tokensPerSecond
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.success = success
    }
}

// MARK: - Dev Analytics Submission Service

/// Service responsible for submitting analytics in development mode
/// Handles both Supabase and backend submission routes
public final class DevAnalyticsSubmissionService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "DevAnalytics")

    // MARK: - Singleton

    public static let shared = DevAnalyticsSubmissionService()

    private init() {}

    // MARK: - Public API

    /// Submit generation analytics using ServiceContainer for all dependencies
    /// Thin wrapper that fetches deviceId and params internally
    /// - Parameters:
    ///   - analyticsParams: Generation analytics parameters
    ///   - serviceContainer: Service container for dependencies
    ///   - sdkParams: SDK initialization parameters
    public func submit(
        analyticsParams: GenerationAnalyticsParams,
        serviceContainer: ServiceContainer,
        sdkParams: SDKInitParams
    ) async {
        guard sdkParams.environment == .development else { return }

        // Fetch deviceId from service
        let deviceId = await serviceContainer.deviceRegistrationService.getDeviceId()

        // Non-blocking background submission
        Task.detached(priority: .background) { [weak self] in
            await self?.performSubmission(
                analyticsParams: analyticsParams,
                sdkParams: sdkParams,
                deviceId: deviceId ?? "unknown"
            )
        }
    }

    // MARK: - Private Implementation

    private func performSubmission(
        analyticsParams: GenerationAnalyticsParams,
        sdkParams: SDKInitParams,
        deviceId: String
    ) async {
        do {
            // Capture host app information
            let hostAppIdentifier = Bundle.main.bundleIdentifier
            let hostAppName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
                ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            let hostAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

            let request = DevAnalyticsSubmissionRequest(
                generationId: analyticsParams.generationId,
                deviceId: deviceId,
                modelId: analyticsParams.modelId,
                tokensPerSecond: analyticsParams.tokensPerSecond,
                totalGenerationTimeMs: analyticsParams.latencyMs,
                inputTokens: analyticsParams.inputTokens,
                outputTokens: analyticsParams.outputTokens,
                success: analyticsParams.success,
                buildToken: BuildToken.token,
                sdkVersion: SDKConstants.version,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                hostAppIdentifier: hostAppIdentifier,
                hostAppName: hostAppName,
                hostAppVersion: hostAppVersion
            )

            if let supabaseConfig = sdkParams.supabaseConfig {
                try await submitViaSupabase(request: request, config: supabaseConfig)
            } else {
                try await submitViaBackend(request: request, baseURL: sdkParams.baseURL)
            }
        } catch {
            // Fail silently - analytics should never break the SDK
            logger.debug("Analytics submission failed (non-critical): \(error.localizedDescription)")
        }
    }

    private func submitViaSupabase(
        request: DevAnalyticsSubmissionRequest,
        config: SupabaseConfig
    ) async throws {
        let url = config.projectURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("sdk_generation_analytics")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunAnywhereError.networkError("Invalid response from Supabase")
        }

        logger.debug("Analytics HTTP Response: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            var errorMessage = "Analytics submission failed: \(httpResponse.statusCode)"
            // swiftlint:disable:next avoid_any_type
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorData["message"] as? String {
                errorMessage = message
            }
            throw RunAnywhereError.networkError(errorMessage)
        }

        logger.debug("Analytics submission successful")
    }

    private func submitViaBackend(
        request: DevAnalyticsSubmissionRequest,
        baseURL: URL
    ) async throws {
        let url = baseURL.appendingPathComponent(APIEndpoint.devAnalytics.path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (_, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw RunAnywhereError.networkError("Analytics submission failed")
        }
    }
}
