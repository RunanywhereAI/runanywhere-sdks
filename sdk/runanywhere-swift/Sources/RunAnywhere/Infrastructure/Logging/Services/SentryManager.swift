//
//  SentryManager.swift
//  RunAnywhere SDK
//
//  Manages Sentry SDK initialization for crash reporting and error tracking
//

import Foundation
import Sentry

/// Manages Sentry SDK initialization and configuration
/// Provides crash reporting, error aggregation, and log ingestion
public final class SentryManager: @unchecked Sendable {

    // MARK: - Shared Instance

    /// Shared singleton instance
    public static let shared = SentryManager()

    // MARK: - Properties

    /// Whether Sentry has been initialized
    public private(set) var isInitialized: Bool = false

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Initialize Sentry with the configured DSN
    /// - Parameters:
    ///   - dsn: Sentry DSN (if nil, uses DevelopmentConfig.sentryDSN)
    ///   - environment: SDK environment for tagging events
    public func initialize(dsn: String? = nil, environment: SDKEnvironment = .development) {
        guard !isInitialized else { return }

        let sentryDSN = dsn ?? DevelopmentConfig.sentryDSN

        // Skip initialization if DSN is placeholder
        guard sentryDSN != "YOUR_SENTRY_DSN_HERE" && !sentryDSN.isEmpty else {
            // Log warning but don't fail - Sentry is optional
            #if DEBUG
            print("[RunAnywhere] Sentry DSN not configured. Crash reporting disabled.")
            #endif
            return
        }

        SentrySDK.start { options in
            options.dsn = sentryDSN
            options.environment = environment.rawValue

            // Enable crash reporting
            options.enableCrashHandler = true

            // Enable automatic breadcrumbs
            options.enableAutoBreadcrumbTracking = true

            // Enable app hang detection (iOS 13+)
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 2.0

            // Enable automatic session tracking
            options.enableAutoSessionTracking = true

            // Attach stack traces to all events
            options.attachStacktrace = true

            // Sample rate for performance monitoring (disabled for now)
            options.tracesSampleRate = 0

            // Debug mode for development
            #if DEBUG
            options.debug = true
            options.diagnosticLevel = .warning
            #else
            options.debug = false
            #endif

            // Add SDK version tag
            options.beforeSend = { event in
                event.tags?["sdk_name"] = "RunAnywhere"
                event.tags?["sdk_version"] = "0.1.0"
                return event
            }
        }

        isInitialized = true
    }

    /// Capture an error with Sentry
    /// - Parameters:
    ///   - error: The error to capture
    ///   - context: Additional context information
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

    /// Capture a message with Sentry
    /// - Parameters:
    ///   - message: The message to capture
    ///   - level: Severity level
    public func captureMessage(_ message: String, level: SentryLevel = .info) {
        guard isInitialized else { return }
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level)
        }
    }

    /// Add a breadcrumb for context
    /// - Parameters:
    ///   - category: Breadcrumb category
    ///   - message: Breadcrumb message
    ///   - level: Severity level
    public func addBreadcrumb(category: String, message: String, level: SentryLevel = .info) {
        guard isInitialized else { return }

        let breadcrumb = Breadcrumb(level: level, category: category)
        breadcrumb.message = message
        breadcrumb.timestamp = Date()
        SentrySDK.addBreadcrumb(breadcrumb)
    }

    /// Set user information for Sentry events
    /// - Parameters:
    ///   - userId: User identifier
    ///   - email: User email (optional)
    ///   - username: Username (optional)
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
    /// - Parameter timeout: Timeout in seconds
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
