import Foundation

// MARK: - Component Input Protocol

/// Base protocol for component inputs
/// All component-specific inputs should conform to this protocol
public protocol ComponentInput: Sendable {
    /// Validate the input parameters
    /// - Throws: Error if validation fails
    func validate() throws
}

// MARK: - Component Output Protocol

/// Base protocol for component outputs
/// All component-specific outputs should conform to this protocol
public protocol ComponentOutput: Sendable {
    /// Timestamp when the output was generated
    var timestamp: Date { get }
}

// MARK: - Component Configuration Protocol

/// Base protocol for component configurations
/// All component-specific configurations should conform to this protocol
public protocol ComponentConfiguration: Sendable {
    /// Validate the configuration parameters
    /// - Throws: Error if validation is invalid
    func validate() throws
}

// MARK: - Component Adapter Protocol

/// Base protocol for component adapters
/// Adapters are responsible for creating service instances from configurations
public protocol ComponentAdapter {
    // swiftlint:disable:next avoid_any_object
    associatedtype ServiceType: AnyObject

    /// Create a service instance from the given configuration
    /// - Parameter configuration: The component configuration
    /// - Returns: A configured service instance
    /// - Throws: Error if service creation fails
    func createService(configuration: any ComponentConfiguration) async throws -> ServiceType
}
