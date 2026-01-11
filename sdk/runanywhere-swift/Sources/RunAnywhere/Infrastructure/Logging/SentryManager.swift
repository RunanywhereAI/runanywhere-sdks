//
//  SentryManager.swift
//  RunAnywhere SDK
//
//  Manages Sentry SDK initialization for crash reporting and error tracking
//

import Foundation
import Sentry

/// Manages Sentry SDK initialization and configuration
public final class SentryManager: @unchecked Sendable {

    public static let shared = SentryManager()

    public private(set) var isInitialized: Bool = false

    private init() {}

    // MARK: - Initialization

    /// Initialize Sentry with the configured DSN
    /// - Parameters:
    ///   - dsn: Sentry DSN (if nil, uses C++ config sentryDSN)
    ///   - environment: SDK environment for tagging events
    public func initialize(dsn: String? = nil, environment: SDKEnvironment = .development) {
        guard !isInitialized else { return }

        // Use provided DSN or fallback to C++ config
        let sentryDSN = dsn ?? CppBridge.DevConfig.sentryDSN

        guard let configuredDSN = sentryDSN,
              configuredDSN != "YOUR_SENTRY_DSN_HERE" && !configuredDSN.isEmpty else {
            // NOTE: Do NOT use SDKLogger here - it would cause a deadlock during Logging.shared initialization
            #if DEBUG
            print("🔍 [Sentry] DSN not configured. Crash reporting disabled.")
            #endif
            return
        }

        SentrySDK.start { options in
            options.dsn = configuredDSN
            options.environment = environment.rawValue
            options.enableCrashHandler = true
            options.enableAutoBreadcrumbTracking = true
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 2.0
            options.enableAutoSessionTracking = true
            options.attachStacktrace = true
            options.tracesSampleRate = 0

            #if DEBUG
            options.debug = true
            options.diagnosticLevel = .warning
            #else
            options.debug = false
            #endif

            options.beforeSend = { event in
                event.tags?["sdk_name"] = "RunAnywhere"
                event.tags?["sdk_version"] = SDKConstants.version
                return event
            }
        }

        isInitialized = true
    }

    // MARK: - Direct API (for advanced use cases)

    /// Capture an error directly with Sentry
    public func captureError(_ error: Error, context: [String: Any]? = nil) { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        guard isInitialized else { return }

        SentrySDK.capture(error: error) { scope in
            if let context = context {
                for (key, value) in context {
                    scope.setExtra(value: value, key: key)
                }
            }
        }
    }

    /// Set user information for Sentry events
    public func setUser(userId: String, email: String? = nil, username: String? = nil) {
        guard isInitialized else { return }

        let user = User(userId: userId)
        user.email = email
        user.username = username
        SentrySDK.setUser(user)
    }

    /// Clear user information
    public func clearUser() {
        guard isInitialized else { return }
        SentrySDK.setUser(nil)
    }

    /// Flush pending events
    public func flush(timeout: TimeInterval = 2.0) {
        guard isInitialized else { return }
        SentrySDK.flush(timeout: timeout)
    }

    /// Close Sentry SDK
    public func close() {
        guard isInitialized else { return }
        SentrySDK.close()
        isInitialized = false
    }
}
