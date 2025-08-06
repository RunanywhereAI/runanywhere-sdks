# Architecture Comparison: Current vs Proposed

## Current Architecture Issues

### 1. Mixed Concerns in Capabilities
```
Capabilities/Repository/          ❌ Data persistence in capability
├── Implementations/             ❌ Storage logic mixed with business
├── Models/                      ❌ Data models mixed with domain
├── Protocols/
└── Services/                    ❌ Network calls in business logic
```

### 2. Confusing Module Responsibilities
```
Infrastructure/
├── DependencyInjection/         ❌ Should be in Foundation
└── Hardware/                    ❌ Has business logic, should be capability

Core/
├── Compatibility/               ❌ Unclear purpose
├── Models/                      ❌ Mixed model types
└── Protocols/                   ❌ No clear organization
```

### 3. String-based Configuration
```swift
// Current - Error prone
analyticsLevel: String = "detailed"
routingPolicy: String = "deviceOnly"

// Proposed - Type safe
analyticsLevel: AnalyticsLevel = .detailed
routingPolicy: RoutingPolicy = .deviceOnly
```

## Proposed Architecture Benefits

### 1. Clean Capability Structure
```
Capabilities/TextGeneration/
├── Services/                    ✅ Pure business logic
│   └── GenerationService.swift  ✅ No data access code
├── Models/                      ✅ Domain models only
│   └── GenerationResult.swift   ✅ Business objects
└── Protocols/                   ✅ Capability contracts
    └── TextGenerator.swift      ✅ Clean interfaces
```

### 2. Dedicated Data Module
```
Data/
├── Protocols/                   ✅ Repository contracts
│   └── Repository.swift
├── Storage/                     ✅ All persistence logic
│   ├── SQLiteDatabase.swift
│   └── FileStorage.swift
├── Network/                     ✅ All API calls
│   └── APIClient.swift
└── Repositories/                ✅ Data access implementations
    └── ConfigurationRepo.swift
```

### 3. Clear Module Responsibilities

| Module | Current Responsibility | Proposed Responsibility |
|--------|----------------------|------------------------|
| **Public** | User-facing APIs | User-facing APIs ✅ |
| **Capabilities** | Business + Data + Storage | Pure Business Logic ✅ |
| **Core** | Mixed protocols/models | Shared Types & Contracts ✅ |
| **Data** | (Doesn't exist) | All Data Access ✅ |
| **Infrastructure** | Platform + DI + Hardware | Platform-specific only ✅ |
| **Foundation** | Utilities | Utilities + DI + Logging ✅ |

## Configuration Refactoring Example

### Current Monolithic Structure
```swift
struct ConfigurationData: Codable {
    // 30+ flat properties mixed together
    var routingPolicy: String
    var analyticsEnabled: Bool
    var analyticsLevel: String
    var temperature: Float
    var maxTokens: Int
    var apiKey: String?
    var cloudRoutingEnabled: Bool
    var privacyModeEnabled: Bool
    // ... many more
}
```

### Proposed Composable Structure
```swift
struct ConfigurationData: Codable {
    var routing: RoutingConfiguration
    var analytics: AnalyticsConfiguration
    var generation: GenerationConfiguration
    var storage: StorageConfiguration
}

struct RoutingConfiguration: Codable {
    var policy: RoutingPolicy          // Enum
    var cloudEnabled: Bool
    var privacyMode: PrivacyMode      // Enum
}

struct AnalyticsConfiguration: Codable {
    var enabled: Bool
    var level: AnalyticsLevel          // Enum
    var liveMetricsEnabled: Bool
}
```

## Data Flow Comparison

### Current: Capability handles everything
```
User Request
    ↓
Capability
    ├── Business Logic
    ├── Database Access    ❌
    ├── Network Calls      ❌
    └── File Storage       ❌
```

### Proposed: Clean separation
```
User Request
    ↓
Capability (Business Logic)
    ↓
Repository Protocol (Contract)
    ↓
Data Module (Implementation)
    ├── Database Access    ✅
    ├── Network Calls      ✅
    └── File Storage       ✅
```

## Example: TextGeneration Refactoring

### Before
```swift
// In TextGenerationService.swift
class GenerationService {
    func generate() async {
        // Business logic
        let processed = processPrompt(prompt)

        // ❌ Direct database access
        let config = try await database.getConfiguration()

        // ❌ Direct network call
        let response = await apiClient.generate(processed)

        // ❌ Direct storage access
        await fileManager.saveResult(response)
    }
}
```

### After
```swift
// In TextGenerationService.swift
class GenerationService {
    let configRepo: ConfigurationRepository  // Protocol from Data module
    let analyticsRepo: AnalyticsRepository   // Protocol from Data module

    func generate() async {
        // ✅ Pure business logic
        let processed = processPrompt(prompt)

        // ✅ Use repository protocol
        let config = try await configRepo.getConfiguration()

        // ✅ Business logic delegates to capability
        let result = await routingCapability.route(processed, config)

        // ✅ Use repository to persist
        await analyticsRepo.recordGeneration(result)
    }
}
```

## Benefits Summary

1. **Testability**: Mock repositories easily
2. **Flexibility**: Swap data implementations
3. **Clarity**: Each module has one job
4. **Maintainability**: Changes isolated
5. **Type Safety**: Enums prevent errors
6. **Scalability**: Easy to add new capabilities

## Migration Impact

| Change | Risk | Impact | Benefit |
|--------|------|--------|---------|
| Move DI to Foundation | Low | Medium | Better organization |
| Create Data Module | Medium | High | Clean separation |
| Enum Configuration | Low | High | Type safety |
| Refactor Capabilities | High | High | Maintainability |
| Hardware → Capability | Low | Medium | Consistency |
