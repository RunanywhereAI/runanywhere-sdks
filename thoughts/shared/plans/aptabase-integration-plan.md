# RunAnywhere Swift SDK - Aptabase Analytics Integration Plan

## Executive Summary

This plan details the integration of Aptabase as the privacy-first analytics solution for the RunAnywhere Swift SDK, replacing the current custom telemetry implementation. The integration will provide simplified, privacy-compliant analytics while removing ~500+ lines of custom code.

**Key Benefits:**
- Privacy-first design with no persistent storage
- Simplified implementation (80% code reduction)
- Automatic platform detection and event batching
- No user tracking or PII collection
- Apple App Store privacy compliance built-in

**Scope:**
- Replace existing telemetry system with Aptabase
- Maintain existing analytics features through Aptabase events
- Clean up legacy telemetry code
- Ensure seamless migration path

---

## Current State Analysis

### Existing Analytics Infrastructure

1. **Custom Telemetry System:**
   - `TelemetryRepository` protocol with database persistence
   - `TelemetryData` entities stored in SQLite/GRDB
   - `DataSyncService` for remote submission
   - Complex event batching and retry logic
   - ~15+ files dedicated to telemetry

2. **Generation Analytics:**
   - `GenerationAnalyticsService` for tracking AI generations
   - Session-based tracking with performance metrics
   - Live metrics streaming
   - Database persistence for historical data

3. **Analytics Configuration:**
   - `AnalyticsConfiguration` with multiple levels
   - `TelemetryConsent` enum (granted/limited/denied)
   - Configurable batch sizes and submission intervals
   - Device and model info inclusion options

4. **Event Types Currently Tracked:**
   ```swift
   enum TelemetryEventType {
       case modelLoaded
       case generationStarted
       case generationCompleted
       case error
       case performance
       case memory
       case custom
   }
   ```

---

## Integration Architecture

### Phase 1: Aptabase Setup & Core Integration

#### 1.1 Add Aptabase Dependency

**Package.swift:**
```swift
dependencies: [
    // ... existing dependencies
    .package(url: "https://github.com/aptabase/aptabase-swift", from: "0.3.4")
],
targets: [
    .target(
        name: "RunAnywhere",
        dependencies: [
            // ... existing dependencies
            "Aptabase"
        ]
    )
]
```

#### 1.2 Create Analytics Abstraction Layer

**Location:** `Sources/RunAnywhere/Foundation/Analytics/`

```swift
// AnalyticsProvider.swift
protocol AnalyticsProvider {
    func initialize(configuration: AnalyticsConfiguration) async throws
    func trackEvent(_ name: String, properties: [String: Any]?) async
    func flush() async
}

// AptabaseAnalyticsProvider.swift
final class AptabaseAnalyticsProvider: AnalyticsProvider {
    func initialize(configuration: AnalyticsConfiguration) async throws
    func trackEvent(_ name: String, properties: [String: Any]?) async
    func flush() async
}
```

#### 1.3 Analytics Service Wrapper

**Location:** `Sources/RunAnywhere/Foundation/Analytics/AnalyticsService.swift`

This service will:
- Manage Aptabase initialization
- Handle consent checking
- Filter events based on analytics level
- Convert internal events to Aptabase format
- Provide backwards compatibility

---

### Phase 2: Event Mapping & Implementation

#### 2.1 Event Schema Design

Map existing telemetry events to Aptabase events:

| Current Event | Aptabase Event | Properties |
|--------------|----------------|------------|
| modelLoaded | model_loaded | model_id, framework, load_time_ms, memory_mb |
| generationStarted | generation_started | model_id, session_id, input_tokens |
| generationCompleted | generation_completed | model_id, session_id, output_tokens, duration_ms, tokens_per_sec |
| error | error_occurred | error_type, error_code, model_id, recovery_attempted |
| performance | performance_metric | metric_type, value, model_id |
| memory | memory_snapshot | used_mb, available_mb, pressure_level |

#### 2.2 Generation Analytics Integration

Convert existing `GenerationAnalyticsService` to use Aptabase:

```swift
// Track generation lifecycle
func trackGenerationStarted(sessionId: String, modelId: String) {
    Aptabase.shared.trackEvent("generation_started", with: [
        "session_id": sessionId,
        "model_id": modelId,
        "framework": currentFramework,
        "device_type": deviceInfo.type
    ])
}

func trackGenerationCompleted(performance: GenerationPerformance) {
    Aptabase.shared.trackEvent("generation_completed", with: [
        "session_id": performance.sessionId,
        "tokens_per_second": performance.tokensPerSecond,
        "time_to_first_token_ms": performance.timeToFirstToken * 1000,
        "total_duration_ms": performance.duration * 1000
    ])
}
```

#### 2.3 Cost & Savings Tracking

Implement cost analytics without storing PII:

```swift
func trackCostSaved(amount: Double, model: String) {
    guard configuration.shouldCollectCostMetrics else { return }

    Aptabase.shared.trackEvent("cost_saved", with: [
        "amount_cents": Int(amount * 100),
        "model": model,
        "routing": "on_device"
    ])
}
```

---

### Phase 3: Privacy & Consent Management

#### 3.1 Consent Integration

Map `TelemetryConsent` to Aptabase behavior:

```swift
extension TelemetryConsent {
    var aptabaseEnabled: Bool {
        switch self {
        case .granted: return true
        case .limited: return true  // Only error events
        case .denied: return false
        }
    }

    func shouldTrackEvent(_ eventName: String) -> Bool {
        switch self {
        case .granted: return true
        case .limited: return eventName.contains("error")
        case .denied: return false
        }
    }
}
```

#### 3.2 Privacy Configuration

Configure Aptabase with RunAnywhere privacy settings:

```swift
private func configureAptabase(apiKey: String, configuration: Configuration) {
    // Determine app key based on environment
    let appKey = configuration.debugMode ? "\(apiKey)-DEV" : apiKey

    // Initialize with privacy settings
    let options = InitOptions(
        flushInterval: NSNumber(value: configuration.analyticsSubmissionInterval),
        trackingMode: configuration.debugMode ? .asDebug : .asRelease
    )

    if configuration.telemetryConsent.aptabaseEnabled {
        Aptabase.shared.initialize(appKey: appKey, with: options)
    }
}
```

---

### Phase 4: Migration & Cleanup

#### 4.1 Files to Remove

**Data Layer:**
- `/Data/Models/DTOs/TelemetryDTO.swift`
- `/Data/Models/Entities/TelemetryData.swift`
- `/Data/Protocols/TelemetryRepository.swift`
- `/Data/Repositories/TelemetryRepositoryImpl.swift`

**Database:**
- Remove telemetry tables from GRDB migrations
- Clean up telemetry-related indexes

**Services:**
- Refactor `DataSyncService` to remove telemetry sync
- Update `GenerationAnalyticsServiceImpl` to use Aptabase
- Remove telemetry batching logic

#### 4.2 Files to Modify

**ServiceContainer.swift:**
- Remove telemetry repository initialization
- Add Aptabase analytics provider
- Update generation analytics to use new provider

**SDKConfiguration.swift:**
- Keep existing analytics configuration
- Add Aptabase-specific options if needed

**RunAnywhereSDK.swift:**
- Update initialization to configure Aptabase
- Maintain existing analytics API surface

#### 4.3 Migration Strategy

1. **Parallel Implementation:**
   - Implement Aptabase alongside existing system
   - Use feature flag to switch between implementations
   - Test thoroughly before removing old code

2. **Data Migration:**
   - No historical data migration (privacy-first approach)
   - Start fresh with Aptabase
   - Document this decision for users

3. **Backwards Compatibility:**
   - Keep existing public APIs unchanged
   - Internal implementation switches to Aptabase
   - Deprecate direct telemetry access methods

---

### Phase 5: Testing & Validation

#### 5.1 Unit Tests

Create comprehensive tests for:
- Analytics provider abstraction
- Event mapping correctness
- Consent filtering
- Property validation
- Batch timing

#### 5.2 Integration Tests

Test scenarios:
- SDK initialization with various consent levels
- Event tracking during generation lifecycle
- Memory pressure event handling
- Error tracking and recovery
- Performance metric collection

#### 5.3 Privacy Validation

Ensure:
- No PII is collected
- Events respect consent settings
- Data doesn't persist on device
- Network failures don't crash app

---

## Implementation Timeline

### Week 1: Foundation
- [ ] Add Aptabase dependency
- [ ] Create analytics abstraction layer
- [ ] Implement AptabaseAnalyticsProvider
- [ ] Add feature flag for rollout

### Week 2: Integration
- [ ] Map all existing events to Aptabase
- [ ] Integrate with GenerationAnalyticsService
- [ ] Update ServiceContainer initialization
- [ ] Implement consent management

### Week 3: Migration
- [ ] Create parallel implementation
- [ ] Add comprehensive logging
- [ ] Test with feature flag enabled
- [ ] Document migration approach

### Week 4: Cleanup
- [ ] Remove legacy telemetry code
- [ ] Update database migrations
- [ ] Clean up unused dependencies
- [ ] Update documentation

### Week 5: Polish
- [ ] Performance optimization
- [ ] Add monitoring for new system
- [ ] Create migration guide
- [ ] Update sample apps

---

## Success Metrics

### Code Quality
- [ ] 500+ lines of code removed
- [ ] Zero telemetry-related database operations
- [ ] Simplified dependency graph
- [ ] All tests passing

### Privacy Compliance
- [ ] No on-device data persistence
- [ ] Consent settings respected
- [ ] Apple App Store privacy compliance
- [ ] GDPR compliance maintained

### Performance
- [ ] Reduced memory footprint
- [ ] Faster SDK initialization
- [ ] No blocking operations
- [ ] Efficient event batching

### Developer Experience
- [ ] Same public API maintained
- [ ] Clear migration documentation
- [ ] Improved debugging tools
- [ ] Simpler configuration

---

## Risk Mitigation

### Technical Risks

1. **Event Loss During Migration**
   - Mitigation: Parallel implementation with feature flag
   - Rollback: Keep old system for 2 versions

2. **Performance Regression**
   - Mitigation: Benchmark before/after
   - Monitor: CPU and memory usage

3. **API Breaking Changes**
   - Mitigation: Maintain compatibility layer
   - Deprecation: Follow semantic versioning

### Business Risks

1. **Analytics Data Gap**
   - Mitigation: Document clearly in changelog
   - Solution: Export old data before migration

2. **Customer Confusion**
   - Mitigation: Comprehensive migration guide
   - Support: FAQ and examples

---

## Next Steps

1. **Review & Approval**
   - Get stakeholder approval
   - Review privacy implications
   - Confirm timeline

2. **Preparation**
   - Set up feature branches
   - Configure CI/CD
   - Prepare test environments

3. **Execution**
   - Follow implementation phases
   - Regular progress updates
   - Continuous testing

This plan provides a clear path to modernizing the RunAnywhere SDK's analytics infrastructure while maintaining privacy, improving performance, and reducing complexity.
