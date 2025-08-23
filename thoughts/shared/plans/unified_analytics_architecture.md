# Unified Analytics Architecture for RunAnywhere SDK

## Overview
This document defines a unified, scalable analytics architecture that consolidates the various analytics patterns currently in the SDK into a single, cohesive system following SOLID principles.

## Current State Analysis

### Existing Analytics Services (Fragmented)
1. **GenerationAnalyticsService** - Actor-based session tracking
2. **VoiceAnalyticsService** - Class with DispatchQueue for voice metrics
3. **TelemetryRepository** - Event-based telemetry with backend sync
4. **MonitoringService** - Real-time performance monitoring
5. **PerformanceMonitor** - Protocol for monitoring

### Problems with Current Approach
- **Inconsistent Patterns**: Actor vs Class vs Protocol
- **Duplicate Code**: Each service implements its own metrics storage
- **No Unified Queue**: Each service manages threading differently
- **Fragmented Data**: Analytics spread across multiple services
- **Complex Integration**: Hard to add new analytics types

## Proposed Unified Architecture

### Core Components

```swift
// 1. Core Analytics Protocol - All analytics services conform to this
public protocol AnalyticsService: Actor {
    associatedtype Event: AnalyticsEvent
    associatedtype Metrics: AnalyticsMetrics

    // Event tracking
    func track(event: Event) async
    func trackBatch(events: [Event]) async

    // Metrics
    func getMetrics() async -> Metrics
    func clearMetrics(olderThan: Date) async

    // Session management
    func startSession(metadata: SessionMetadata) async -> String
    func endSession(sessionId: String) async

    // Health
    func isHealthy() async -> Bool
}

// 2. Unified Event System
public protocol AnalyticsEvent: Sendable, Codable {
    var id: String { get }
    var type: String { get }
    var timestamp: Date { get }
    var sessionId: String? { get }
    var properties: [String: String] { get }
}

// 3. Metrics Protocol
public protocol AnalyticsMetrics: Sendable {
    var totalEvents: Int { get }
    var startTime: Date { get }
    var lastEventTime: Date? { get }
}

// 4. Analytics Queue Manager - Central queue for all analytics
public actor AnalyticsQueueManager {
    private var eventQueue: [any AnalyticsEvent] = []
    private let batchSize: Int = 50
    private let flushInterval: TimeInterval = 30.0
    private let telemetryRepository: TelemetryRepository

    // Singleton for centralized management
    public static let shared = AnalyticsQueueManager()

    // Queue management
    public func enqueue(_ event: any AnalyticsEvent) async
    public func enqueueBatch(_ events: [any AnalyticsEvent]) async
    private func flush() async
    private func processBatch(_ batch: [any AnalyticsEvent]) async
}

// 5. Base Analytics Service - Reusable base implementation
public actor BaseAnalyticsService<Event: AnalyticsEvent, Metrics: AnalyticsMetrics> {
    protected let queueManager: AnalyticsQueueManager
    protected let logger: SDKLogger
    protected var currentSession: SessionInfo?
    protected var events: [Event] = []

    // Template method pattern for common functionality
    public func track(event: Event) async {
        events.append(event)
        await queueManager.enqueue(event)
        await processEvent(event)  // Hook for subclasses
    }

    // Subclasses override for custom processing
    open func processEvent(_ event: Event) async {}
}
```

### Concrete Implementations

```swift
// 1. STT Analytics Service - Follows unified pattern
public actor STTAnalyticsService: BaseAnalyticsService<STTEvent, STTMetrics> {

    // STT-specific tracking
    public func trackTranscription(
        text: String,
        confidence: Float,
        duration: TimeInterval,
        audioLength: TimeInterval,
        speaker: SpeakerInfo?
    ) async {
        let event = STTEvent(
            type: .transcriptionCompleted,
            sessionId: currentSession?.id,
            properties: [
                "word_count": String(text.split(separator: " ").count),
                "confidence": String(confidence),
                "duration_ms": String(duration * 1000),
                "audio_length_ms": String(audioLength * 1000),
                "real_time_factor": String(duration / audioLength),
                "speaker_id": speaker?.id ?? "unknown"
            ]
        )
        await track(event: event)
    }

    public func trackSpeakerChange(from: SpeakerInfo?, to: SpeakerInfo) async {
        let event = STTEvent(
            type: .speakerChanged,
            sessionId: currentSession?.id,
            properties: [
                "from_speaker": from?.id ?? "none",
                "to_speaker": to.id,
                "timestamp": String(Date().timeIntervalSince1970)
            ]
        )
        await track(event: event)
    }

    override func processEvent(_ event: STTEvent) async {
        // STT-specific processing
        updateQualityMetrics(from: event)
        updateSpeakerMetrics(from: event)
    }
}

// 2. Generation Analytics - Migrated to unified pattern
public actor GenerationAnalyticsServiceV2: BaseAnalyticsService<GenerationEvent, GenerationMetrics> {
    // Existing functionality adapted to new pattern
}

// 3. Voice Analytics - Migrated to unified pattern
public actor VoiceAnalyticsServiceV2: BaseAnalyticsService<VoiceEvent, VoiceMetrics> {
    // Existing functionality adapted to new pattern
}
```

### Event Queue System

```swift
// Centralized event queue with batching and retry logic
extension AnalyticsQueueManager {

    private actor EventQueue {
        private var queue: [any AnalyticsEvent] = []
        private var processing = false
        private let maxRetries = 3

        func add(_ event: any AnalyticsEvent) {
            queue.append(event)
            if queue.count >= batchSize && !processing {
                Task { await processBatch() }
            }
        }

        private func processBatch() async {
            processing = true
            defer { processing = false }

            let batch = Array(queue.prefix(batchSize))
            guard !batch.isEmpty else { return }

            do {
                // Convert to telemetry events
                let telemetryEvents = batch.map { event in
                    TelemetryData(
                        eventType: event.type,
                        properties: event.properties,
                        timestamp: event.timestamp
                    )
                }

                // Send to backend via existing telemetry repository
                try await telemetryRepository.trackBatch(telemetryEvents)

                // Remove successfully sent events
                queue.removeFirst(batch.count)

            } catch {
                // Retry logic with exponential backoff
                await retryBatch(batch, attempt: 1)
            }
        }

        private func retryBatch(_ batch: [any AnalyticsEvent], attempt: Int) async {
            guard attempt <= maxRetries else {
                // Log failed events and move on
                logger.error("Failed to send batch after \(maxRetries) attempts")
                queue.removeFirst(batch.count)
                return
            }

            // Exponential backoff
            let delay = pow(2.0, Double(attempt))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            await processBatch()
        }
    }
}
```

### Integration Points

```swift
// 1. Service Container Registration
extension ServiceContainer {
    // Unified analytics services registration
    public var analyticsQueueManager: AnalyticsQueueManager {
        AnalyticsQueueManager.shared
    }

    public var sttAnalytics: STTAnalyticsService {
        get async {
            await STTAnalyticsService(queueManager: analyticsQueueManager)
        }
    }

    public var generationAnalytics: GenerationAnalyticsServiceV2 {
        get async {
            await GenerationAnalyticsServiceV2(queueManager: analyticsQueueManager)
        }
    }
}

// 2. Easy Integration in Handlers
extension STTHandler {
    private let analytics: STTAnalyticsService

    func transcribeAudio(...) async throws -> String {
        let startTime = Date()

        // Track start event
        await analytics.track(event: STTEvent(type: .transcriptionStarted))

        // Perform transcription
        let result = try await performTranscription(...)

        // Track completion with metrics
        await analytics.trackTranscription(
            text: result,
            confidence: extractConfidence(result),
            duration: Date().timeIntervalSince(startTime),
            audioLength: audioData.duration,
            speaker: currentSpeaker
        )

        return result
    }
}

// 3. Pipeline Event Integration
extension VoicePipelineManager {
    func handleEvent(_ event: ModularPipelineEvent) async {
        // Convert pipeline events to analytics events
        switch event {
        case .sttFinalTranscript(let text):
            await sttAnalytics.track(event: STTEvent(
                type: .finalTranscript,
                properties: ["text_length": String(text.count)]
            ))

        case .sttSpeakerChanged(let from, let to):
            await sttAnalytics.trackSpeakerChange(from: from, to: to)

        // ... other events
        }
    }
}
```

## Migration Strategy

### ✅ Phase 1: Core Infrastructure (Completed)
1. ✅ Implemented `AnalyticsService` protocol
2. ✅ Implemented `AnalyticsQueueManager`
3. ✅ Created `BaseAnalyticsService` actor
4. ✅ Created event and metrics protocols

### ✅ Phase 2: Service Migration (Completed)
1. ✅ Created `STTAnalyticsService` using new pattern
2. ✅ Migrated `GenerationAnalyticsService` to new pattern
3. ✅ Migrated `VoiceAnalyticsService` to new pattern
4. ✅ Created `MonitoringAnalyticsService` for performance tracking
5. ✅ Updated integration points

### ✅ Phase 3: Clean-up (Completed)
1. ✅ Removed old GenerationAnalyticsServiceImpl
2. ✅ Removed old VoiceAnalyticsService
3. ✅ Removed old protocol definitions
4. ✅ Removed old repository implementations
5. ✅ Updated ServiceContainer with new services
6. ✅ Integrated with existing TelemetryRepository for backend sync

## Benefits of Unified Architecture

### 1. **Consistency**
- Single pattern for all analytics (Actor-based)
- Unified event system
- Consistent session management

### 2. **Scalability**
- Centralized queue management
- Automatic batching and retry
- Easy to add new analytics types

### 3. **Performance**
- Non-blocking event tracking
- Efficient batch processing
- Shared queue reduces overhead

### 4. **Maintainability**
- DRY principle - no duplicate code
- Clear separation of concerns
- Easy to test and mock

### 5. **SOLID Compliance**
- **S**: Each service has single responsibility
- **O**: Open for extension via inheritance
- **L**: Services are substitutable via protocol
- **I**: Focused protocols for each domain
- **D**: Depends on abstractions (protocols)

## Configuration

```swift
public struct AnalyticsConfiguration {
    public let enabled: Bool = true
    public let batchSize: Int = 50
    public let flushInterval: TimeInterval = 30.0
    public let maxQueueSize: Int = 1000
    public let maxRetries: Int = 3
    public let endpoint: URL?
    public let offlineStorage: Bool = true
    public let privacyMode: PrivacyMode = .standard
}
```

## Privacy Considerations

```swift
public enum PrivacyMode {
    case strict    // No PII, minimal data
    case standard  // Session IDs, metrics only
    case detailed  // Full analytics (with consent)
}

extension BaseAnalyticsService {
    func sanitizeEvent(_ event: Event) -> Event {
        switch configuration.privacyMode {
        case .strict:
            // Remove all potentially identifying information
            return event.stripped()
        case .standard:
            // Keep metrics, remove text content
            return event.sanitized()
        case .detailed:
            // Return as-is (user consented)
            return event
        }
    }
}
```

## Testing Strategy

```swift
// Mock analytics for testing
public actor MockAnalyticsService<Event: AnalyticsEvent, Metrics: AnalyticsMetrics>: AnalyticsService {
    public var trackedEvents: [Event] = []

    public func track(event: Event) async {
        trackedEvents.append(event)
    }

    public func verifyEvent(matching predicate: (Event) -> Bool) -> Bool {
        trackedEvents.contains(where: predicate)
    }
}

// Test example
func testSTTAnalytics() async {
    let mockAnalytics = MockAnalyticsService<STTEvent, STTMetrics>()
    let handler = STTHandler(analytics: mockAnalytics)

    _ = try await handler.transcribeAudio(testAudio)

    XCTAssertTrue(
        await mockAnalytics.verifyEvent { $0.type == .transcriptionCompleted }
    )
}
```

## Monitoring & Observability

```swift
extension AnalyticsQueueManager {
    public struct QueueMetrics {
        public let queueSize: Int
        public let eventsProcessed: Int
        public let eventsFailed: Int
        public let averageLatency: TimeInterval
        public let lastFlush: Date
    }

    public func getQueueMetrics() async -> QueueMetrics {
        // Return current queue statistics
    }

    public func observeQueueMetrics() -> AsyncStream<QueueMetrics> {
        // Stream real-time queue metrics
    }
}
```

## Implementation Summary

### Completed Implementation Details

The unified analytics architecture has been successfully implemented with the following structure:

#### Core Components Created:
1. **UnifiedAnalytics.swift** - Core protocol definitions
   - `AnalyticsService` protocol with associated types
   - `AnalyticsEvent` and `AnalyticsMetrics` protocols
   - `SessionMetadata` struct for session management

2. **AnalyticsQueueManager.swift** - Centralized queue management
   - Singleton pattern for central management
   - Batch processing (50 events per batch)
   - Automatic retry with exponential backoff
   - 30-second flush interval
   - Direct integration with TelemetryRepository

3. **BaseAnalyticsService.swift** - Reusable base implementation
   - Template method pattern for event processing
   - Common session management
   - Event tracking with queue integration

#### Migrated Services:
1. **STTAnalyticsService** - Speech-to-text analytics
   - Transcription tracking with confidence scores
   - Speaker change detection
   - Language detection tracking
   - Partial and final transcript events

2. **GenerationAnalyticsService** - Text generation analytics
   - Generation lifecycle tracking
   - First token and streaming updates
   - Model loading/unloading events
   - Token count and performance metrics

3. **VoiceAnalyticsService** - Voice processing analytics
   - Pipeline creation and execution
   - Transcription performance metrics
   - Stage execution tracking
   - Real-time factor calculations

4. **MonitoringAnalyticsService** - System monitoring
   - CPU and memory usage tracking
   - Memory warnings and pressure events
   - Disk space monitoring
   - Network latency tracking

#### Integration Points:
- ServiceContainer updated with all new analytics services
- VoiceCapabilityService integrated with new async analytics
- Direct backend sync via existing TelemetryRepository
- No local database storage (as requested)

#### Removed Components:
- Old GenerationAnalyticsServiceImpl
- Old VoiceAnalyticsService (class-based)
- Old GenerationAnalytics protocol directory
- Old repository implementations
- Fragmented analytics patterns

## Summary

This unified analytics architecture provides:
- ✅ **Single consistent pattern** for all analytics
- ✅ **Centralized queue management** with batching
- ✅ **Automatic retry logic** with exponential backoff
- ✅ **Easy service creation** via base class
- ✅ **Type-safe events** with protocols
- ✅ **Privacy-first design** with sanitization
- ✅ **Testable architecture** with mocks
- ✅ **Observable metrics** for monitoring
- ✅ **SOLID principles** compliance
- ✅ **Minimal migration effort** from existing services
