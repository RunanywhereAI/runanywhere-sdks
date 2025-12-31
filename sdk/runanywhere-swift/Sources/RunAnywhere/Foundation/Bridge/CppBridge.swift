// swiftlint:disable file_length
/**
 * CppBridge.swift
 *
 * Unified bridge architecture for C++ ↔ Swift interop.
 *
 * All C++ bridges are organized under a single namespace for:
 * - Consistent initialization/shutdown lifecycle
 * - Shared access to platform resources
 * - Clear ownership and dependency management
 *
 * Usage:
 * ```swift
 * // Initialize all bridges
 * CppBridge.initialize(environment: .production, apiClient: client)
 *
 * // Access specific bridges
 * CppBridge.Environment.requiresAuth(.production)
 * CppBridge.Telemetry.track(event)
 * CppBridge.Auth.getAccessToken()
 * ```
 */

import CRACommons
import Foundation

// MARK: - Main Bridge Coordinator

/// Central coordinator for all C++ bridges
/// Manages lifecycle and shared resources
public enum CppBridge {

    // MARK: - Shared State

    private static var _environment: SDKEnvironment = .development
    private static var _isInitialized = false
    private static let lock = NSLock()

    /// Current SDK environment
    static var environment: SDKEnvironment {
        lock.lock()
        defer { lock.unlock() }
        return _environment
    }

    /// Whether bridges are initialized
    public static var isInitialized: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isInitialized
    }

    // MARK: - Lifecycle

    /// Initialize all C++ bridges
    /// - Parameter environment: SDK environment
    public static func initialize(environment: SDKEnvironment) {
        lock.lock()
        _environment = environment
        _isInitialized = true
        lock.unlock()

        // Initialize sub-bridges
        Events.register()
        Telemetry.initialize(environment: environment)

        SDKLogger(category: "CppBridge").info("All bridges initialized for \(environment)")
    }

    /// Shutdown all C++ bridges
    public static func shutdown() {
        // Shutdown sub-bridges in reverse order
        Telemetry.shutdown()
        Events.unregister()

        lock.lock()
        _isInitialized = false
        lock.unlock()

        SDKLogger(category: "CppBridge").info("All bridges shutdown")
    }
}

// MARK: - Environment Bridge

extension CppBridge {

    /// Environment configuration bridge
    /// Wraps C++ rac_environment.h functions
    public enum Environment {

        /// Convert Swift environment to C++ type
        public static func toC(_ env: SDKEnvironment) -> rac_environment_t {
            switch env {
            case .development: return RAC_ENV_DEVELOPMENT
            case .staging: return RAC_ENV_STAGING
            case .production: return RAC_ENV_PRODUCTION
            }
        }

        /// Convert C++ environment to Swift type
        public static func fromC(_ env: rac_environment_t) -> SDKEnvironment {
            switch env {
            case RAC_ENV_DEVELOPMENT: return .development
            case RAC_ENV_STAGING: return .staging
            case RAC_ENV_PRODUCTION: return .production
            default: return .development
            }
        }

        /// Check if environment requires authentication
        public static func requiresAuth(_ env: SDKEnvironment) -> Bool {
            return rac_env_requires_auth(toC(env))
        }

        /// Check if environment requires backend URL
        public static func requiresBackendURL(_ env: SDKEnvironment) -> Bool {
            return rac_env_requires_backend_url(toC(env))
        }

        /// Validate API key for environment
        public static func validateAPIKey(_ key: String, for env: SDKEnvironment) -> rac_validation_result_t {
            return key.withCString { rac_validate_api_key($0, toC(env)) }
        }

        /// Validate base URL for environment
        public static func validateBaseURL(_ url: String, for env: SDKEnvironment) -> rac_validation_result_t {
            return url.withCString { rac_validate_base_url($0, toC(env)) }
        }

        /// Get validation error message
        public static func validationErrorMessage(_ result: rac_validation_result_t) -> String {
            return String(cString: rac_validation_error_message(result))
        }
    }
}

// MARK: - Development Config Bridge

extension CppBridge {

    /// Development configuration bridge
    /// Wraps C++ rac_dev_config.h functions
    /// Used for development mode with Supabase backend
    public enum DevConfig {

        /// Check if development config is available
        public static var isAvailable: Bool {
            rac_dev_config_is_available()
        }

        /// Get Supabase URL for development mode
        public static var supabaseURL: String? {
            guard isAvailable else { return nil }
            guard let ptr = rac_dev_config_get_supabase_url() else { return nil }
            return String(cString: ptr)
        }

        /// Get Supabase API key for development mode
        public static var supabaseKey: String? {
            guard isAvailable else { return nil }
            guard let ptr = rac_dev_config_get_supabase_key() else { return nil }
            return String(cString: ptr)
        }

        /// Get build token for development mode
        public static var buildToken: String? {
            guard rac_dev_config_has_build_token() else { return nil }
            guard let ptr = rac_dev_config_get_build_token() else { return nil }
            return String(cString: ptr)
        }

        /// Get Sentry DSN for crash reporting (optional)
        public static var sentryDSN: String? {
            guard let ptr = rac_dev_config_get_sentry_dsn() else { return nil }
            return String(cString: ptr)
        }

        /// Configure CppBridge.HTTP for development mode using C++ config
        /// - Returns: true if configured successfully, false if config not available
        @discardableResult
        public static func configureHTTP() async -> Bool {
            guard let urlString = supabaseURL,
                  let url = URL(string: urlString),
                  let apiKey = supabaseKey else {
                return false
            }
            await CppBridge.HTTP.shared.configure(baseURL: url, apiKey: apiKey)
            return true
        }
    }
}

// MARK: - Endpoints Bridge

extension CppBridge {

    /// API endpoint paths bridge
    /// Wraps C++ rac_endpoints.h macros and functions
    public enum Endpoints {

        // Static endpoint strings (from C macros)
        public static let authenticate = RAC_ENDPOINT_AUTHENTICATE
        public static let refresh = RAC_ENDPOINT_REFRESH
        public static let health = RAC_ENDPOINT_HEALTH

        /// Get device registration endpoint for environment
        public static func deviceRegistration(for env: SDKEnvironment) -> String {
            return String(cString: rac_endpoint_device_registration(Environment.toC(env)))
        }

        /// Get telemetry endpoint for environment
        public static func telemetry(for env: SDKEnvironment) -> String {
            return String(cString: rac_endpoint_telemetry(Environment.toC(env)))
        }

        /// Get model assignments endpoint
        public static func modelAssignments(deviceType: String, platform: String) -> String {
            var buffer = [CChar](repeating: 0, count: 512)
            deviceType.withCString { dt in
                platform.withCString { plat in
                    _ = rac_endpoint_model_assignments(dt, plat, &buffer, buffer.count)
                }
            }
            return String(cString: buffer)
        }

        /// Get model download endpoint
        public static func modelDownload(modelId: String) -> String {
            var buffer = [CChar](repeating: 0, count: 512)
            modelId.withCString { mid in
                _ = rac_endpoint_model_download(mid, &buffer, buffer.count)
            }
            return String(cString: buffer)
        }
    }
}

// MARK: - Events Bridge

extension CppBridge {

    /// Analytics events bridge
    /// Receives events from C++ and routes to Swift + Telemetry
    public enum Events {

        private static var isRegistered = false

        /// Register C++ event callback
        static func register() {
            guard !isRegistered else { return }

            let result = rac_analytics_events_set_callback(eventCallback, nil)
            if result == RAC_SUCCESS {
                isRegistered = true
                SDKLogger(category: "CppBridge.Events").debug("Registered C++ event callback")
            }
        }

        /// Unregister C++ event callback
        static func unregister() {
            guard isRegistered else { return }
            _ = rac_analytics_events_set_callback(nil, nil)
            isRegistered = false
        }
    }
}

/// C callback for analytics events
private func eventCallback(
    type: rac_event_type_t,
    data: UnsafePointer<rac_analytics_event_data_t>?,
    userData: UnsafeMutableRawPointer?
) {
    guard let data = data else { return }

    // Forward to telemetry (C++ builds JSON, calls HTTP)
    CppBridge.Telemetry.trackAnalyticsEvent(type: type, data: data)

    // Also publish to Swift EventPublisher (for app developers)
    publishToSwiftEventPublisher(type: type, data: data)
}

// MARK: - Telemetry Bridge

extension CppBridge {

    /// Telemetry bridge
    /// C++ handles JSON building, batching; Swift handles HTTP
    public enum Telemetry {

        private static var manager: OpaquePointer?
        private static let lock = NSLock()

        /// Initialize telemetry manager
        static func initialize(environment: SDKEnvironment) {
            lock.lock()
            defer { lock.unlock() }

            // Destroy existing if any
            if let existing = manager {
                rac_telemetry_manager_destroy(existing)
            }

            let deviceId = DeviceIdentity.persistentUUID
            let deviceInfo = DeviceInfo.current

            manager = deviceId.withCString { did in
                SDKConstants.platform.withCString { plat in
                    SDKConstants.version.withCString { ver in
                        rac_telemetry_manager_create(Environment.toC(environment), did, plat, ver)
                    }
                }
            }

            // Set device info
            deviceInfo.deviceModel.withCString { model in
                deviceInfo.osVersion.withCString { os in
                    rac_telemetry_manager_set_device_info(manager, model, os)
                }
            }

            // Register HTTP callback
            let userData = Unmanaged.passUnretained(Telemetry.self as AnyObject).toOpaque()
            rac_telemetry_manager_set_http_callback(manager, telemetryHttpCallback, userData)
        }

        /// Shutdown telemetry manager
        static func shutdown() {
            lock.lock()
            defer { lock.unlock() }

            if let mgr = manager {
                rac_telemetry_manager_flush(mgr)
                rac_telemetry_manager_destroy(mgr)
                manager = nil
            }
        }

        /// Track analytics event from C++
        static func trackAnalyticsEvent(
            type: rac_event_type_t,
            data: UnsafePointer<rac_analytics_event_data_t>
        ) {
            lock.lock()
            let mgr = manager
            lock.unlock()

            guard let mgr = mgr else { return }
            rac_telemetry_manager_track_analytics(mgr, type, data)
        }

        /// Flush pending events
        public static func flush() {
            lock.lock()
            let mgr = manager
            lock.unlock()

            guard let mgr = mgr else { return }
            rac_telemetry_manager_flush(mgr)
        }
    }
}

/// HTTP callback for telemetry
private func telemetryHttpCallback(
    userData: UnsafeMutableRawPointer?,
    endpoint: UnsafePointer<CChar>?,
    jsonBody: UnsafePointer<CChar>?,
    jsonLength: Int,
    requiresAuth: rac_bool_t
) {
    guard let endpoint = endpoint, let jsonBody = jsonBody else { return }

    let path = String(cString: endpoint)
    let json = String(cString: jsonBody)
    let needsAuth = requiresAuth == RAC_TRUE

    Task {
        await performTelemetryHTTP(path: path, json: json, requiresAuth: needsAuth)
    }
}

private func performTelemetryHTTP(path: String, json: String, requiresAuth: Bool) async {
    do {
        _ = try await CppBridge.HTTP.shared.post(path, json: json, requiresAuth: requiresAuth)
    } catch {
        SDKLogger(category: "CppBridge.Telemetry").warning("HTTP failed: \(error)")
    }
}

// MARK: - Device Bridge

extension CppBridge {

    /// Device registration bridge
    /// C++ builds JSON; Swift provides device info + HTTP
    public enum Device {

        /// Build device registration JSON via C++
        public static func buildRegistrationJSON(buildToken: String? = nil) -> String? {
            let deviceInfo = DeviceInfo.current
            let deviceId = DeviceIdentity.persistentUUID
            let env = CppBridge.environment

            #if targetEnvironment(simulator)
            let isSimulator = true
            #else
            let isSimulator = false
            #endif

            var request = rac_device_registration_request_t()
            var cDeviceInfo = rac_device_registration_info_t()

            return deviceId.withCString { did in
                deviceInfo.deviceType.withCString { dtype in
                    deviceInfo.deviceModel.withCString { dmodel in
                        "iOS".withCString { osName in
                            deviceInfo.osVersion.withCString { osVer in
                                deviceInfo.platform.withCString { plat in
                                    SDKConstants.version.withCString { sdkVer in
                                        (buildToken ?? "").withCString { token in

                                            cDeviceInfo.device_id = did
                                            cDeviceInfo.device_type = dtype
                                            cDeviceInfo.device_model = dmodel
                                            cDeviceInfo.os_name = osName
                                            cDeviceInfo.os_version = osVer
                                            cDeviceInfo.platform = plat
                                            cDeviceInfo.total_memory_bytes = Int64(deviceInfo.totalMemory)
                                            cDeviceInfo.available_memory_bytes = Int64(deviceInfo.availableMemory)
                                            cDeviceInfo.processor_count = Int32(deviceInfo.coreCount)
                                            cDeviceInfo.is_simulator = isSimulator ? RAC_TRUE : RAC_FALSE

                                            request.device_info = cDeviceInfo
                                            request.sdk_version = sdkVer
                                            request.build_token = buildToken != nil ? token : nil
                                            request.last_seen_at_ms = Int64(Date().timeIntervalSince1970 * 1000)

                                            var jsonPtr: UnsafeMutablePointer<CChar>?
                                            var jsonLen: Int = 0

                                            let result = rac_device_registration_to_json(
                                                &request,
                                                Environment.toC(env),
                                                &jsonPtr,
                                                &jsonLen
                                            )

                                            if result == RAC_SUCCESS, let json = jsonPtr {
                                                let jsonString = String(cString: json)
                                                free(json)
                                                return jsonString
                                            }
                                            return nil
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        /// Register device with backend
        public static func register(buildToken: String? = nil) async throws {
            guard await CppBridge.HTTP.shared.isConfigured else {
                throw SDKError.network(.serviceNotAvailable, "HTTP not configured")
            }

            guard let json = buildRegistrationJSON(buildToken: buildToken) else {
                throw SDKError.general(.validationFailed, "Failed to build registration JSON")
            }

            let endpoint = Endpoints.deviceRegistration(for: CppBridge.environment)
            let requiresAuth = Environment.requiresAuth(CppBridge.environment)

            _ = try await CppBridge.HTTP.shared.post(endpoint, json: json, requiresAuth: requiresAuth)
        }
    }
}

// MARK: - State Bridge (Centralized SDK State)

extension CppBridge {

    /// SDK State bridge - centralized state management in C++
    /// C++ owns runtime state; Swift handles persistence (Keychain)
    public enum State {

        private static var persistenceRegistered = false

        // MARK: - Initialization

        /// Initialize C++ state manager
        /// - Parameters:
        ///   - environment: SDK environment
        ///   - apiKey: API key
        ///   - baseURL: Base URL
        ///   - deviceId: Persistent device ID
        public static func initialize(
            environment: SDKEnvironment,
            apiKey: String,
            baseURL: URL,
            deviceId: String
        ) {
            apiKey.withCString { key in
                baseURL.absoluteString.withCString { url in
                    deviceId.withCString { did in
                        _ = rac_state_initialize(
                            Environment.toC(environment),
                            key,
                            url,
                            did
                        )
                    }
                }
            }

            // Register Keychain persistence callbacks
            registerPersistenceCallbacks()

            // Load any stored tokens from Keychain into C++ state
            loadStoredAuth()

            SDKLogger(category: "CppBridge.State").debug("C++ state initialized")
        }

        /// Check if state is initialized
        public static var isInitialized: Bool {
            rac_state_is_initialized()
        }

        /// Reset state (for testing)
        public static func reset() {
            rac_state_reset()
        }

        /// Shutdown state manager
        public static func shutdown() {
            rac_state_shutdown()
            persistenceRegistered = false
        }

        // MARK: - Environment Queries

        /// Get current environment from C++ state
        public static var environment: SDKEnvironment {
            Environment.fromC(rac_state_get_environment())
        }

        /// Get base URL from C++ state
        public static var baseURL: String? {
            guard let ptr = rac_state_get_base_url() else { return nil }
            let str = String(cString: ptr)
            return str.isEmpty ? nil : str
        }

        /// Get API key from C++ state
        public static var apiKey: String? {
            guard let ptr = rac_state_get_api_key() else { return nil }
            let str = String(cString: ptr)
            return str.isEmpty ? nil : str
        }

        /// Get device ID from C++ state
        public static var deviceId: String? {
            guard let ptr = rac_state_get_device_id() else { return nil }
            let str = String(cString: ptr)
            return str.isEmpty ? nil : str
        }

        // MARK: - Auth State

        /// Set authentication state after successful HTTP auth
        /// - Parameters:
        ///   - accessToken: Access token
        ///   - refreshToken: Refresh token
        ///   - expiresAt: Token expiry date
        ///   - userId: User ID (nullable)
        ///   - organizationId: Organization ID
        ///   - deviceId: Device ID from response
        public static func setAuth(
            accessToken: String,
            refreshToken: String,
            expiresAt: Date,
            userId: String?,
            organizationId: String,
            deviceId: String
        ) {
            let expiresAtUnix = Int64(expiresAt.timeIntervalSince1970)

            accessToken.withCString { access in
                refreshToken.withCString { refresh in
                    organizationId.withCString { org in
                        deviceId.withCString { did in
                            var authData = rac_auth_data_t(
                                access_token: access,
                                refresh_token: refresh,
                                expires_at_unix: expiresAtUnix,
                                user_id: nil,
                                organization_id: org,
                                device_id: did
                            )

                            if let userId = userId {
                                userId.withCString { user in
                                    authData.user_id = user
                                    _ = rac_state_set_auth(&authData)
                                }
                            } else {
                                _ = rac_state_set_auth(&authData)
                            }
                        }
                    }
                }
            }

            SDKLogger(category: "CppBridge.State").debug("Auth state set in C++")
        }

        /// Get access token from C++ state
        public static var accessToken: String? {
            guard let ptr = rac_state_get_access_token() else { return nil }
            return String(cString: ptr)
        }

        /// Get refresh token from C++ state
        public static var refreshToken: String? {
            guard let ptr = rac_state_get_refresh_token() else { return nil }
            return String(cString: ptr)
        }

        /// Check if authenticated (valid non-expired token)
        public static var isAuthenticated: Bool {
            rac_state_is_authenticated()
        }

        /// Check if token needs refresh
        public static var tokenNeedsRefresh: Bool {
            rac_state_token_needs_refresh()
        }

        /// Get token expiry timestamp
        public static var tokenExpiresAt: Date? {
            let unix = rac_state_get_token_expires_at()
            return unix > 0 ? Date(timeIntervalSince1970: TimeInterval(unix)) : nil
        }

        /// Get user ID from C++ state
        public static var userId: String? {
            guard let ptr = rac_state_get_user_id() else { return nil }
            return String(cString: ptr)
        }

        /// Get organization ID from C++ state
        public static var organizationId: String? {
            guard let ptr = rac_state_get_organization_id() else { return nil }
            return String(cString: ptr)
        }

        /// Clear authentication state
        public static func clearAuth() {
            rac_state_clear_auth()
            SDKLogger(category: "CppBridge.State").debug("Auth state cleared")
        }

        // MARK: - Device State

        /// Set device registration status
        public static func setDeviceRegistered(_ registered: Bool) {
            rac_state_set_device_registered(registered)
        }

        /// Check if device is registered
        public static var isDeviceRegistered: Bool {
            rac_state_is_device_registered()
        }

        // MARK: - Persistence (Keychain Integration)

        /// Register Keychain persistence callbacks with C++
        private static func registerPersistenceCallbacks() {
            guard !persistenceRegistered else { return }

            rac_state_set_persistence_callbacks(
                keychainPersistCallback,
                keychainLoadCallback,
                nil
            )

            persistenceRegistered = true
        }

        /// Load stored auth from Keychain into C++ state
        private static func loadStoredAuth() {
            // Load tokens from Keychain
            guard let accessToken = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.accessToken"),
                  let refreshToken = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.refreshToken") else {
                return
            }

            // Load additional fields
            let userId = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.userId")
            let orgId = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.organizationId")
            let deviceIdStored = try? KeychainManager.shared.retrieve(for: "com.runanywhere.sdk.deviceId")

            // Set in C++ state (use a far-future expiry for loaded tokens - they'll be refreshed if needed)
            accessToken.withCString { access in
                refreshToken.withCString { refresh in
                    (orgId ?? "").withCString { org in
                        (deviceIdStored ?? DeviceIdentity.persistentUUID).withCString { did in
                            var authData = rac_auth_data_t(
                                access_token: access,
                                refresh_token: refresh,
                                expires_at_unix: 0, // Unknown - will check via API
                                user_id: nil,
                                organization_id: org,
                                device_id: did
                            )

                            if let userId = userId {
                                userId.withCString { user in
                                    authData.user_id = user
                                    _ = rac_state_set_auth(&authData)
                                }
                            } else {
                                _ = rac_state_set_auth(&authData)
                            }
                        }
                    }
                }
            }

            SDKLogger(category: "CppBridge.State").debug("Loaded stored auth from Keychain")
        }
    }
}

// MARK: - HTTP Bridge (Unified HTTP Transport)

extension CppBridge {

    /// HTTP transport bridge - unified URLSession wrapper
    /// Conforms to NetworkService for compatibility with existing code
    /// Replaces APIClient for all HTTP operations
    public actor HTTP: NetworkService {

        /// Shared HTTP instance
        public static let shared = HTTP()

        private var session: URLSession
        private var baseURL: URL?
        private var apiKey: String?
        private let logger = SDKLogger(category: "CppBridge.HTTP")

        private init() {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30.0
            config.httpAdditionalHeaders = [
                "Content-Type": "application/json",
                "X-SDK-Client": "RunAnywhereSDK",
                "X-SDK-Version": SDKConstants.version,
                "X-Platform": SDKConstants.platform
            ]
            self.session = URLSession(configuration: config)
        }

        /// Configure HTTP with base URL and API key
        public func configure(baseURL: URL, apiKey: String) {
            self.baseURL = baseURL
            self.apiKey = apiKey

            // Update session with API key header
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30.0
            config.httpAdditionalHeaders = [
                "Content-Type": "application/json",
                "X-SDK-Client": "RunAnywhereSDK",
                "X-SDK-Version": SDKConstants.version,
                "X-Platform": SDKConstants.platform,
                "apikey": apiKey,
                "Prefer": "return=representation"
            ]
            self.session = URLSession(configuration: config)
        }

        /// Check if HTTP is configured
        public var isConfigured: Bool {
            baseURL != nil
        }

        // MARK: - NetworkService Protocol

        /// POST request with raw Data body (NetworkService protocol)
        public func postRaw(
            _ path: String,
            _ payload: Data,
            requiresAuth: Bool
        ) async throws -> Data {
            guard let baseURL = baseURL else {
                throw SDKError.network(.serviceNotAvailable, "HTTP not configured")
            }

            let url = baseURL.appendingPathComponent(path)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = payload

            let token = try await resolveToken(requiresAuth: requiresAuth)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            return try await execute(request, url: url)
        }

        /// GET request with raw response (NetworkService protocol)
        public func getRaw(
            _ path: String,
            requiresAuth: Bool
        ) async throws -> Data {
            guard let baseURL = baseURL else {
                throw SDKError.network(.serviceNotAvailable, "HTTP not configured")
            }

            let url = baseURL.appendingPathComponent(path)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let token = try await resolveToken(requiresAuth: requiresAuth)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            return try await execute(request, url: url)
        }

        // MARK: - JSON Convenience Methods

        /// POST request with JSON string body
        public func post(_ path: String, json: String, requiresAuth: Bool = false) async throws -> Data {
            guard let data = json.data(using: .utf8) else {
                throw SDKError.general(.validationFailed, "Invalid JSON string")
            }
            return try await postRaw(path, data, requiresAuth: requiresAuth)
        }

        // MARK: - Private Helpers

        private func resolveToken(requiresAuth: Bool) async throws -> String {
            if requiresAuth {
                // Get token from C++ state, refreshing if needed
                if let token = CppBridge.State.accessToken, !CppBridge.State.tokenNeedsRefresh {
                    return token
                }
                // Try refresh if we have refresh token
                if CppBridge.State.refreshToken != nil {
                    try await CppBridge.Auth.refreshToken()
                    if let token = CppBridge.State.accessToken {
                        return token
                    }
                }
                throw SDKError.authentication(.authenticationFailed, "No valid token")
            }
            // Use API key for non-auth requests
            return apiKey ?? ""
        }

        private func execute(_ request: URLRequest, url: URL) async throws -> Data {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SDKError.network(.invalidResponse, "Invalid HTTP response")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let error = CppBridge.Auth.parseAPIError(
                    statusCode: Int32(httpResponse.statusCode),
                    body: data,
                    url: url.absoluteString
                )
                logger.error("HTTP \(httpResponse.statusCode): \(url)")
                throw error
            }

            return data
        }
    }
}

// MARK: - Auth Bridge (Complete Auth Flow)

extension CppBridge {

    /// Complete authentication bridge
    /// Handles full auth flow: JSON building, HTTP, parsing, state storage
    public enum Auth {

        private static let logger = SDKLogger(category: "CppBridge.Auth")

        // MARK: - Complete Auth Flow

        /// Authenticate with backend
        /// - Parameter apiKey: API key for authentication
        /// - Returns: Authentication response
        /// - Throws: SDKError on failure
        @discardableResult
        public static func authenticate(apiKey: String) async throws -> AuthenticationResponse {
            let deviceId = DeviceIdentity.persistentUUID

            // 1. Build request JSON via C++
            guard let json = buildAuthenticateRequestJSON(
                apiKey: apiKey,
                deviceId: deviceId,
                platform: SDKConstants.platform,
                sdkVersion: SDKConstants.version
            ) else {
                throw SDKError.general(.validationFailed, "Failed to build auth request")
            }

            logger.info("Starting authentication...")

            // 2. Make HTTP request
            let responseData = try await HTTP.shared.post(
                RAC_ENDPOINT_AUTHENTICATE,
                json: json,
                requiresAuth: false
            )

            // 3. Parse response via Codable
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(AuthenticationResponse.self, from: responseData)

            // 4. Store in C++ state
            let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))
            State.setAuth(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: expiresAt,
                userId: response.userId,
                organizationId: response.organizationId,
                deviceId: response.deviceId
            )

            // 5. Store in Keychain
            try storeTokensInKeychain(response)

            logger.info("Authentication successful")
            return response
        }

        /// Refresh access token
        /// - Returns: New access token
        /// - Throws: SDKError on failure
        @discardableResult
        public static func refreshToken() async throws -> String {
            guard let refreshToken = State.refreshToken else {
                throw SDKError.authentication(.invalidAPIKey, "No refresh token")
            }

            guard let deviceId = State.deviceId else {
                throw SDKError.authentication(.authenticationFailed, "No device ID")
            }

            // 1. Build refresh request JSON via C++
            guard let json = buildRefreshRequestJSON(deviceId: deviceId, refreshToken: refreshToken) else {
                throw SDKError.general(.validationFailed, "Failed to build refresh request")
            }

            logger.debug("Refreshing access token...")

            // 2. Make HTTP request
            let responseData = try await HTTP.shared.post(
                RAC_ENDPOINT_REFRESH,
                json: json,
                requiresAuth: false
            )

            // 3. Parse response
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(AuthenticationResponse.self, from: responseData)

            // 4. Store in C++ state
            let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))
            State.setAuth(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: expiresAt,
                userId: response.userId,
                organizationId: response.organizationId,
                deviceId: response.deviceId
            )

            // 5. Store in Keychain
            try storeTokensInKeychain(response)

            logger.info("Token refresh successful")
            return response.accessToken
        }

        /// Get valid access token (refresh if needed)
        /// - Returns: Valid access token
        /// - Throws: SDKError if no valid token available
        public static func getAccessToken() async throws -> String {
            // Check if current token is valid
            if let token = State.accessToken, !State.tokenNeedsRefresh {
                return token
            }

            // Try to refresh
            if State.refreshToken != nil {
                return try await refreshToken()
            }

            throw SDKError.authentication(.authenticationFailed, "No valid token")
        }

        /// Clear authentication state
        public static func clearAuth() throws {
            // Clear C++ state
            State.clearAuth()

            // Clear Keychain
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.accessToken")
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.refreshToken")
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.deviceId")
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.userId")
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.organizationId")

            logger.info("Authentication cleared")
        }

        /// Check if currently authenticated
        public static var isAuthenticated: Bool {
            State.isAuthenticated
        }

        // MARK: - Keychain Storage

        private static func storeTokensInKeychain(_ response: AuthenticationResponse) throws {
            try KeychainManager.shared.store(response.accessToken, for: "com.runanywhere.sdk.accessToken")
            try KeychainManager.shared.store(response.refreshToken, for: "com.runanywhere.sdk.refreshToken")
            try KeychainManager.shared.store(response.deviceId, for: "com.runanywhere.sdk.deviceId")
            if let userId = response.userId {
                try KeychainManager.shared.store(userId, for: "com.runanywhere.sdk.userId")
            }
            try KeychainManager.shared.store(response.organizationId, for: "com.runanywhere.sdk.organizationId")
        }

        // MARK: - JSON Building (existing methods)

        /// Build authentication request JSON via C++
        /// - Parameters:
        ///   - apiKey: API key
        ///   - deviceId: Device ID
        ///   - platform: Platform string (e.g., "ios")
        ///   - sdkVersion: SDK version string
        /// - Returns: JSON string for POST body, or nil on error
        public static func buildAuthenticateRequestJSON(
            apiKey: String,
            deviceId: String,
            platform: String,
            sdkVersion: String
        ) -> String? {
            return apiKey.withCString { key in
                deviceId.withCString { did in
                    platform.withCString { plat in
                        sdkVersion.withCString { ver in
                            var request = rac_auth_request_t(
                                api_key: key,
                                device_id: did,
                                platform: plat,
                                sdk_version: ver
                            )

                            guard let jsonPtr = rac_auth_request_to_json(&request) else {
                                return nil
                            }

                            let json = String(cString: jsonPtr)
                            free(jsonPtr)
                            return json
                        }
                    }
                }
            }
        }

        /// Build refresh token request JSON via C++
        /// - Parameters:
        ///   - deviceId: Device ID
        ///   - refreshToken: Refresh token
        /// - Returns: JSON string for POST body, or nil on error
        public static func buildRefreshRequestJSON(
            deviceId: String,
            refreshToken: String
        ) -> String? {
            return deviceId.withCString { did in
                refreshToken.withCString { token in
                    var request = rac_refresh_request_t(
                        device_id: did,
                        refresh_token: token
                    )

                    guard let jsonPtr = rac_refresh_request_to_json(&request) else {
                        return nil
                    }

                    let json = String(cString: jsonPtr)
                    free(jsonPtr)
                    return json
                }
            }
        }

        /// Parse API error from HTTP response via C++
        /// - Parameters:
        ///   - statusCode: HTTP status code
        ///   - body: Response body data
        ///   - url: Request URL
        /// - Returns: SDKError with appropriate category and message
        public static func parseAPIError(
            statusCode: Int32,
            body: Data?,
            url: String?
        ) -> SDKError {
            let bodyString = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let urlString = url ?? ""

            var error = rac_api_error_t()

            let result = bodyString.withCString { bodyPtr in
                urlString.withCString { urlPtr in
                    rac_api_error_from_response(statusCode, bodyPtr, urlPtr, &error)
                }
            }

            defer {
                rac_api_error_free(&error)
            }

            // Use C++ parsed message, or fallback
            let message: String
            if result == 0, let msgPtr = error.message {
                message = String(cString: msgPtr)
            } else {
                message = "HTTP \(statusCode)"
            }

            // Map status code to SDKError category
            switch statusCode {
            case 401:
                return SDKError.network(.unauthorized, message)
            case 403:
                return SDKError.network(.forbidden, message)
            case 404:
                return SDKError.network(.invalidResponse, message)
            case 408, 504:
                return SDKError.network(.timeout, message)
            case 422:
                return SDKError.network(.validationFailed, message)
            case 400..<500:
                return SDKError.network(.httpError, "Client error \(statusCode): \(message)")
            case 500..<600:
                return SDKError.network(.serverError, "Server error \(statusCode): \(message)")
            default:
                return SDKError.network(.unknown, "\(message) (status: \(statusCode))")
            }
        }
    }
}

// MARK: - Services Bridge (Service Registry Queries)

extension CppBridge {

    /// Bridge for querying the C++ service registry
    /// Provides runtime discovery of registered modules and service providers
    public enum Services {

        /// Registered provider info
        public struct ProviderInfo { // swiftlint:disable:this nesting
            public let name: String
            public let capability: SDKComponent
            public let priority: Int
        }

        /// Registered module info
        public struct ModuleInfo { // swiftlint:disable:this nesting
            public let id: String
            public let name: String
            public let version: String
            public let capabilities: Set<SDKComponent>
        }

        // MARK: - Provider Queries

        /// List all providers for a capability
        /// - Parameter capability: The capability to query (llm, stt, tts, vad)
        /// - Returns: Array of provider names sorted by priority (highest first)
        public static func listProviders(for capability: SDKComponent) -> [String] {
            let cCapability = capability.toC()

            var namesPtr: UnsafeMutablePointer<UnsafePointer<CChar>?>?
            var count: Int = 0

            let result = rac_service_list_providers(cCapability, &namesPtr, &count)
            guard result == RAC_SUCCESS, let names = namesPtr else {
                return []
            }

            var providers: [String] = []
            for i in 0..<count {
                if let name = names[i] {
                    providers.append(String(cString: name))
                }
            }

            return providers
        }

        /// Check if any provider is registered for a capability
        public static func hasProvider(for capability: SDKComponent) -> Bool {
            !listProviders(for: capability).isEmpty
        }

        /// Check if a specific provider is registered
        public static func isProviderRegistered(_ name: String, for capability: SDKComponent) -> Bool {
            listProviders(for: capability).contains(name)
        }

        // MARK: - Module Queries

        /// List all registered modules
        /// - Returns: Array of module info
        public static func listModules() -> [ModuleInfo] {
            var modulesPtr: UnsafePointer<rac_module_info_t>?
            var count: Int = 0

            let result = rac_module_list(&modulesPtr, &count)
            guard result == RAC_SUCCESS, let modules = modulesPtr else {
                return []
            }

            var moduleInfos: [ModuleInfo] = []
            for i in 0..<count {
                let module = modules[i]

                var capabilities: Set<SDKComponent> = []
                if let caps = module.capabilities {
                    for j in 0..<Int(module.num_capabilities) {
                        if let component = SDKComponent.from(caps[j]) {
                            capabilities.insert(component)
                        }
                    }
                }

                moduleInfos.append(ModuleInfo(
                    id: module.id.map { String(cString: $0) } ?? "",
                    name: module.name.map { String(cString: $0) } ?? "",
                    version: module.version.map { String(cString: $0) } ?? "",
                    capabilities: capabilities
                ))
            }

            return moduleInfos
        }

        /// Get info for a specific module
        public static func getModule(_ moduleId: String) -> ModuleInfo? {
            var modulePtr: UnsafePointer<rac_module_info_t>?

            let result = moduleId.withCString { idPtr in
                rac_module_get_info(idPtr, &modulePtr)
            }

            guard result == RAC_SUCCESS, let module = modulePtr?.pointee else {
                return nil
            }

            var capabilities: Set<SDKComponent> = []
            if let caps = module.capabilities {
                for j in 0..<Int(module.num_capabilities) {
                    if let component = SDKComponent.from(caps[j]) {
                        capabilities.insert(component)
                    }
                }
            }

            return ModuleInfo(
                id: module.id.map { String(cString: $0) } ?? "",
                name: module.name.map { String(cString: $0) } ?? "",
                version: module.version.map { String(cString: $0) } ?? "",
                capabilities: capabilities
            )
        }

        /// Check if a module is registered
        public static func isModuleRegistered(_ moduleId: String) -> Bool {
            getModule(moduleId) != nil
        }

        // MARK: - Platform Service Registration

        /// Context for platform service callbacks
        /// Internal for callback access (C callbacks are outside the extension)
        class PlatformServiceContext { // swiftlint:disable:this nesting
            let canHandle: (String?) -> Bool
            let create: () async throws -> Any // swiftlint:disable:this avoid_any_type
            var instances: [rac_handle_t: Any] = [:] // swiftlint:disable:this avoid_any_type

            init(canHandle: @escaping (String?) -> Bool, create: @escaping () async throws -> Any) {
                self.canHandle = canHandle
                self.create = create
            }
        }

        // Internal for callback access (C callbacks are outside the extension)
        static var platformContexts: [String: PlatformServiceContext] = [:]
        static let platformLock = NSLock()

        /// Register a platform-only service with the C++ registry
        ///
        /// This allows Swift-only services (like SystemTTS, AppleAI) to be registered
        /// with the C++ service registry, making them discoverable alongside C++ backends.
        ///
        /// - Parameters:
        ///   - name: Provider name (e.g., "SystemTTS")
        ///   - capability: Capability this provider offers
        ///   - priority: Priority (higher = preferred)
        ///   - canHandle: Closure to check if provider can handle a request
        ///   - create: Factory closure to create the service
        /// - Returns: true if registration succeeded
        @discardableResult
        public static func registerPlatformService(
            name: String,
            capability: SDKComponent,
            priority: Int,
            canHandle: @escaping (String?) -> Bool,
            create: @escaping () async throws -> Any
        ) -> Bool {
            platformLock.lock()
            defer { platformLock.unlock() }

            // Store context for callbacks
            let context = PlatformServiceContext(canHandle: canHandle, create: create)
            platformContexts[name] = context

            // Create C provider struct
            var provider = rac_service_provider_t()
            provider.capability = capability.toC()
            provider.priority = Int32(priority)

            // Use global callbacks that look up the context by name
            // Note: We store the name as user_data
            let namePtr = strdup(name)
            provider.user_data = UnsafeMutableRawPointer(namePtr)
            provider.can_handle = platformCanHandleCallback
            provider.create = platformCreateCallback

            let result = name.withCString { namePtr in
                provider.name = namePtr
                return rac_service_register_provider(&provider)
            }

            if result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED {
                // Cleanup on failure
                platformContexts.removeValue(forKey: name)
                if let namePtr = provider.user_data?.assumingMemoryBound(to: CChar.self) {
                    free(namePtr)
                }
                return false
            }

            return true
        }

        /// Unregister a platform service
        public static func unregisterPlatformService(name: String, capability: SDKComponent) {
            platformLock.lock()
            defer { platformLock.unlock() }

            platformContexts.removeValue(forKey: name)

            _ = name.withCString { namePtr in
                rac_service_unregister_provider(namePtr, capability.toC())
            }
        }
    }
}

// MARK: - Platform Service Callbacks

/// Callback for checking if platform service can handle request
private func platformCanHandleCallback(
    request: UnsafePointer<rac_service_request_t>?,
    userData: UnsafeMutableRawPointer?
) -> rac_bool_t {
    guard let userData = userData else { return RAC_FALSE }

    let name = String(cString: userData.assumingMemoryBound(to: CChar.self))

    CppBridge.Services.platformLock.lock()
    guard let context = CppBridge.Services.platformContexts[name] else {
        CppBridge.Services.platformLock.unlock()
        return RAC_FALSE
    }
    CppBridge.Services.platformLock.unlock()

    let identifier = request?.pointee.identifier.map { String(cString: $0) }
    return context.canHandle(identifier) ? RAC_TRUE : RAC_FALSE
}

/// Callback for creating platform service
private func platformCreateCallback(
    request: UnsafePointer<rac_service_request_t>?,
    userData: UnsafeMutableRawPointer?
) -> rac_handle_t? {
    guard let userData = userData else { return nil }

    let name = String(cString: userData.assumingMemoryBound(to: CChar.self))

    CppBridge.Services.platformLock.lock()
    guard let context = CppBridge.Services.platformContexts[name] else {
        CppBridge.Services.platformLock.unlock()
        return nil
    }
    CppBridge.Services.platformLock.unlock()

    // Platform services are Swift objects - we return a dummy handle
    // The actual service is stored in the context and managed by Swift
    // This is a bridge pattern - C++ tracks that a service exists,
    // but Swift manages the actual instance
    return UnsafeMutableRawPointer(bitPattern: 0xDEADBEEF)  // Marker handle
}

// MARK: - SDKComponent C++ Conversion

extension SDKComponent {

    /// Convert to C++ capability type
    func toC() -> rac_capability_t {
        switch self {
        case .llm:
            return RAC_CAPABILITY_TEXT_GENERATION
        case .stt:
            return RAC_CAPABILITY_STT
        case .tts:
            return RAC_CAPABILITY_TTS
        case .vad:
            return RAC_CAPABILITY_VAD
        case .voice:
            // Voice agent uses multiple capabilities, default to text generation
            return RAC_CAPABILITY_TEXT_GENERATION
        case .embedding:
            // Embeddings use text generation capability
            return RAC_CAPABILITY_TEXT_GENERATION
        }
    }

    /// Convert from C++ capability type
    static func from(_ capability: rac_capability_t) -> SDKComponent? {
        switch capability {
        case RAC_CAPABILITY_TEXT_GENERATION:
            return .llm
        case RAC_CAPABILITY_STT:
            return .stt
        case RAC_CAPABILITY_TTS:
            return .tts
        case RAC_CAPABILITY_VAD:
            return .vad
        default:
            return nil
        }
    }
}

// MARK: - Keychain Persistence Callbacks

/// C callback for persisting state to Keychain
private func keychainPersistCallback(
    key: UnsafePointer<CChar>?,
    value: UnsafePointer<CChar>?,
    userData: UnsafeMutableRawPointer?
) {
    guard let key = key else { return }
    let keyString = String(cString: key)

    // Map C++ keys to Keychain keys
    let keychainKey: String
    switch keyString {
    case "access_token":
        keychainKey = "com.runanywhere.sdk.accessToken"
    case "refresh_token":
        keychainKey = "com.runanywhere.sdk.refreshToken"
    default:
        return // Ignore unknown keys
    }

    if let value = value {
        // Store value
        let valueString = String(cString: value)
        try? KeychainManager.shared.store(valueString, for: keychainKey)
    } else {
        // Delete value
        try? KeychainManager.shared.delete(for: keychainKey)
    }
}

/// C callback for loading state from Keychain
private func keychainLoadCallback(
    key: UnsafePointer<CChar>?,
    userData: UnsafeMutableRawPointer?
) -> UnsafePointer<CChar>? {
    guard let key = key else { return nil }
    let keyString = String(cString: key)

    // Map C++ keys to Keychain keys
    let keychainKey: String
    switch keyString {
    case "access_token":
        keychainKey = "com.runanywhere.sdk.accessToken"
    case "refresh_token":
        keychainKey = "com.runanywhere.sdk.refreshToken"
    default:
        return nil
    }

    // Load from Keychain
    // Note: This returns a pointer that C++ should NOT free
    // The Swift string's memory is managed by Swift
    guard let value = try? KeychainManager.shared.retrieve(for: keychainKey) else {
        return nil
    }

    // This is a workaround - we return a static buffer
    // In practice, C++ should call this during init only
    return nil // For now, we load manually via loadStoredAuth()
}

// MARK: - Helper to publish to Swift EventPublisher

/// Publish C++ event to Swift EventPublisher for app developers
private func publishToSwiftEventPublisher(
    type: rac_event_type_t,
    data: UnsafePointer<rac_analytics_event_data_t>
) {
    // Convert C++ event to Swift event and publish
    // (This is the existing CppEventBridge logic)

    switch type {
    case RAC_EVENT_LLM_GENERATION_STARTED,
         RAC_EVENT_LLM_GENERATION_COMPLETED,
         RAC_EVENT_LLM_GENERATION_FAILED,
         RAC_EVENT_LLM_FIRST_TOKEN,
         RAC_EVENT_LLM_STREAMING_UPDATE,
         RAC_EVENT_LLM_MODEL_LOAD_STARTED,
         RAC_EVENT_LLM_MODEL_LOAD_COMPLETED,
         RAC_EVENT_LLM_MODEL_LOAD_FAILED,
         RAC_EVENT_LLM_MODEL_UNLOADED:
        publishLLMEvent(type: type, data: data)

    case RAC_EVENT_STT_TRANSCRIPTION_STARTED,
         RAC_EVENT_STT_TRANSCRIPTION_COMPLETED,
         RAC_EVENT_STT_TRANSCRIPTION_FAILED:
        publishSTTEvent(type: type, data: data)

    case RAC_EVENT_TTS_SYNTHESIS_STARTED,
         RAC_EVENT_TTS_SYNTHESIS_COMPLETED,
         RAC_EVENT_TTS_SYNTHESIS_FAILED:
        publishTTSEvent(type: type, data: data)

    case RAC_EVENT_VAD_STARTED,
         RAC_EVENT_VAD_STOPPED,
         RAC_EVENT_VAD_SPEECH_STARTED,
         RAC_EVENT_VAD_SPEECH_ENDED:
        publishVADEvent(type: type, data: data)

    default:
        break
    }
}

// MARK: - InferenceFramework C++ Conversion

extension InferenceFramework {
    /// Initialize from C++ rac_inference_framework_t
    init(from cppFramework: rac_inference_framework_t) {
        switch cppFramework {
        case RAC_FRAMEWORK_LLAMACPP:
            self = .llamaCpp
        case RAC_FRAMEWORK_ONNX:
            self = .onnx
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            self = .foundationModels
        case RAC_FRAMEWORK_SYSTEM_TTS:
            self = .systemTTS
        case RAC_FRAMEWORK_FLUID_AUDIO:
            self = .fluidAudio
        case RAC_FRAMEWORK_BUILTIN:
            self = .builtIn
        case RAC_FRAMEWORK_NONE:
            self = .none
        default:
            self = .unknown
        }
    }
}

// Event publishing helpers (same as existing CppEventBridge)
private func publishLLMEvent(type: rac_event_type_t, data: UnsafePointer<rac_analytics_event_data_t>) {
    switch type {
    case RAC_EVENT_LLM_GENERATION_STARTED:
        let event = data.pointee.data.llm_generation
        EventPublisher.shared.track(LLMEvent.generationStarted(
            generationId: event.generation_id.map { String(cString: $0) } ?? "",
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            prompt: nil,
            isStreaming: event.is_streaming == RAC_TRUE,
            framework: InferenceFramework(from: event.framework)
        ))
    case RAC_EVENT_LLM_GENERATION_COMPLETED:
        let event = data.pointee.data.llm_generation
        EventPublisher.shared.track(LLMEvent.generationCompleted(
            generationId: event.generation_id.map { String(cString: $0) } ?? "",
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            inputTokens: Int(event.input_tokens),
            outputTokens: Int(event.output_tokens),
            durationMs: event.duration_ms,
            tokensPerSecond: event.tokens_per_second,
            isStreaming: event.is_streaming == RAC_TRUE,
            timeToFirstTokenMs: event.time_to_first_token_ms > 0 ? event.time_to_first_token_ms : nil,
            framework: InferenceFramework(from: event.framework),
            temperature: event.temperature > 0 ? event.temperature : nil,
            maxTokens: event.max_tokens > 0 ? Int(event.max_tokens) : nil,
            contextLength: event.context_length > 0 ? Int(event.context_length) : nil
        ))
    case RAC_EVENT_LLM_GENERATION_FAILED:
        let event = data.pointee.data.llm_generation
        let errorMessage = event.error_message.map { String(cString: $0) } ?? "Unknown error"
        EventPublisher.shared.track(LLMEvent.generationFailed(
            generationId: event.generation_id.map { String(cString: $0) } ?? "",
            error: SDKError.llm(.generationFailed, errorMessage)
        ))
    case RAC_EVENT_LLM_MODEL_LOAD_COMPLETED:
        let event = data.pointee.data.llm_model
        EventPublisher.shared.track(LLMEvent.modelLoadCompleted(
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            durationMs: event.duration_ms,
            modelSizeBytes: event.model_size_bytes,
            framework: InferenceFramework(from: event.framework)
        ))
    default:
        break
    }
}

private func publishSTTEvent(type: rac_event_type_t, data: UnsafePointer<rac_analytics_event_data_t>) {
    switch type {
    case RAC_EVENT_STT_TRANSCRIPTION_COMPLETED:
        let event = data.pointee.data.stt_transcription
        EventPublisher.shared.track(STTEvent.transcriptionCompleted(
            transcriptionId: event.transcription_id.map { String(cString: $0) } ?? "",
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            text: event.text.map { String(cString: $0) } ?? "",
            confidence: event.confidence,
            durationMs: event.duration_ms,
            audioLengthMs: event.audio_length_ms,
            audioSizeBytes: Int(event.audio_size_bytes),
            wordCount: Int(event.word_count),
            realTimeFactor: event.real_time_factor,
            language: event.language.map { String(cString: $0) } ?? "en-US"
        ))
    default:
        break
    }
}

private func publishTTSEvent(type: rac_event_type_t, data: UnsafePointer<rac_analytics_event_data_t>) {
    switch type {
    case RAC_EVENT_TTS_SYNTHESIS_COMPLETED:
        let event = data.pointee.data.tts_synthesis
        EventPublisher.shared.track(TTSEvent.synthesisCompleted(
            synthesisId: event.synthesis_id.map { String(cString: $0) } ?? "",
            modelId: event.model_id.map { String(cString: $0) } ?? "",
            characterCount: Int(event.character_count),
            audioDurationMs: event.audio_duration_ms,
            audioSizeBytes: Int(event.audio_size_bytes),
            processingDurationMs: event.processing_duration_ms,
            charactersPerSecond: event.characters_per_second,
            sampleRate: Int(event.sample_rate),
            framework: InferenceFramework(from: event.framework)
        ))
    default:
        break
    }
}

private func publishVADEvent(type: rac_event_type_t, data: UnsafePointer<rac_analytics_event_data_t>) {
    switch type {
    case RAC_EVENT_VAD_STARTED:
        EventPublisher.shared.track(VADEvent.started)
    case RAC_EVENT_VAD_STOPPED:
        EventPublisher.shared.track(VADEvent.stopped)
    case RAC_EVENT_VAD_SPEECH_STARTED:
        EventPublisher.shared.track(VADEvent.speechStarted)
    case RAC_EVENT_VAD_SPEECH_ENDED:
        let event = data.pointee.data.vad
        EventPublisher.shared.track(VADEvent.speechEnded(durationMs: event.speech_duration_ms))
    default:
        break
    }
}
