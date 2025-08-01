# SDK Integration and Cleanup Plan

## Overview
This plan outlines how to integrate the existing SDK implementation with the new unified architecture from Phase 1, eliminating duplications and ensuring a clean, cohesive SDK structure.

## Analysis of Existing Implementation

### Current Files:
1. **Configuration.swift** - SDK configuration with routing policies
2. **GenerationOptions.swift** - Generation parameters
3. **GenerationResult.swift** - Generation results
4. **RunAnywhereSDK.swift** - Main SDK entry point
5. **Types.swift** - Internal types for routing

### Identified Issues:
1. **Duplication**: Context and Message structures exist in both Configuration.swift and LLMService.swift
2. **Missing Integration**: ExecutionTarget enum could be mapped to HardwareAcceleration
3. **Incomplete Implementation**: RunAnywhereSDK has many TODOs and needs integration with new components
4. **Routing System**: Internal types for routing need to be integrated with the new architecture

## Integration Strategy

### 1. Merge Duplicate Structures

#### Context and Message
- **Keep**: The existing Context and Message in Configuration.swift (already public)
- **Remove**: GenerationContext and Message from LLMService.swift
- **Update**: LLMService protocol to use the existing public types

### 2. Enhance Existing Types

#### Configuration.swift
- Add model-specific configuration options
- Integrate with HardwareConfiguration
- Add framework preferences
- Add model provider authentication settings

#### GenerationOptions.swift
- Already well-structured
- Add framework-specific options
- Add streaming configuration
- Add token budget constraints

#### GenerationResult.swift
- Add framework information
- Add detailed performance metrics
- Add memory usage statistics
- Add tokenizer information

### 3. Bridge Execution Concepts

Map ExecutionTarget to our new architecture:
- `onDevice` → Use FrameworkAdapter with local models
- `cloud` → Use cloud provider APIs
- `hybrid` → Use both based on token splitting

### 4. Complete RunAnywhereSDK Implementation

Integrate with:
- ModelLifecycleStateMachine
- UnifiedTokenizerManager
- HardwareCapabilityManager
- FrameworkAdapterRegistry (from sample app)
- DynamicModelRegistry
- EnhancedDownloadManager

## Detailed Changes

### 1. Configuration.swift Updates

```swift
public struct Configuration {
    // ... existing fields ...

    // New fields for unified architecture
    public var preferredFrameworks: [LLMFramework]
    public var hardwarePreferences: HardwareConfiguration?
    public var modelProviders: [ModelProviderConfig]
    public var memoryThreshold: Int64
    public var downloadConfiguration: DownloadConfig
}

public struct ModelProviderConfig {
    public let provider: String
    public let credentials: ProviderCredentials?
    public let enabled: Bool
}

public struct DownloadConfig {
    public let maxConcurrentDownloads: Int
    public let retryAttempts: Int
    public let cacheDirectory: URL?
}
```

### 2. Remove Duplicates from LLMService.swift

- Remove GenerationContext (use Context from Configuration.swift)
- Remove nested Message struct (use Message from Configuration.swift)
- Update protocol to reference the public types

### 3. Enhance GenerationResult.swift

```swift
public struct GenerationResult {
    // ... existing fields ...

    // New fields
    public let framework: LLMFramework?
    public let hardwareUsed: HardwareAcceleration
    public let memoryUsed: Int64
    public let tokenizerFormat: TokenizerFormat?
    public let performanceMetrics: PerformanceMetrics
}

public struct PerformanceMetrics {
    public let tokenizationTimeMs: TimeInterval
    public let inferenceTimeMs: TimeInterval
    public let postProcessingTimeMs: TimeInterval
    public let tokensPerSecond: Double
}
```

### 4. Update RunAnywhereSDK.swift

Complete the implementation by:
- Injecting unified components
- Implementing model loading with lifecycle management
- Adding framework adapter selection
- Implementing intelligent routing
- Adding progress tracking
- Adding error recovery

### 5. Integrate Types.swift

Connect internal routing types with the new architecture:
- RoutingDecision maps to framework selection
- RoutingReason provides context for framework choice
- InferenceRequest wraps user requests with metadata

## Implementation Order

1. **First**: Update LLMService.swift to remove duplicates
2. **Second**: Enhance Configuration.swift with new fields
3. **Third**: Update GenerationResult.swift with performance metrics
4. **Fourth**: Complete RunAnywhereSDK.swift implementation
5. **Fifth**: Integrate Types.swift with routing logic

## Benefits

1. **No Duplication**: Single source of truth for each type
2. **Clean Architecture**: Clear separation between public API and internal implementation
3. **Extensibility**: Easy to add new frameworks and providers
4. **Type Safety**: Consistent types throughout the SDK
5. **Better Integration**: Seamless connection between existing and new components
