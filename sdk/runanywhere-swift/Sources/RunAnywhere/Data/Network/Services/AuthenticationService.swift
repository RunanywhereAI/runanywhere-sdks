import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Service responsible for authentication and token management
public actor AuthenticationService {

    // MARK: - Properties

    private let apiClient: APIClient
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiresAt: Date?
    private var deviceId: String?
    private var userId: String?  // Optional since API can return null for now if org_level
    private var organizationId: String?
    private let logger = SDKLogger(category: "AuthenticationService")

    // MARK: - Initialization

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Public Methods

    /// Authenticate with the backend and obtain access token
    public func authenticate(apiKey: String) async throws -> AuthenticationResponse {
        let deviceId = PersistentDeviceIdentity.getPersistentDeviceUUID()

        let request = AuthenticationRequest(
            apiKey: apiKey,
            deviceId: deviceId,
            platform: SDKConstants.platform,
            sdkVersion: SDKConstants.version
        )

        logger.debug("Authenticating with backend")

        // Use APIClient for the authentication request (doesn't require auth)
        let authResponse: AuthenticationResponse = try await apiClient.post(
            .authenticate,
            request,
            requiresAuth: false
        )

        // Store tokens and additional info
        self.accessToken = authResponse.accessToken
        self.refreshToken = authResponse.refreshToken
        self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(authResponse.expiresIn))
        self.deviceId = authResponse.deviceId
        self.userId = authResponse.userId
        self.organizationId = authResponse.organizationId

        // Store in keychain for persistence
        try await storeTokensInKeychain(authResponse)

        logger.info("Authentication successful")
        return authResponse
    }

    /// Get current access token, refreshing if needed
    public func getAccessToken() async throws -> String {
        // Check if token exists and is valid
        if let token = accessToken,
           let expiresAt = tokenExpiresAt,
           expiresAt > Date().addingTimeInterval(60) { // 1 minute buffer
            return token
        }

        // Try to refresh token if we have a refresh token
        if refreshToken != nil {
            return try await refreshAccessToken()
        }

        // Otherwise, we can't re-authenticate without API key
        throw SDKError.authenticationFailed("No valid token and no way to re-authenticate")
    }

    /// Perform health check
    public func healthCheck() async throws -> HealthCheckResponse {
        logger.debug("Performing health check")

        // Health check requires authentication
        return try await apiClient.get(
            .healthCheck,
            requiresAuth: true
        )
    }

    /// Check if authenticated
    public func isAuthenticated() -> Bool {
        return accessToken != nil
    }

    /// Clear authentication state
    public func clearAuthentication() async throws {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        deviceId = nil
        userId = nil
        organizationId = nil

        // Clear from keychain
        try KeychainManager.shared.delete(for: "com.runanywhere.sdk.accessToken")
        try KeychainManager.shared.delete(for: "com.runanywhere.sdk.refreshToken")
        try KeychainManager.shared.delete(for: "com.runanywhere.sdk.deviceId")
        try KeychainManager.shared.delete(for: "com.runanywhere.sdk.userId")
        try KeychainManager.shared.delete(for: "com.runanywhere.sdk.organizationId")

        logger.info("Authentication cleared")
    }

    // MARK: - Private Methods

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken = refreshToken else {
            throw SDKError.invalidAPIKey("No refresh token available")
        }

        guard let deviceId = deviceId else {
            throw SDKError.authenticationFailed("No device ID available for refresh")
        }

        logger.debug("Refreshing access token")

        let request = RefreshTokenRequest(
            deviceId: deviceId,
            refreshToken: refreshToken
        )

        // Call refresh endpoint
        let refreshResponse: RefreshTokenResponse = try await apiClient.post(
            .refreshToken,
            request,
            requiresAuth: false
        )

        // Update stored tokens and info
        self.accessToken = refreshResponse.accessToken
        self.refreshToken = refreshResponse.refreshToken
        self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(refreshResponse.expiresIn))
        self.deviceId = refreshResponse.deviceId
        self.userId = refreshResponse.userId
        self.organizationId = refreshResponse.organizationId

        // Store updated tokens in keychain
        try await storeTokensInKeychain(refreshResponse)

        logger.info("Token refresh successful")
        return refreshResponse.accessToken
    }

    private func storeTokensInKeychain(_ response: AuthenticationResponse) async throws {
        try KeychainManager.shared.store(response.accessToken, for: "com.runanywhere.sdk.accessToken")
        try KeychainManager.shared.store(response.refreshToken, for: "com.runanywhere.sdk.refreshToken")
        try KeychainManager.shared.store(response.deviceId, for: "com.runanywhere.sdk.deviceId")
        if let userId = response.userId {
            try KeychainManager.shared.store(userId, for: "com.runanywhere.sdk.userId")
        }
        try KeychainManager.shared.store(response.organizationId, for: "com.runanywhere.sdk.organizationId")
    }

    /// Load tokens from keychain if available
    public func loadStoredTokens() async throws {
        if let storedAccessToken = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.accessToken") {
            self.accessToken = storedAccessToken
            logger.debug("Loaded stored access token from keychain")
        }

        if let storedRefreshToken = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.refreshToken") {
            self.refreshToken = storedRefreshToken
            logger.debug("Loaded stored refresh token from keychain")
        }

        if let storedDeviceId = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.deviceId") {
            self.deviceId = storedDeviceId
            logger.debug("Loaded stored device ID from keychain")
        }

        if let storedUserId = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.userId") {
            self.userId = storedUserId
            logger.debug("Loaded stored user ID from keychain")
        }

        if let storedOrgId = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.organizationId") {
            self.organizationId = storedOrgId
            logger.debug("Loaded stored organization ID from keychain")
        }
    }

    /// Get current device ID
    public func getDeviceId() -> String? {
        return deviceId
    }

    /// Get current user ID
    public func getUserId() -> String? {
        return userId
    }

    /// Get current organization ID
    public func getOrganizationId() -> String? {
        return organizationId
    }

    /// Register device with backend
    public func registerDevice() async throws -> DeviceRegistrationResponse {
        logger.debug("Registering device with backend")

        // Collect device information
        let deviceInfo = await collectDeviceInfo()
        let request = DeviceRegistrationRequest(deviceInfo: deviceInfo)

        // Make API call with authentication
        let response: DeviceRegistrationResponse = try await apiClient.post(
            .registerDevice,
            request,
            requiresAuth: true
        )

        logger.info("Device registration successful: \(response.deviceId)")
        return response
    }

    // MARK: - Device Info Collection

    /// Collect comprehensive device information
    private func collectDeviceInfo() async -> DeviceRegistrationInfo {
        let processInfo = ProcessInfo.processInfo

        // Get basic system info
        let architecture = getArchitecture()
        let coreCount = processInfo.processorCount
        let totalMemory = Int64(processInfo.physicalMemory)
        let osVersion = processInfo.operatingSystemVersionString

        // Get device-specific info
        let deviceModel = getDeviceModel()
        let formFactor = getFormFactor()

        // Get device name and battery info
        #if os(iOS)
        let device = await MainActor.run { UIDevice.current }
        let deviceName = await MainActor.run { device.name }

        // Enable battery monitoring to get real values
        await MainActor.run { device.isBatteryMonitoringEnabled = true }
        let batteryLevel = await MainActor.run {
            device.batteryLevel >= 0 ? Double(device.batteryLevel) : 1.0
        }
        let batteryState = await MainActor.run {
            switch device.batteryState {
            case .unplugged: return "unplugged"
            case .charging: return "charging"
            case .full: return "full"
            case .unknown: return "unknown"
            @unknown default: return "unknown"
            }
        }
        let isLowPowerMode = processInfo.isLowPowerModeEnabled
        #else
        let deviceName = Host.current().localizedName ?? "Mac"
        let batteryLevel = 1.0  // Default for Mac
        let batteryState = "charging"  // Default for Mac
        let isLowPowerMode = false
        #endif

        // Get chip info based on device model
        let (chipName, performanceCores, efficiencyCores, neuralEngineCores) = getChipInfo(for: deviceModel)

        return DeviceRegistrationInfo(
            architecture: architecture,
            availableMemory: Int64(processInfo.physicalMemory / 2), // Available memory estimate
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            chipName: chipName,
            coreCount: coreCount,
            deviceModel: deviceModel,
            deviceName: deviceName,
            efficiencyCores: efficiencyCores,
            formFactor: formFactor,
            gpuFamily: "apple",
            hasNeuralEngine: true,  // All modern Apple devices have Neural Engine
            isLowPowerMode: isLowPowerMode,
            neuralEngineCores: neuralEngineCores,
            osVersion: osVersion,
            performanceCores: performanceCores,
            platform: SDKConstants.platform,
            totalMemory: totalMemory
        )
    }

    private func getChipInfo(for model: String) -> (chipName: String, performanceCores: Int, efficiencyCores: Int, neuralEngineCores: Int) {
        // Map device models to chip info
        // iPhone models
        if model.contains("iPhone16") {
            return ("A18 Pro", 2, 4, 16)
        } else if model.contains("iPhone15") {
            if model.contains("Pro") {
                return ("A17 Pro", 2, 4, 16)
            } else {
                return ("A16 Bionic", 2, 4, 16)
            }
        } else if model.contains("iPhone14") {
            if model.contains("Pro") {
                return ("A16 Bionic", 2, 4, 16)
            } else {
                return ("A15 Bionic", 2, 4, 16)
            }
        } else if model.contains("iPhone13") {
            return ("A15 Bionic", 2, 4, 16)
        } else if model.contains("iPhone12") {
            return ("A14 Bionic", 2, 4, 16)
        }
        // iPad models
        else if model.contains("iPad") {
            if model.contains("Pro") {
                return ("M2", 8, 4, 16)
            } else {
                return ("A15 Bionic", 2, 4, 16)
            }
        }
        // Mac models
        else if model.contains("Mac") {
            if model.contains("Studio") || model.contains("Pro") {
                return ("M2 Max", 8, 4, 32)
            } else {
                return ("M2", 8, 4, 16)
            }
        }
        // Simulator or unknown
        else if model == "arm64" || model.contains("Simulator") {
            return ("Apple Silicon", 8, 4, 16)
        }
        // Default fallback
        else {
            return ("Apple Chip", 2, 4, 16)
        }
    }

    private func getArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private func getDeviceModel() -> String {
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return modelCode ?? UIDevice.current.model
        #elseif os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
        #else
        return "Unknown"
        #endif
    }

    private func getFormFactor() -> String {
        #if os(iOS)
        let device = UIDevice.current
        if device.userInterfaceIdiom == .phone {
            return "phone"
        } else if device.userInterfaceIdiom == .pad {
            return "tablet"
        } else {
            return "unknown"
        }
        #elseif os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelString = String(cString: model)
        return modelString.contains("MacBook") ? "laptop" : "desktop"
        #else
        return "unknown"
        #endif
    }
}
