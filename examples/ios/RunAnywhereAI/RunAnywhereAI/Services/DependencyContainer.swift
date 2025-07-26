//
//  DependencyContainer.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation

/// Dependency injection container for managing LLM services
@MainActor
final class DependencyContainer: ObservableObject {
    /// Shared instance
    static let shared = DependencyContainer()
    
    /// Registered service instances
    private var services: [String: LLMService] = [:]
    
    /// Service factories for lazy initialization
    private var factories: [String: () -> LLMService] = [:]
    
    /// Configuration options for services
    private var configurations: [String: [String: Any]] = [:]
    
    /// Service lifecycle observers
    private var observers: [UUID: ServiceLifecycleObserver] = [:]
    
    private init() {
        registerDefaultServices()
    }
    
    /// Register a service factory
    func register<T: LLMService>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: type)
        factories[key] = factory
    }
    
    /// Register a service factory with configuration
    func register<T: LLMService>(
        _ type: T.Type,
        configuration: [String: Any]? = nil,
        factory: @escaping () -> T
    ) {
        let key = String(describing: type)
        factories[key] = factory
        if let config = configuration {
            configurations[key] = config
        }
    }
    
    /// Register a singleton service instance
    func registerSingleton<T: LLMService>(_ service: T) {
        let key = String(describing: T.self)
        services[key] = service
    }
    
    /// Resolve a service
    func resolve<T: LLMService>(_ type: T.Type) -> T? {
        let key = String(describing: type)
        
        // Check if we have an existing instance
        if let service = services[key] as? T {
            return service
        }
        
        // Try to create from factory
        if let factory = factories[key] {
            let service = factory() as! T
            
            // Apply configuration if available
            if let config = configurations[key] {
                try? service.configure(config)
            }
            
            // Store for future use
            services[key] = service
            
            // Notify observers
            notifyServiceCreated(service)
            
            return service
        }
        
        return nil
    }
    
    /// Resolve all services of a given protocol type
    func resolveAll<T>(_ type: T.Type) -> [T] {
        var results: [T] = []
        
        // Check existing services
        for service in services.values {
            if let typedService = service as? T {
                results.append(typedService)
            }
        }
        
        // Check factories that haven't been instantiated
        for (key, factory) in factories {
            if services[key] == nil {
                if let service = factory() as? T {
                    services[key] = service as? LLMService
                    results.append(service)
                }
            }
        }
        
        return results
    }
    
    /// Clear all services
    func reset() {
        for service in services.values {
            service.cleanup()
        }
        services.removeAll()
        
        // Keep factories and configurations
        // They can be reused
    }
    
    /// Remove a specific service
    func remove<T: LLMService>(_ type: T.Type) {
        let key = String(describing: type)
        if let service = services[key] {
            service.cleanup()
            services.removeValue(forKey: key)
            notifyServiceRemoved(service)
        }
    }
    
    /// Add lifecycle observer
    @discardableResult
    func addObserver(_ observer: ServiceLifecycleObserver) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }
    
    /// Remove lifecycle observer
    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }
    
    // MARK: - Private Methods
    
    private func registerDefaultServices() {
        // Register all available LLM services
        register(MockLLMService.self) { MockLLMService() }
        register(LlamaCppService.self) { LlamaCppService() }
        register(MLCService.self) { MLCService() }
        register(ONNXService.self) { ONNXService() }
        register(ExecuTorchService.self) { ExecuTorchService() }
        register(TFLiteService.self) { TFLiteService() }
        register(PicoLLMService.self) { PicoLLMService() }
        
        if #available(iOS 15.0, *) {
            register(SwiftTransformersService.self) { SwiftTransformersService() }
        }
        
        if #available(iOS 17.0, *) {
            register(CoreMLService.self) { CoreMLService() }
            register(MLXService.self) { MLXService() }
        }
        
        if #available(iOS 18.0, *) {
            register(FoundationModelsService.self) { FoundationModelsService() }
        }
    }
    
    private func notifyServiceCreated(_ service: LLMService) {
        for observer in observers.values {
            observer.serviceCreated(service)
        }
    }
    
    private func notifyServiceRemoved(_ service: LLMService) {
        for observer in observers.values {
            observer.serviceRemoved(service)
        }
    }
}

/// Protocol for observing service lifecycle events
protocol ServiceLifecycleObserver {
    func serviceCreated(_ service: LLMService)
    func serviceRemoved(_ service: LLMService)
}

/// Service registration builder for fluent API
class ServiceRegistrationBuilder<T: LLMService> {
    private let container: DependencyContainer
    private let type: T.Type
    private var configuration: [String: Any] = [:]
    
    init(container: DependencyContainer, type: T.Type) {
        self.container = container
        self.type = type
    }
    
    func withConfiguration(_ config: [String: Any]) -> Self {
        configuration.merge(config) { _, new in new }
        return self
    }
    
    func withFactory(_ factory: @escaping () -> T) {
        container.register(type, configuration: configuration, factory: factory)
    }
    
    func asSingleton(_ instance: T) {
        if !configuration.isEmpty {
            try? instance.configure(configuration)
        }
        container.registerSingleton(instance)
    }
}

// MARK: - Convenience Extensions

extension DependencyContainer {
    /// Fluent API for service registration
    func register<T: LLMService>(_ type: T.Type) -> ServiceRegistrationBuilder<T> {
        ServiceRegistrationBuilder(container: self, type: type)
    }
}