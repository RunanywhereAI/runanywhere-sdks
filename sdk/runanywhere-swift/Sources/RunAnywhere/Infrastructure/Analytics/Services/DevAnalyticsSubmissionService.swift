//
//  DevAnalyticsSubmissionService.swift
//  RunAnywhere SDK
//
//  Service responsible for submitting development analytics to Supabase/backend
//

import Foundation

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
    ///   - generationId: Unique ID for this generation
    ///   - modelId: Model identifier used
    ///   - latencyMs: Total generation time in milliseconds
    ///   - tokensPerSecond: Generation speed
    ///   - inputTokens: Number of input tokens
    ///   - outputTokens: Number of output tokens
    ///   - success: Whether generation succeeded
    ///   - serviceContainer: Service container for dependencies
    ///   - params: SDK initialization parameters
    public func submit( // swiftlint:disable:this function_parameter_count
        generationId: String,
        modelId: String,
        latencyMs: Double,
        tokensPerSecond: Double,
        inputTokens: Int,
        outputTokens: Int,
        success: Bool,
        serviceContainer: ServiceContainer,
        params: SDKInitParams
    ) async {
        guard params.environment == .development else { return }

        // Fetch deviceId from service
        let deviceId = await serviceContainer.deviceRegistrationService.getDeviceId()

        // Non-blocking background submission
        Task.detached(priority: .background) { [weak self] in
            await self?.performSubmission(
                generationId: generationId,
                modelId: modelId,
                latencyMs: latencyMs,
                tokensPerSecond: tokensPerSecond,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                success: success,
                params: params,
                deviceId: deviceId ?? "unknown"
            )
        }
    }

    /// Internal method for services to submit analytics without needing external dependencies
    /// Fetches all required context from ServiceContainer
    /// - Note: Only submits in development mode; fails silently on errors
    internal func submitInternal( // swiftlint:disable:this function_parameter_count
        generationId: String,
        modelId: String,
        latencyMs: Double,
        tokensPerSecond: Double,
        inputTokens: Int,
        outputTokens: Int,
        success: Bool
    ) async {
        // Get params from RunAnywhere internal state
        guard let params = RunAnywhere.initParams,
              params.environment == .development else { return }

        let serviceContainer = ServiceContainer.shared
        let deviceId = await serviceContainer.deviceRegistrationService.getDeviceId()

        // Non-blocking background submission
        Task.detached(priority: .background) { [weak self] in
            await self?.performSubmission(
                generationId: generationId,
                modelId: modelId,
                latencyMs: latencyMs,
                tokensPerSecond: tokensPerSecond,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                success: success,
                params: params,
                deviceId: deviceId ?? "unknown"
            )
        }
    }

    /// Submit generation analytics (non-blocking, fails silently)
    /// - Parameters:
    ///   - generationId: Unique ID for this generation
    ///   - modelId: Model identifier used
    ///   - latencyMs: Total generation time in milliseconds
    ///   - tokensPerSecond: Generation speed
    ///   - inputTokens: Number of input tokens
    ///   - outputTokens: Number of output tokens
    ///   - success: Whether generation succeeded
    ///   - params: SDK initialization parameters
    @available(*, deprecated, message: "Use submit() instead which handles deviceId internally")
    public func submitGenerationAnalytics( // swiftlint:disable:this function_parameter_count
        generationId: String,
        modelId: String,
        latencyMs: Double,
        tokensPerSecond: Double,
        inputTokens: Int,
        outputTokens: Int,
        success: Bool,
        params: SDKInitParams,
        deviceId: String?
    ) {
        guard params.environment == .development else { return }

        // Non-blocking background submission
        Task.detached(priority: .background) { [weak self] in
            await self?.performSubmission(
                generationId: generationId,
                modelId: modelId,
                latencyMs: latencyMs,
                tokensPerSecond: tokensPerSecond,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                success: success,
                params: params,
                deviceId: deviceId ?? "unknown"
            )
        }
    }

    // MARK: - Private Implementation

    private func performSubmission(
        generationId: String,
        modelId: String,
        latencyMs: Double,
        tokensPerSecond: Double,
        inputTokens: Int,
        outputTokens: Int,
        success: Bool,
        params: SDKInitParams,
        deviceId: String
    ) async {
        do {
            // Capture host app information
            let hostAppIdentifier = Bundle.main.bundleIdentifier
            let hostAppName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
                ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            let hostAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

            let request = DevAnalyticsSubmissionRequest(
                generationId: generationId,
                deviceId: deviceId,
                modelId: modelId,
                tokensPerSecond: tokensPerSecond,
                totalGenerationTimeMs: latencyMs,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                success: success,
                buildToken: BuildToken.token,
                sdkVersion: SDKConstants.version,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                hostAppIdentifier: hostAppIdentifier,
                hostAppName: hostAppName,
                hostAppVersion: hostAppVersion
            )

            if let supabaseConfig = params.supabaseConfig {
                try await submitViaSupabase(request: request, config: supabaseConfig)
            } else {
                try await submitViaBackend(request: request, baseURL: params.baseURL)
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
