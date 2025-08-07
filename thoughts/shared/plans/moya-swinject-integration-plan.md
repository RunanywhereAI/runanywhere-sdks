# RunAnywhere Swift SDK - Moya and Swinject Integration Plan

## Executive Summary

This plan outlines the integration of Moya (networking abstraction) and Swinject (dependency injection) into the RunAnywhere Swift SDK. These battle-tested frameworks will significantly improve code quality, maintainability, and testability while reducing custom implementation complexity.

**Framework Versions:**
- **Moya**: 15.0.0+ (Swift 5.3+ minimum, includes Combine support)
- **Swinject**: 2.9.0+ (Swift 5.9+ minimum, includes visionOS support)

**Key Benefits:**
- Replace ~500 lines of manual ServiceContainer code with Swinject
- Type-safe API definitions with Moya replacing raw Alamofire usage
- Improved testability with built-in mocking and stubbing
- Better separation of concerns and modular architecture
- Production-proven reliability from mature frameworks
- Built-in support for Combine and async/await patterns

---

## Phase 1: Swinject Integration - Core Infrastructure (Week 1)

### 1.1 Add Swinject Dependency

**Package.swift Update:**
```swift
dependencies: [
    .package(url: "https://github.com/Swinject/Swinject.git", from: "2.9.0"),
    // existing dependencies...
]
```

**Platform Requirements:**
- macOS 10.13+
- iOS 12+
- tvOS 12+
- watchOS 4+
- visionOS 1+
- Swift 5.9+

### 1.2 Design Assembly Architecture

**Create Assembly Structure:**
```
Sources/RunAnywhere/Foundation/DependencyInjection/
├── Assemblies/
│   ├── CoreAssembly.swift           # Core services (Logger, Environment)
│   ├── DataAssembly.swift          # Repositories and database
│   ├── NetworkAssembly.swift       # API clients and network services
│   ├── CapabilityAssembly.swift    # All capability services
│   ├── ModelLoadingAssembly.swift  # Model loading services
│   └── PublicAssembly.swift        # Public API services
├── Extensions/
│   └── Container+RunAnywhere.swift  # Convenience extensions
└── ServiceContainerMigration.swift  # Migration helper
```

### 1.3 Implement Core Assembly

**CoreAssembly.swift:**
```swift
import Swinject

final class CoreAssembly: Assembly {
    func assemble(container: Container) {
        // Logger
        container.register(LoggingManager.self) { resolver in
            LoggingManager(
                configuration: resolver.resolve(LoggingConfiguration.self)!,
                remoteLogger: resolver.resolve(RemoteLogger.self)
            )
        }
        .inObjectScope(.container)

        // Environment Configuration
        container.register(EnvironmentConfiguration.self) { _ in
            EnvironmentConfiguration()
        }
        .inObjectScope(.container)

        // SDK Logger
        container.register(SDKLogger.self) { resolver in
            SDKLogger(
                loggingManager: resolver.resolve(LoggingManager.self)!,
                identifier: "RunAnywhereSDK"
            )
        }
    }
}
```

### 1.4 Create Assembler Configuration

**SDKAssembler.swift:**
```swift
import Swinject

public final class SDKAssembler {
    private let assembler: Assembler

    public init(configuration: SDKConfiguration) {
        // Create container with configuration
        let container = Container()
        container.register(SDKConfiguration.self) { _ in configuration }

        // Initialize assembler with all assemblies
        self.assembler = Assembler(
            [
                CoreAssembly(),
                DataAssembly(),
                NetworkAssembly(),
                CapabilityAssembly(),
                ModelLoadingAssembly(),
                PublicAssembly()
            ],
            container: container
        )
    }

    public var resolver: Resolver {
        assembler.resolver
    }

    public var synchronizedResolver: Resolver {
        assembler.resolver.synchronize()
    }
}
```

### 1.5 Migrate ServiceContainer

**Migration Strategy:**
1. Keep existing ServiceContainer temporarily
2. Create Swinject assemblies alongside
3. Add resolver property to ServiceContainer
4. Gradually migrate service resolution
5. Remove old implementations

**ServiceContainer Migration:**
```swift
// Add to existing ServiceContainer
private let assembler: SDKAssembler
public var resolver: Resolver { assembler.synchronizedResolver }

// Gradual migration example
public var logger: SDKLogger {
    // Old: return _logger
    return resolver.resolve(SDKLogger.self)!
}
```

---

## Phase 2: Moya Integration - Networking Layer (Week 2)

### 2.1 Add Moya Dependency

**Package.swift Update:**
```swift
dependencies: [
    .package(url: "https://github.com/Moya/Moya.git", .upToNextMajor(from: "15.0.0")),
    // existing dependencies...
]
```

**Platform Requirements:**
- macOS 10.12+
- iOS 10+
- tvOS 10+
- watchOS 3+
- Swift 5.3+ (minimum)
- Alamofire 5.0+ (dependency)

### 2.2 Define API Specifications

**Create API Structure:**
```
Sources/RunAnywhere/Data/Network/API/
├── RunAnywhereAPI.swift          # Main API enum
├── Targets/
│   ├── ConfigurationTarget.swift
│   ├── ModelMetadataTarget.swift
│   ├── TelemetryTarget.swift
│   └── CloudInferenceTarget.swift
├── Models/
│   ├── APIError.swift
│   └── APIResponse.swift
└── Plugins/
    ├── AuthenticationPlugin.swift
    ├── CostTrackingPlugin.swift
    └── TelemetryPlugin.swift
```

### 2.3 Implement API Target

**RunAnywhereAPI.swift:**
```swift
import Moya

enum RunAnywhereAPI {
    // Configuration
    case fetchConfiguration(apiKey: String)
    case updateConfiguration(ConfigurationDTO)

    // Model Metadata
    case fetchModelList
    case fetchModelMetadata(modelId: String)
    case reportModelUsage(ModelUsageDTO)

    // Telemetry
    case sendTelemetry(TelemetryDTO)
    case sendBatch([TelemetryDTO])

    // Cloud Inference
    case generateText(request: CloudInferenceRequest)
    case streamGeneration(request: CloudInferenceRequest)
}

extension RunAnywhereAPI: TargetType {
    var baseURL: URL {
        URL(string: "https://api.runanywhere.ai/v1")!
    }

    var path: String {
        switch self {
        case .fetchConfiguration:
            return "/configuration"
        case .updateConfiguration:
            return "/configuration"
        case .fetchModelList:
            return "/models"
        case .fetchModelMetadata(let modelId):
            return "/models/\(modelId)"
        case .reportModelUsage:
            return "/models/usage"
        case .sendTelemetry:
            return "/telemetry"
        case .sendBatch:
            return "/telemetry/batch"
        case .generateText:
            return "/inference/generate"
        case .streamGeneration:
            return "/inference/stream"
        }
    }

    var method: Moya.Method {
        switch self {
        case .fetchConfiguration, .fetchModelList, .fetchModelMetadata:
            return .get
        case .updateConfiguration, .reportModelUsage, .sendTelemetry,
             .sendBatch, .generateText, .streamGeneration:
            return .post
        }
    }

    var task: Task {
        switch self {
        case .fetchConfiguration, .fetchModelList:
            return .requestPlain

        case .fetchModelMetadata(let modelId):
            return .requestParameters(
                parameters: ["model_id": modelId],
                encoding: URLEncoding.queryString
            )

        case .updateConfiguration(let config):
            return .requestJSONEncodable(config)

        case .reportModelUsage(let usage):
            return .requestJSONEncodable(usage)

        case .sendTelemetry(let telemetry):
            return .requestJSONEncodable(telemetry)

        case .sendBatch(let batch):
            return .requestJSONEncodable(["events": batch])

        case .generateText(let request), .streamGeneration(let request):
            return .requestJSONEncodable(request)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }

    var sampleData: Data {
        switch self {
        case .fetchModelList:
            return """
            {
                "models": [
                    {"id": "llama-3.2-1b", "name": "Llama 3.2 1B"},
                    {"id": "phi-3.5-mini", "name": "Phi 3.5 Mini"}
                ]
            }
            """.data(using: .utf8)!
        default:
            return Data()
        }
    }
}
```

### 2.4 Create Custom Plugins

**AuthenticationPlugin.swift:**
```swift
import Moya

struct AuthenticationPlugin: PluginType {
    let apiKeyProvider: () -> String?

    func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        var request = request
        if let apiKey = apiKeyProvider() {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
```

**CostTrackingPlugin.swift:**
```swift
import Moya

final class CostTrackingPlugin: PluginType {
    private let costTracker: CostTrackingService

    init(costTracker: CostTrackingService) {
        self.costTracker = costTracker
    }

    func didReceive(_ result: Result<Response, MoyaError>, target: TargetType) {
        guard case .success(let response) = result,
              let costHeader = response.response?.value(forHTTPHeaderField: "X-API-Cost") else {
            return
        }

        if let cost = Double(costHeader) {
            costTracker.recordAPIUsage(
                endpoint: target.path,
                cost: cost,
                timestamp: Date()
            )
        }
    }
}
```

### 2.5 Implement Moya Provider Factory

**NetworkAssembly.swift Update:**
```swift
import Swinject
import Moya

final class NetworkAssembly: Assembly {
    func assemble(container: Container) {
        // Moya Provider
        container.register(MoyaProvider<RunAnywhereAPI>.self) { resolver in
            let configuration = resolver.resolve(SDKConfiguration.self)!
            let logger = resolver.resolve(SDKLogger.self)!
            let costTracker = resolver.resolve(CostTrackingService.self)!

            let plugins: [PluginType] = [
                AuthenticationPlugin(apiKeyProvider: { configuration.apiKey }),
                CostTrackingPlugin(costTracker: costTracker),
                NetworkLoggerPlugin(configuration: .init(
                    formatter: .init(responseData: JSONResponseDataFormatter),
                    logOptions: .verbose
                ))
            ]

            return MoyaProvider<RunAnywhereAPI>(
                endpointClosure: { target in
                    MoyaProvider.defaultEndpointMapping(for: target)
                        .adding(newHTTPHeaderFields: [
                            "X-SDK-Version": SDKConstants.version,
                            "X-Platform": SDKConstants.platform
                        ])
                },
                plugins: plugins,
                trackInflights: true // Enable request deduplication
            )
        }
        .inObjectScope(.container)

        // API Client using Moya
        container.register(APIClient.self) { resolver in
            MoyaAPIClient(
                provider: resolver.resolve(MoyaProvider<RunAnywhereAPI>.self)!,
                decoder: JSONDecoder(),
                logger: resolver.resolve(SDKLogger.self)!
            )
        }
        .inObjectScope(.container)
    }
}
```

---

## Phase 3: Service Migration (Week 3)

### 3.1 Capability Services Migration

**CapabilityAssembly.swift:**
```swift
import Swinject

final class CapabilityAssembly: Assembly {
    func assemble(container: Container) {
        // Device Capability
        container.register(HardwareDetectionService.self) { resolver in
            HardwareDetectionService(
                processorDetector: resolver.resolve(ProcessorDetector.self)!,
                gpuDetector: resolver.resolve(GPUDetector.self)!,
                neuralEngineDetector: resolver.resolve(NeuralEngineDetector.self)!,
                logger: resolver.resolve(SDKLogger.self)!
            )
        }

        // Model Loading
        container.register(ModelLoadingService.self) { resolver in
            ModelLoadingService(
                frameworkRegistry: resolver.resolve(FrameworkAdapterRegistry.self)!,
                validationService: resolver.resolve(ValidationService.self)!,
                logger: resolver.resolve(SDKLogger.self)!
            )
        }

        // Routing
        container.register(RoutingService.self) { resolver in
            RoutingService(
                configuration: resolver.resolve(RoutingConfiguration.self)!,
                hardwareService: resolver.resolve(HardwareDetectionService.self)!,
                costEstimator: resolver.resolve(CostEstimationService.self)!
            )
        }

        // Continue for all capability services...
    }
}
```

### 3.2 Repository Migration

**DataAssembly.swift:**
```swift
import Swinject

final class DataAssembly: Assembly {
    func assemble(container: Container) {
        // Database
        container.register(DatabaseCore.self) { resolver in
            // Will be replaced with GRDB in Phase 1 of main plan
            SQLiteDatabase(
                configuration: resolver.resolve(SDKConfiguration.self)!.storage,
                logger: resolver.resolve(SDKLogger.self)!
            )
        }
        .inObjectScope(.container)

        // Repositories
        container.register(ConfigurationRepository.self) { resolver in
            ConfigurationRepositoryImpl(
                database: resolver.resolve(DatabaseCore.self)!,
                apiClient: resolver.resolve(APIClient.self)!,
                logger: resolver.resolve(SDKLogger.self)!
            )
        }

        container.register(ModelMetadataRepository.self) { resolver in
            ModelMetadataRepositoryImpl(
                database: resolver.resolve(DatabaseCore.self)!,
                apiClient: resolver.resolve(APIClient.self)!,
                logger: resolver.resolve(SDKLogger.self)!
            )
        }

        // Continue for all repositories...
    }
}
```

### 3.3 Public API Migration

**PublicAssembly.swift:**
```swift
import Swinject

final class PublicAssembly: Assembly {
    func assemble(container: Container) {
        // Main SDK instance
        container.register(RunAnywhereSDK.self) { resolver in
            RunAnywhereSDK(
                configurationService: resolver.resolve(ConfigurationService.self)!,
                modelLoadingService: resolver.resolve(ModelLoadingService.self)!,
                generationService: resolver.resolve(GenerationService.self)!,
                routingService: resolver.resolve(RoutingService.self)!,
                telemetryService: resolver.resolve(TelemetryService.self)!,
                logger: resolver.resolve(SDKLogger.self)!
            )
        }
        .inObjectScope(.container)
    }
}
```

---

## Phase 4: Cleanup and Documentation (Week 4)

### 4.1 Remove Old Code

**Cleanup Tasks:**
1. Remove old ServiceContainer implementation
2. Delete manual dependency management code
3. Remove raw Alamofire usage
4. Clean up manual factory methods

### 4.2 Documentation Updates

**Documentation Structure:**
```
docs/
├── Architecture/
│   ├── DependencyInjection.md
│   ├── NetworkingLayer.md
│   └── ModularArchitecture.md
├── Guides/
│   ├── AddingNewServices.md
│   ├── CreatingAPIEndpoints.md
│   └── NetworkingGuide.md
└── Migration/
    ├── FromServiceContainer.md
    └── FromAlamofire.md
```

### 4.3 Performance Optimization

**Optimization Tasks:**
1. Profile Swinject resolver performance
2. Optimize assembly loading order
3. Implement lazy registration where appropriate
4. Add resolver caching for hot paths

---

## Implementation Guidelines

### Best Practices

**1. Assembly Organization:**
- One assembly per major feature area
- Keep assemblies focused and cohesive
- Use load-aware assemblies for post-init setup
- Leverage `LoadAwareAssembly` for dependencies between assemblies

**2. Service Registration:**
- Always specify object scopes explicitly
- Use named registrations for variants
- Document complex factory closures
- Consider `.weak` scope for preventing retain cycles
- Use `initCompleted` for circular dependency resolution

**3. Moya Integration:**
- Keep API targets focused on single responsibility
- Use plugins for cross-cutting concerns
- Leverage sample data for testing
- Enable `trackInflights` to prevent duplicate requests
- Use Combine publishers for reactive programming
- Implement proper error mapping with `MoyaError`

**4. Production Readiness:**
- Monitor performance metrics during rollout
- Implement feature flags for gradual adoption
- Keep backward compatibility during migration
- Document breaking changes clearly

**5. Modern Swift Features:**
- Use async/await with Moya via continuations
- Leverage Combine for reactive streams
- Support visionOS with Swinject 2.9+
- Use Swift Concurrency for thread safety

### Migration Strategy

**Phase Approach:**
1. Add frameworks without breaking existing code
2. Create parallel implementations
3. Gradually migrate services
4. Remove old code only after validation
5. Update documentation continuously

### Risk Mitigation

**1. Feature Flags:**
```swift
if FeatureFlags.useSwinject {
    return resolver.resolve(Service.self)!
} else {
    return legacyServiceFactory()
}
```

**2. Gradual Rollout:**
- Start with non-critical services
- Monitor performance metrics
- Gather team feedback
- Full migration after validation

**3. Rollback Plan:**
- Keep ServiceContainer for 2 releases
- Document rollback procedures
- Maintain compatibility layer

---

## Success Metrics

### Code Quality
- [ ] 500+ lines of ServiceContainer code removed
- [ ] All services using dependency injection
- [ ] 100% type-safe API definitions
- [ ] No raw Alamofire usage

### Architecture Quality
- [ ] Clean separation of concerns achieved
- [ ] Modular assembly structure implemented
- [ ] Dependency graph clearly defined
- [ ] No circular dependencies

### Development Experience
- [ ] Onboarding time reduced
- [ ] Consistent patterns across codebase
- [ ] Clear documentation
- [ ] IDE autocomplete for all APIs

### Performance
- [ ] No regression in startup time
- [ ] Memory usage stable
- [ ] Network request deduplication working
- [ ] Binary size increase <5%

---

## Timeline

**Week 1:** Swinject integration and core assemblies
**Week 2:** Moya integration and API implementation
**Week 3:** Service migration to assemblies
**Week 4:** Cleanup and documentation

Total Duration: 4 weeks

---

## Advanced Integration Patterns

### Swift Concurrency Support

**Async/Await with Moya:**
```swift
extension MoyaProvider {
    func request(_ target: Target) async throws -> Response {
        try await withCheckedThrowingContinuation { continuation in
            self.request(target) { result in
                continuation.resume(with: result)
            }
        }
    }
}
```

**Thread-Safe Swinject Resolution:**
```swift
// In production code
let threadSafeResolver = container.synchronize()

// Use in concurrent contexts
Task {
    let service = threadSafeResolver.resolve(ServiceType.self)!
    await service.performWork()
}
```

### Combine Integration

**Reactive Moya Requests:**
```swift
provider.requestPublisher(.fetchModelList)
    .map(ModelListResponse.self)
    .retry(3)
    .receive(on: DispatchQueue.main)
    .sink(
        receiveCompletion: { /* handle */ },
        receiveValue: { /* process */ }
    )
```

### Error Handling Patterns

**Comprehensive Error Mapping:**
```swift
extension MoyaError {
    var runAnywhereError: RunAnywhereError {
        switch self {
        case .statusCode(let response):
            return .apiError(statusCode: response.statusCode)
        case .underlying(let error, _):
            return .networkError(error)
        default:
            return .unknown
        }
    }
}
```

---

## Next Steps

1. Get approval for framework additions
2. Create feature branch `feature/moya-swinject-integration`
3. Start with Swinject CoreAssembly
4. Set up CI/CD for new tests
5. Schedule knowledge sharing sessions

This plan provides a clear path to modernizing the RunAnywhere SDK's architecture with proven, production-ready frameworks that will significantly improve code quality and developer productivity.
