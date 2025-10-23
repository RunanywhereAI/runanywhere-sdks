import Foundation

/// A cross-platform unfair lock that provides Swift 6 concurrency safety
/// Uses os_unfair_lock which is available on all Apple platforms
public final class UnfairLock: @unchecked Sendable {

    private var lock: os_unfair_lock_t

    public init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Execute a closure while holding the lock
    @discardableResult
    public func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return try body()
    }
}

/// A cross-platform unfair lock with protected state
/// Uses os_unfair_lock for synchronization
public final class UnfairLockWithState<State>: @unchecked Sendable {

    private var state: State
    private var lock: os_unfair_lock_t

    public init(initialState: State) {
        state = initialState
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Execute a closure while holding the lock, providing read-only access to the state
    @discardableResult
    public func withLock<Result>(_ body: (State) throws -> Result) rethrows -> Result {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return try body(state)
    }

    /// Execute a closure while holding the lock, providing mutable access to the state
    @discardableResult
    public func withLock<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return try body(&state)
    }
}
