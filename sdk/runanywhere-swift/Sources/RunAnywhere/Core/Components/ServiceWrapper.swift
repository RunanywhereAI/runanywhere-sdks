import Foundation

// MARK: - Service Wrapper Protocol

/// Service wrapper protocol that allows protocol types to be used with BaseComponent
/// This enables wrapping services that are defined as protocols rather than concrete classes
public protocol ServiceWrapper: AnyObject { // swiftlint:disable:this avoid_any_object
    associatedtype ServiceProtocol

    /// The wrapped service instance
    var wrappedService: ServiceProtocol? { get set }
}

// MARK: - Any Service Wrapper

/// Generic service wrapper for any protocol type
/// Use this when you need to wrap a protocol-typed service for use with BaseComponent
///
/// Example usage:
/// ```swift
/// let wrapper = AnyServiceWrapper<MyServiceProtocol>(myService)
/// // Later access:
/// if let service = wrapper.wrappedService {
///     service.doSomething()
/// }
/// ```
public final class AnyServiceWrapper<T>: ServiceWrapper {
    /// The wrapped service instance
    public var wrappedService: T?

    /// Initialize with an optional service
    /// - Parameter service: The service to wrap (optional)
    public init(_ service: T? = nil) {
        self.wrappedService = service
    }
}
