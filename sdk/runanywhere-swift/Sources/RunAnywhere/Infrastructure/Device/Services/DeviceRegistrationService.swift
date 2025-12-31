//
//  DeviceRegistrationService.swift
//  RunAnywhere SDK
//
//  Device registration service using C++ JSON building via CppBridge.Device
//

import CRACommons
import Foundation

/// Service for device registration with backend
/// Uses CppBridge.Device for JSON building (C++ is source of truth)
/// Swift only handles HTTP transport via URLSession
public actor DeviceRegistrationService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "DeviceRegistration")
    private static let registeredKey = "com.runanywhere.sdk.deviceRegistered"

    // MARK: - Initialization

    public init() {}

    // MARK: - Device Info API

    /// Get current device information
    public var currentDeviceInfo: DeviceInfo { DeviceInfo.current }

    /// Get the persistent device ID (Keychain-stored UUID)
    public var deviceId: String { DeviceIdentity.persistentUUID }

    // MARK: - Registration API

    /// Register device with backend if not already registered
    /// Uses CppBridge.Device for JSON building, Swift for HTTP
    public func registerIfNeeded(
        networkService: any NetworkService,
        environment: SDKEnvironment
    ) async {
        guard !isRegistered else {
            logger.debug("Device already registered, skipping")
            return
        }

        let deviceId = DeviceIdentity.persistentUUID

        do {
            // C++ builds the JSON with C++ build token
            let buildToken = environment == .development ? CppBridge.DevConfig.buildToken : nil
            guard let json = CppBridge.Device.buildRegistrationJSON(buildToken: buildToken) else {
                throw SDKError.general(.validationFailed, "Failed to build registration JSON")
            }

            // Get endpoint from C++
            let path = CppBridge.Endpoints.deviceRegistration(for: environment)

            // Swift makes HTTP call
            guard let data = json.data(using: .utf8) else {
                throw SDKError.general(.validationFailed, "Failed to encode JSON")
            }

            // Development uses API key auth, staging/production use JWT
            let _: Data = try await networkService.postRaw(
                path,
                data,
                requiresAuth: environment != .development
            )

            markAsRegistered()
            EventPublisher.shared.track(DeviceEvent.registered(deviceId: deviceId))
            logger.info("Device registration successful")

        } catch {
            EventPublisher.shared.track(DeviceEvent.registrationFailed(error: SDKError.from(error, category: .network)))
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
