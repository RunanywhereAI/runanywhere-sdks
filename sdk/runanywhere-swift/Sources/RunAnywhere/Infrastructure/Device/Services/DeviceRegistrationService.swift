//
//  DeviceRegistrationService.swift
//  RunAnywhere SDK
//
//  Service responsible for device registration with backend and Supabase
//

import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

// MARK: - Device Registration Service

/// Service responsible for device registration with backend
/// Handles lazy registration, retry logic, and dev/prod environments
public actor DeviceRegistrationService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "DeviceRegistration")
    private let keychainManager: KeychainManager

    /// Registration state management
    private var cachedDeviceId: String?
    private var isRegistering = false

    /// Configuration
    private static let maxRetries = 3
    private static let retryDelayNanoseconds: UInt64 = 2_000_000_000 // 2 seconds

    /// Keys for persistence
    private static let deviceIdKey = "com.runanywhere.sdk.deviceId"
    private static let devDeviceRegisteredKey = "com.runanywhere.sdk.devDeviceRegistered"

    // MARK: - Initialization

    public init(
        keychainManager: KeychainManager = .shared,
        deviceService _: DeviceService? = nil
    ) {
        self.keychainManager = keychainManager
    }

    // MARK: - Public API

    /// Ensure device is registered with backend (lazy registration)
    /// Only registers if device ID doesn't exist locally
    /// - Parameters:
    ///   - params: SDK initialization parameters
    ///   - environment: Current SDK environment
    ///   - serviceContainer: Service container for network services
    /// - Throws: RunAnywhereError if registration fails
    public func ensureDeviceRegistered(
        params: SDKInitParams,
        environment: SDKEnvironment,
        serviceContainer: ServiceContainer
    ) async throws {
        // Network services should already be initialized by RunAnywhere.ensureDeviceRegistered()
        // This method now only handles the device registration logic itself

        // Check cached device ID
        if let cachedId = cachedDeviceId, !cachedId.isEmpty {
            logger.debug("Device already registered (cached): \(cachedId.prefix(8))...")
            return
        }

        // Check local storage
        if let storedId = getStoredDeviceId(), !storedId.isEmpty {
            logger.debug("Found stored device ID: \(storedId.prefix(8))...")
            cachedDeviceId = storedId

            // In development mode, check if registered to Supabase
            if environment == .development && !isDevDeviceRegistered() {
                logger.debug("Device ID exists but not registered - will register now")
            } else {
                logger.debug("Device already fully registered")
                return
            }
        } else {
            logger.debug("No device ID found - will create and register")
        }

        // Prevent concurrent registrations
        if isRegistering {
            try await waitForRegistration()
            return
        }

        isRegistering = true
        defer { isRegistering = false }

        logger.debug("Starting device registration...")

        // Route to appropriate registration method
        if environment == .development {
            try await registerDevDevice(params: params)
        } else {
            try await registerProductionDevice(params: params, serviceContainer: serviceContainer)
        }
    }

    /// Get the current device ID
    public func getDeviceId() -> String? {
        return cachedDeviceId ?? getStoredDeviceId()
    }

    /// Check if device is registered
    public func isRegistered() -> Bool {
        return getStoredDeviceId() != nil
    }

    /// Clear device registration (for reset)
    public func clearRegistration() {
        cachedDeviceId = nil
        clearStoredDeviceId()
    }

    // MARK: - Development Mode Registration

    private func registerDevDevice(params: SDKInitParams) async throws {
        logger.debug("Development mode - registering device for dev analytics...")

        do {
            try await performDevRegistration(params: params)

            guard let deviceId = getStoredDeviceId() else {
                throw RunAnywhereError.storageError("Device ID not found after successful registration")
            }

            cachedDeviceId = deviceId
            markDevDeviceAsRegistered()

            // Track device registration success
            EventPublisher.shared.track(DeviceEvent.registered(deviceId: deviceId))

            logger.info("Dev device registration successful")

        } catch {
            // Non-critical - create mock device ID
            logger.warning("Dev device registration failed (non-critical): \(error.localizedDescription)")

            let mockDeviceId = "dev-" + generateDeviceIdentifier()
            try storeDeviceId(mockDeviceId)
            cachedDeviceId = mockDeviceId

            // Track with mock ID (still successful from SDK perspective)
            EventPublisher.shared.track(DeviceEvent.registered(deviceId: mockDeviceId))

            logger.info("Using mock device ID for development: \(mockDeviceId.prefix(8))...")
        }
    }

    private func performDevRegistration(params: SDKInitParams) async throws {
        let deviceInfo = DeviceInfo.current
        let deviceId = getStoredDeviceId() ?? generateDeviceIdentifier()
        let isNewDevice = getStoredDeviceId() == nil

        let request = DevDeviceRegistrationRequest(
            deviceId: deviceId,
            deviceModel: deviceInfo.model,
            osVersion: deviceInfo.osVersion,
            architecture: deviceInfo.architecture,
            platform: deviceInfo.platform,
            sdkVersion: SDKConstants.version,
            buildToken: BuildToken.token,
            lastSeenAt: ISO8601DateFormatter().string(from: Date())
        )

        if let supabaseConfig = params.supabaseConfig {
            try await registerViaSupabase(request: request, config: supabaseConfig)
        } else {
            try await registerViaBackend(request: request, baseURL: params.baseURL)
        }

        if isNewDevice {
            try storeDeviceId(deviceId)
        }
    }

    // MARK: - Production Mode Registration

    private func registerProductionDevice(
        params _: SDKInitParams,
        serviceContainer: ServiceContainer
    ) async throws {
        var lastError: Error?

        for attempt in 1...Self.maxRetries {
            do {
                logger.info("Device registration attempt \(attempt) of \(Self.maxRetries)")

                // Authentication service should already be initialized by RunAnywhere.ensureDeviceRegistered()
                guard let authService = serviceContainer.authenticationService else {
                    let errorMsg = "Authentication service not available - should be initialized before calling device registration"
                    throw RunAnywhereError.invalidState(errorMsg)
                }

                let registration = try await authService.registerDevice()
                try storeDeviceId(registration.deviceId)
                cachedDeviceId = registration.deviceId

                // Track device registration success
                EventPublisher.shared.track(DeviceEvent.registered(deviceId: registration.deviceId))

                logger.info("Device registered successfully: \(registration.deviceId.prefix(8))...")
                return

            } catch {
                lastError = error
                logger.error("Device registration attempt \(attempt) failed: \(error.localizedDescription)")

                if !isRetryableError(error) {
                    throw error
                }

                if attempt < Self.maxRetries {
                    logger.info("Waiting before retry...")
                    try? await Task.sleep(nanoseconds: Self.retryDelayNanoseconds)
                }
            }
        }

        // Track device registration failure
        let finalError = lastError ?? RunAnywhereError.networkError("Device registration failed after \(Self.maxRetries) attempts")
        EventPublisher.shared.track(DeviceEvent.registrationFailed(error: finalError.localizedDescription))

        throw finalError
    }

    // MARK: - Network Requests

    private func registerViaSupabase(request: DevDeviceRegistrationRequest, config: SupabaseConfig) async throws {
        let url = config.projectURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("sdk_devices")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunAnywhereError.networkError("Invalid response from Supabase")
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            var errorMessage = "Registration failed with status code: \(httpResponse.statusCode)"
            // swiftlint:disable:next avoid_any_type
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorData["message"] as? String {
                errorMessage = message
            }
            throw RunAnywhereError.networkError(errorMessage)
        }

        logger.info("Device successfully registered with Supabase!")
    }

    private func registerViaBackend(request: DevDeviceRegistrationRequest, baseURL: URL) async throws {
        let url = baseURL.appendingPathComponent(APIEndpoint.devDeviceRegistration.path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw RunAnywhereError.networkError("Registration failed")
        }

        _ = try JSONDecoder().decode(DevDeviceRegistrationResponse.self, from: data)
    }

    // MARK: - Device ID Persistence

    private func getStoredDeviceId() -> String? {
        if let keychainId = keychainManager.retrieveDeviceUUID() {
            return keychainId
        }
        return UserDefaults.standard.string(forKey: Self.deviceIdKey)
    }

    private func storeDeviceId(_ deviceId: String) throws {
        guard !deviceId.isEmpty else {
            throw RunAnywhereError.validationFailed("Device ID cannot be empty")
        }

        try keychainManager.storeDeviceUUID(deviceId)
        UserDefaults.standard.set(deviceId, forKey: Self.deviceIdKey)
        UserDefaults.standard.synchronize()
    }

    private func clearStoredDeviceId() {
        try? keychainManager.delete(for: "com.runanywhere.sdk.device.uuid")
        UserDefaults.standard.removeObject(forKey: Self.deviceIdKey)
        UserDefaults.standard.synchronize()
    }

    private func generateDeviceIdentifier() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS)
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            return vendorId
        }
        #endif
        return UUID().uuidString
    }

    // MARK: - Dev Registration State

    private func isDevDeviceRegistered() -> Bool {
        if let registered = try? keychainManager.retrieve(for: Self.devDeviceRegisteredKey),
           registered == "true" {
            return true
        }
        return UserDefaults.standard.bool(forKey: Self.devDeviceRegisteredKey)
    }

    private func markDevDeviceAsRegistered() {
        try? keychainManager.store("true", for: Self.devDeviceRegisteredKey)
        UserDefaults.standard.set(true, forKey: Self.devDeviceRegisteredKey)
    }

    // MARK: - Helpers

    private func waitForRegistration() async throws {
        var waitAttempts = 0
        let maxWaitAttempts = 50 // 5 seconds timeout

        while isRegistering && waitAttempts < maxWaitAttempts {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            waitAttempts += 1
        }

        if let deviceId = cachedDeviceId, !deviceId.isEmpty {
            return
        }

        if waitAttempts >= maxWaitAttempts {
            throw RunAnywhereError.timeout("Device registration timeout")
        }
    }

    private func isRetryableError(_ error: Error) -> Bool {
        if let sdkError = error as? SDKError {
            switch sdkError {
            case .networkError, .timeout, .serverError:
                return true
            default:
                return false
            }
        }

        if let nsError = error as NSError? {
            let retryableCodes = [
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorDNSLookupFailed
            ]
            return retryableCodes.contains(nsError.code)
        }

        return false
    }
}
