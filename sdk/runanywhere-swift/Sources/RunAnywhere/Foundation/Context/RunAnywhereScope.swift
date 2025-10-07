import Foundation

/// Thread-safe scope management for RunAnywhere SDK
/// Following Sentry's context isolation pattern
public class RunAnywhereScope {

    // MARK: - Properties

    private let lock = NSLock()
    private var _deviceId: String?
    private var _isRegistering: Bool = false

    // MARK: - Thread Isolation

    private static let isolationContext = NSMapTable<AnyObject, RunAnywhereScope>.strongToWeakObjects()
    private static let contextLock = NSLock()

    /// Get the current scope for the calling thread
    /// Creates a new scope if none exists for this thread
    /// - Returns: Current thread's scope
    public static func getCurrentScope() -> RunAnywhereScope {
        contextLock.lock()
        defer { contextLock.unlock() }

        let currentContext = Thread.current

        if let scope = isolationContext.object(forKey: currentContext) {
            return scope
        }

        let newScope = RunAnywhereScope()
        isolationContext.setObject(newScope, forKey: currentContext)
        return newScope
    }

    /// Clear all scopes (for testing)
    public static func clearAllScopes() {
        contextLock.lock()
        defer { contextLock.unlock() }

        isolationContext.removeAllObjects()
    }

    // MARK: - Device ID Management

    /// Get cached device ID for this scope
    /// - Returns: Cached device ID if available
    public func getCachedDeviceId() -> String? {
        lock.lock()
        defer { lock.unlock() }

        return _deviceId
    }

    /// Set device ID in this scope
    /// - Parameter deviceId: Device ID to cache
    public func setCachedDeviceId(_ deviceId: String?) {
        lock.lock()
        defer { lock.unlock() }

        _deviceId = deviceId
    }

    // MARK: - Registration State

    /// Check if registration is in progress
    /// - Returns: true if currently registering
    public func isRegistering() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return _isRegistering
    }

    /// Set registration state
    /// - Parameter registering: true if registration is in progress
    public func setRegistering(_ registering: Bool) {
        lock.lock()
        defer { lock.unlock() }

        _isRegistering = registering
    }

    // MARK: - Scope Information

    /// Get scope identifier (for debugging)
    /// - Returns: Unique scope identifier
    var identifier: String {
        return String(describing: Unmanaged.passUnretained(self).toOpaque())
    }

    /// Get thread information (for debugging)
    /// - Returns: Thread description
    var threadInfo: String {
        let thread = Thread.current
        if thread.isMainThread {
            return "Main Thread"
        } else {
            return "Background Thread (\(thread.description))"
        }
    }
}

// MARK: - Global Scope Access

extension RunAnywhere {
    /// Get the current scope for the calling thread
    /// - Returns: Current scope
    internal static func getCurrentScope() -> RunAnywhereScope {
        return RunAnywhereScope.getCurrentScope()
    }
}
