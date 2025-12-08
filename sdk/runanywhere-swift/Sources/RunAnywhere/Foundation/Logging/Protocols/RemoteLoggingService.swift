import Foundation

/// Protocol for remote logging service integration
/// This allows for flexible implementation with different providers
protocol RemoteLoggingService {
    /// Initialize the service with configuration
    func configure(apiKey: String, environment: SDKEnvironment)

    /// Log an event to the remote service
    func logEvent(_ event: LogEntry, level: LogLevel)

    /// Log an error with stack trace
    func logError(_ error: Error, metadata: [String: Any]?)  // swiftlint:disable:this prefer_concrete_types avoid_any_type

    /// Add user context for better debugging
    func setUserContext(userId: String?, metadata: [String: Any]?)  // swiftlint:disable:this prefer_concrete_types avoid_any_type

    /// Add breadcrumb for tracking user actions
    func addBreadcrumb(message: String, category: String, level: LogLevel)

    /// Flush all pending logs
    func flush()

    /// Clear all stored data
    func clear()
}

// MARK: - Recommended Remote Logging Services

/*
 Recommended Remote Logging Services for RunAnywhere SDK:

 1. **Sentry (RECOMMENDED)**
    - Pros:
      • Excellent error tracking and performance monitoring
      • Native Swift/iOS SDK with great integration
      • Automatic breadcrumbs and context capture
      • Session replay capabilities
      • Real-time alerts and notifications
      • Good pricing for mobile apps
      • GDPR compliant with data residency options
    - Cons:
      • Can increase app size (~2MB)
      • Requires careful PII handling
    - Best for: Production error tracking and monitoring

 2. **DataDog**
    - Pros:
      • Comprehensive APM and logging platform
      • Excellent for correlation with backend services
      • Real-time log analysis
      • Custom dashboards and alerting
    - Cons:
      • More expensive than alternatives
      • Overkill if only need mobile logging
    - Best for: Enterprise with existing DataDog infrastructure

 3. **LogRocket**
    - Pros:
      • Session replay with network requests
      • User behavior analytics
      • Performance monitoring
    - Cons:
      • More focused on web than mobile
      • Higher cost
    - Best for: User behavior analysis

 4. **Custom Backend Service**
    - Pros:
      • Full control over data
      • Can optimize for specific needs
      • No third-party dependencies
      • Cost-effective at scale
    - Cons:
      • Requires building and maintaining infrastructure
      • Need to handle scaling, storage, and analysis
      • Time to implement
    - Best for: Companies with specific compliance requirements

 **RECOMMENDATION: Sentry**

 For RunAnywhere SDK, I recommend Sentry because:
 1. It's specifically designed for error tracking in production apps
 2. Has excellent Swift/iOS integration with minimal setup
 3. Provides actionable insights with stack traces and breadcrumbs
 4. Cost-effective for mobile applications
 5. Can filter sensitive data before sending
 6. Supports offline caching and batch uploads

 Implementation example:
 ```swift
 import Sentry

 class SentryLoggingService: RemoteLoggingService {
     func configure(apiKey: String, environment: SDKEnvironment) {
         SentrySDK.start { options in
             options.dsn = apiKey
             options.environment = environment.rawValue
             options.tracesSampleRate = environment == .production ? 0.1 : 1.0
             options.attachScreenshot = false // Privacy
             options.beforeSend = { event in
                 // Filter sensitive data
                 return event
             }
         }
     }

     func logEvent(_ event: LogEntry, level: LogLevel) {
         let sentryLevel = mapToSentryLevel(level)
         SentrySDK.capture(message: event.message) { scope in
             scope.setLevel(sentryLevel)
             scope.setContext("metadata", value: event.metadata ?? [:])
         }
     }
 }
 ```
 */
