//
//  DeviceRegistrationService.swift
//  RunAnywhere SDK
//
//  Unified service for device registration and device info across all environments
//  Uses NetworkService for all network calls
//

import Foundation

/// Unified service for device registration with backend
/// Handles registration for development, staging, and production environments
/// Uses NetworkService (APIClient) for network calls
/// Device UUID is managed by DeviceIdentity (Keychain-persisted)
public actor DeviceRegistrationService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "DeviceRegistration")

    /// Key for tracking registration status
    private static let registeredKey = "com.runanywhere.sdk.deviceRegistered"

    // MARK: - Initialization

    public init() {}

    // MARK: - Device Info API

    /// Get current device information
    /// Returns fresh data each time
    public var currentDeviceInfo: DeviceInfo {
        DeviceInfo.current
    }

    /// Get the persistent device ID (Keychain-stored UUID)
    public var deviceId: String {
        DeviceIdentity.persistentUUID
    }

    // MARK: - Registration API

    /// Register device with backend if not already registered
    /// Uses NetworkService for network calls
    /// Works for all environments: development, staging, and production
    public func registerIfNeeded(
        networkService: any NetworkService,
        environment: SDKEnvironment
    ) async {
        // Skip if already registered
        guard !isRegistered else {
            logger.debug("Device already registered, skipping")
            return
        }

        let deviceId = DeviceIdentity.persistentUUID

        do {
            let request = DeviceRegistrationRequest.fromCurrentDevice()
            let endpoint = APIEndpoint.deviceRegistrationEndpoint(for: environment)

            // Use NetworkService for the request
            // Development mode uses build token, staging/production use JWT
            let _: DeviceRegistrationResponse = try await networkService.post(
                endpoint,
                request,
                requiresAuth: environment != .development
            )

            markAsRegistered()
            EventPublisher.shared.track(DeviceEvent.registered(deviceId: deviceId))
            logger.info("Device registration successful")

        } catch {
            // Registration failure is non-critical - log and continue
            EventPublisher.shared.track(DeviceEvent.registrationFailed(error: error.localizedDescription))
            logger.warning("Device registration failed: \(error.localizedDescription)")
        }
    }

    /// Check if device is registered
    public var isRegistered: Bool {
        UserDefaults.standard.bool(forKey: Self.registeredKey)
    }

    /// Clear registration status (for testing/reset)
    public func clearRegistration() {
        UserDefaults.standard.removeObject(forKey: Self.registeredKey)
    }

    // MARK: - Private Methods

    private func markAsRegistered() {
        UserDefaults.standard.set(true, forKey: Self.registeredKey)
    }
}
