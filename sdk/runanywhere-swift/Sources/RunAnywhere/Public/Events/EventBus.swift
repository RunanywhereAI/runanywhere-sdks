import Combine
import Foundation

/// Central event bus for SDK-wide event distribution
/// Thread-safe event bus using Combine's built-in thread safety
public final class EventBus: @unchecked Sendable {
    /// Shared instance - thread-safe singleton
    public static let shared = EventBus()

    /// Event publishers for each event type
    private let initializationSubject = PassthroughSubject<SDKInitializationEvent, Never>()
    private let configurationSubject = PassthroughSubject<SDKConfigurationEvent, Never>()
    private let generationSubject = PassthroughSubject<SDKGenerationEvent, Never>()
    private let modelSubject = PassthroughSubject<SDKModelEvent, Never>()
    private let voiceSubject = PassthroughSubject<SDKVoiceEvent, Never>()
    private let performanceSubject = PassthroughSubject<SDKPerformanceEvent, Never>()
    private let networkSubject = PassthroughSubject<SDKNetworkEvent, Never>()
    private let storageSubject = PassthroughSubject<SDKStorageEvent, Never>()
    private let frameworkSubject = PassthroughSubject<SDKFrameworkEvent, Never>()
    private let componentSubject = PassthroughSubject<ComponentInitializationEvent, Never>()

    /// All events publisher
    private let allEventsSubject = PassthroughSubject<any SDKEvent, Never>()

    /// Public publishers for subscribing to events
    public var initializationEvents: AnyPublisher<SDKInitializationEvent, Never> {
        initializationSubject.eraseToAnyPublisher()
    }

    public var configurationEvents: AnyPublisher<SDKConfigurationEvent, Never> {
        configurationSubject.eraseToAnyPublisher()
    }

    public var generationEvents: AnyPublisher<SDKGenerationEvent, Never> {
        generationSubject.eraseToAnyPublisher()
    }

    public var modelEvents: AnyPublisher<SDKModelEvent, Never> {
        modelSubject.eraseToAnyPublisher()
    }

    public var voiceEvents: AnyPublisher<SDKVoiceEvent, Never> {
        voiceSubject.eraseToAnyPublisher()
    }

    public var performanceEvents: AnyPublisher<SDKPerformanceEvent, Never> {
        performanceSubject.eraseToAnyPublisher()
    }

    public var networkEvents: AnyPublisher<SDKNetworkEvent, Never> {
        networkSubject.eraseToAnyPublisher()
    }

    public var storageEvents: AnyPublisher<SDKStorageEvent, Never> {
        storageSubject.eraseToAnyPublisher()
    }

    public var frameworkEvents: AnyPublisher<SDKFrameworkEvent, Never> {
        frameworkSubject.eraseToAnyPublisher()
    }

    public var componentEvents: AnyPublisher<ComponentInitializationEvent, Never> {
        componentSubject.eraseToAnyPublisher()
    }

    public var allEvents: AnyPublisher<any SDKEvent, Never> {
        allEventsSubject.eraseToAnyPublisher()
    }

    private init() {}

    // MARK: - Event Publishing

    /// Publish an initialization event
    public func publish(_ event: SDKInitializationEvent) {
        initializationSubject.send(event)
        allEventsSubject.send(event)
    }

    /// Publish a configuration event
    public func publish(_ event: SDKConfigurationEvent) {
        configurationSubject.send(event)
        allEventsSubject.send(event)
    }

    /// Publish a generation event
    public func publish(_ event: SDKGenerationEvent) {
        generationSubject.send(event)
        allEventsSubject.send(event)
    }

    /// Publish a model event
    public func publish(_ event: SDKModelEvent) {
        modelSubject.send(event)
        allEventsSubject.send(event)
    }

    /// Publish a voice event
    public func publish(_ event: SDKVoiceEvent) {
        voiceSubject.send(event)
        allEventsSubject.send(event)
    }

    /// Publish a performance event
    public func publish(_ event: SDKPerformanceEvent) {
        performanceSubject.send(event)
        allEventsSubject.send(event)
    }

    /// Publish a network event
    public func publish(_ event: SDKNetworkEvent) {
        networkSubject.send(event)
        allEventsSubject.send(event)
    }

    /// Publish a storage event
    public func publish(_ event: SDKStorageEvent) {
        storageSubject.send(event)
        allEventsSubject.send(event)
    }

    /// Publish a framework event
    public func publish(_ event: SDKFrameworkEvent) {
        frameworkSubject.send(event)
        allEventsSubject.send(event)
    }

    /// Publish a device event
    public func publish(_ event: SDKDeviceEvent) {
        // Since we don't have a device subject yet, just send to all events
        allEventsSubject.send(event)
    }

    /// Publish a component initialization event
    public func publish(_ event: ComponentInitializationEvent) {
        componentSubject.send(event)
        allEventsSubject.send(event)
    }

    /// Generic event publisher
    public func publish(_ event: any SDKEvent) {
        switch event {
        case let initEvent as SDKInitializationEvent:
            publish(initEvent)
        case let configEvent as SDKConfigurationEvent:
            publish(configEvent)
        case let genEvent as SDKGenerationEvent:
            publish(genEvent)
        case let modelEvent as SDKModelEvent:
            publish(modelEvent)
        case let voiceEvent as SDKVoiceEvent:
            publish(voiceEvent)
        case let perfEvent as SDKPerformanceEvent:
            publish(perfEvent)
        case let netEvent as SDKNetworkEvent:
            publish(netEvent)
        case let storageEvent as SDKStorageEvent:
            publish(storageEvent)
        case let frameworkEvent as SDKFrameworkEvent:
            publish(frameworkEvent)
        case let deviceEvent as SDKDeviceEvent:
            publish(deviceEvent)
        case let componentEvent as ComponentInitializationEvent:
            publish(componentEvent)
        default:
            allEventsSubject.send(event)
        }
    }
}

// MARK: - Non-Blocking Event Publishing

extension EventBus {
    /// Publish an event asynchronously without blocking the caller
    /// Use this for hot paths where event publishing shouldn't add latency
    public func publishAsync(_ event: SDKInitializationEvent) {
        Task.detached { [self] in
            self.publish(event)
        }
    }

    /// Publish a generation event asynchronously without blocking the caller
    public func publishAsync(_ event: SDKGenerationEvent) {
        Task.detached { [self] in
            self.publish(event)
        }
    }

    /// Publish a model event asynchronously without blocking the caller
    public func publishAsync(_ event: SDKModelEvent) {
        Task.detached { [self] in
            self.publish(event)
        }
    }

    /// Publish a voice event asynchronously without blocking the caller
    public func publishAsync(_ event: SDKVoiceEvent) {
        Task.detached { [self] in
            self.publish(event)
        }
    }

    /// Publish a configuration event asynchronously without blocking the caller
    public func publishAsync(_ event: SDKConfigurationEvent) {
        Task.detached { [self] in
            self.publish(event)
        }
    }

    /// Publish a component event asynchronously without blocking the caller
    public func publishAsync(_ event: ComponentInitializationEvent) {
        Task.detached { [self] in
            self.publish(event)
        }
    }
}

// MARK: - Convenience Extensions

extension EventBus {
    /// Subscribe to events with a closure
    public func on<T: SDKEvent>(_ eventType: T.Type, handler: @escaping (T) -> Void) -> AnyCancellable {
        allEvents
            .compactMap { $0 as? T }
            .sink { event in
                handler(event)
            }
    }

    /// Subscribe to specific initialization events
    public func onInitialization(handler: @escaping (SDKInitializationEvent) -> Void) -> AnyCancellable {
        initializationEvents.sink { event in
            handler(event)
        }
    }

    /// Subscribe to specific generation events
    public func onGeneration(handler: @escaping (SDKGenerationEvent) -> Void) -> AnyCancellable {
        generationEvents.sink { event in
            handler(event)
        }
    }

    /// Subscribe to specific model events
    public func onModel(handler: @escaping (SDKModelEvent) -> Void) -> AnyCancellable {
        modelEvents.sink { event in
            handler(event)
        }
    }

    /// Subscribe to specific voice events
    public func onVoice(handler: @escaping (SDKVoiceEvent) -> Void) -> AnyCancellable {
        voiceEvents.sink { event in
            handler(event)
        }
    }

    /// Subscribe to component initialization events
    public func onComponentInitialization(
        handler: @escaping (ComponentInitializationEvent) -> Void
    ) -> AnyCancellable {
        componentEvents.sink { event in
            handler(event)
        }
    }

    /// Subscribe to specific component events
    public func onComponent(
        _ component: SDKComponent,
        handler: @escaping (ComponentInitializationEvent) -> Void
    ) -> AnyCancellable {
        componentEvents
            .filter { $0.component == component }
            .sink { event in
                handler(event)
            }
    }
}
