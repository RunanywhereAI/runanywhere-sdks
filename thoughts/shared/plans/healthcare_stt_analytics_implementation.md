# Healthcare STT Analytics Implementation Plan

## Overview
This document provides a step-by-step implementation plan for adding analytics to the existing STT and speaker diarization pipeline, focusing on minimal code changes and maximum value delivery.

## Current System Analysis

### Existing Integration Points
1. **TranscriptionViewModel.swift** (lines 278-349): `handlePipelineEvent()` method
2. **WhisperKitService.swift** (lines 88-139): `transcribe()` method
3. **ModularPipelineEvent** enum: Already captures key events
4. **VoicePipelineManager**: Event delegation system

### Available Data Points (No Code Changes Needed)
- Session start/stop timestamps
- Speaker detection events
- Transcription confidence from WhisperKit
- Processing latency measurements
- Error events and messages
- Audio duration and quality metrics

## Implementation Plan

### Phase 1: Data Collection Infrastructure (Week 1)

#### 1.1 Create Analytics Models
```swift
// Add to SDK: Sources/RunAnywhere/Public/Models/Analytics/
struct SessionAnalytics: Codable {
    let sessionId: String
    let timestamp: Date
    let duration: TimeInterval
    let totalWords: Int
    let speakerCount: Int
    let whisperModel: String
    let completionStatus: String
}

struct QualityMetrics: Codable {
    let sessionId: String
    let confidence: Float
    let processingLatency: TimeInterval
    let speechToSilenceRatio: Float
    let errorCount: Int
}

struct SpeakerMetrics: Codable {
    let sessionId: String
    let totalSpeakers: Int
    let primarySpeakerRatio: Float
    let speakerSwitchCount: Int
}
```

#### 1.2 Create Analytics Service
```swift
// Add to SDK: Sources/RunAnywhere/Capabilities/Analytics/
class TranscriptionAnalyticsService {
    private let networkService: NetworkService
    private var currentSession: AnalyticsSession?

    func startSession(whisperModel: String) -> String
    func recordEvent(_ event: AnalyticsEvent)
    func endSession(status: String)
    func sendBatch() async
}
```

### Phase 2: Integration Points (Week 2)

#### 2.1 Modify TranscriptionViewModel
**File**: `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/TranscriptionViewModel.swift`

**Changes**:
```swift
// Add property
private let analyticsService = TranscriptionAnalyticsService()
private var sessionStartTime: Date?
private var speakerSwitchCount = 0

// Modify startTranscription() method (line 102)
func startTranscription() async {
    // Existing code...
    sessionStartTime = Date()
    let sessionId = analyticsService.startSession(whisperModel: whisperModel)
    // Existing code...
}

// Modify stopTranscription() method (line 194)
func stopTranscription() async {
    // Existing code...
    if let startTime = sessionStartTime {
        let duration = Date().timeIntervalSince(startTime)
        analyticsService.endSession(
            duration: duration,
            wordCount: finalTranscripts.map { $0.text.split(separator: " ").count }.reduce(0, +),
            speakerCount: detectedSpeakers.count,
            status: "completed"
        )
    }
    // Existing code...
}

// Modify handlePipelineEvent() method (line 278)
private func handlePipelineEvent(_ event: ModularPipelineEvent) async {
    // Add analytics collection
    analyticsService.recordEvent(event)

    // Existing event handling code...
    switch event {
    case .sttSpeakerChanged:
        speakerSwitchCount += 1
    // Existing cases...
    }
}
```

#### 2.2 Modify WhisperKitService
**File**: `sdk/runanywhere-swift/Modules/WhisperKitTranscription/Sources/WhisperKitTranscription/WhisperKitService.swift`

**Changes**:
```swift
// Add to transcribe() method (line 88)
func transcribe(samples: [Float], options: VoiceTranscriptionOptions) async throws -> VoiceTranscriptionResult {
    let startTime = Date()

    // Existing transcription code...

    let endTime = Date()
    let latency = endTime.timeIntervalSince(startTime)

    // Record metrics
    AnalyticsService.shared.recordLatency(latency)
    AnalyticsService.shared.recordConfidence(result.confidence)

    return result
}
```

### Phase 3: Network Integration (Week 2-3)

#### 3.1 Add to Existing Network Layer
**File**: Update existing network service or create new analytics endpoint

```swift
extension NetworkService {
    func sendAnalytics(_ data: [String: Any]) async throws {
        let endpoint = "/analytics/transcription"
        try await post(endpoint: endpoint, data: data)
    }
}
```

#### 3.2 Batch Upload Strategy
```swift
class AnalyticsBatchUploader {
    private var batch: [AnalyticsEvent] = []
    private let batchSize = 50
    private let uploadInterval: TimeInterval = 300 // 5 minutes

    func add(_ event: AnalyticsEvent) {
        batch.append(event)
        if batch.count >= batchSize {
            Task { await uploadBatch() }
        }
    }

    private func uploadBatch() async {
        // Upload and clear batch
    }
}
```

### Phase 4: Dashboard Backend (Week 3-4)

#### 4.1 Analytics API Endpoints
```
POST /api/analytics/transcription/session
POST /api/analytics/transcription/events
GET  /api/analytics/dashboard/realtime
GET  /api/analytics/dashboard/quality
GET  /api/analytics/dashboard/usage
```

#### 4.2 Database Schema
```sql
-- Sessions table
CREATE TABLE transcription_sessions (
    session_id VARCHAR(255) PRIMARY KEY,
    timestamp TIMESTAMP,
    duration_seconds FLOAT,
    word_count INTEGER,
    speaker_count INTEGER,
    whisper_model VARCHAR(100),
    completion_status VARCHAR(50)
);

-- Quality metrics table
CREATE TABLE quality_metrics (
    session_id VARCHAR(255),
    confidence FLOAT,
    processing_latency_ms FLOAT,
    speech_silence_ratio FLOAT,
    error_count INTEGER,
    FOREIGN KEY (session_id) REFERENCES transcription_sessions(session_id)
);

-- Events table
CREATE TABLE transcription_events (
    event_id VARCHAR(255) PRIMARY KEY,
    session_id VARCHAR(255),
    event_type VARCHAR(100),
    timestamp TIMESTAMP,
    metadata JSON,
    FOREIGN KEY (session_id) REFERENCES transcription_sessions(session_id)
);
```

### Phase 5: Dashboard Frontend (Week 4-5)

#### 5.1 Real-Time Dashboard Components
```typescript
// Real-time metrics component
const RealTimeMetrics = () => {
    const [metrics, setMetrics] = useState(null);

    useEffect(() => {
        const ws = new WebSocket('/ws/analytics/realtime');
        ws.onmessage = (event) => {
            setMetrics(JSON.parse(event.data));
        };
    }, []);

    return (
        <div className="dashboard">
            <MetricCard title="Active Sessions" value={metrics?.activeSessions} />
            <MetricCard title="Avg Latency" value={`${metrics?.avgLatency}ms`} />
            <MetricCard title="Success Rate" value={`${metrics?.successRate}%`} />
        </div>
    );
};
```

#### 5.2 Key Dashboard Views
1. **Operations Dashboard**: Live sessions, system health, alerts
2. **Quality Dashboard**: Confidence trends, error rates, latency charts
3. **Usage Dashboard**: Session volume, peak times, user adoption

## Implementation Details

### Minimal Code Changes Required

#### TranscriptionViewModel Changes
```swift
// Add these 3 lines to existing methods:
private let analytics = AnalyticsService.shared

// In startTranscription():
analytics.startSession(model: whisperModel)

// In stopTranscription():
analytics.endSession(wordCount: totalWords, speakers: detectedSpeakers.count)

// In handlePipelineEvent():
analytics.recordEvent(event)
```

#### WhisperKitService Changes
```swift
// Add these 2 lines to transcribe() method:
let startTime = Date()
// ... existing code ...
AnalyticsService.shared.recordLatency(Date().timeIntervalSince(startTime))
```

### Data Flow
1. **Event Collection**: TranscriptionViewModel + WhisperKitService collect metrics
2. **Local Storage**: SQLite for offline capability
3. **Batch Upload**: Every 5 minutes or 50 events
4. **Backend Processing**: Store in PostgreSQL/MySQL
5. **Dashboard Updates**: WebSocket for real-time updates

### Privacy Safeguards
```swift
struct AnalyticsEvent {
    let sessionId: String // UUID only
    let eventType: String
    let timestamp: Date
    let metrics: [String: Any] // No text content

    // Explicitly exclude sensitive data
    private let excludedFields = ["text", "transcript", "audio"]
}
```

## Testing Strategy

### Unit Tests
- Analytics data collection accuracy
- Privacy data filtering
- Batch upload functionality
- Error handling

### Integration Tests
- End-to-end analytics flow
- Network failure scenarios
- Dashboard data accuracy
- Real-time updates

### Performance Tests
- Analytics overhead on transcription
- Memory usage with analytics enabled
- Network bandwidth usage
- Dashboard response times

## Rollout Plan

### Week 1: Foundation
- Create analytics models and service
- Add basic event collection
- Set up local storage

### Week 2: Integration
- Integrate with TranscriptionViewModel
- Add WhisperKit metrics collection
- Implement batch uploading

### Week 3: Backend
- Create analytics API endpoints
- Set up database schema
- Implement data processing

### Week 4: Dashboard
- Build real-time operations dashboard
- Create quality metrics views
- Add usage analytics

### Week 5: Testing & Polish
- Comprehensive testing
- Performance optimization
- Documentation and training

## Success Metrics

### Technical Metrics
- < 5ms additional latency from analytics
- 99.9% data collection reliability
- < 1MB memory overhead
- < 100KB/hour network usage

### Business Metrics
- 100% visibility into transcription sessions
- Real-time error detection and alerting
- Historical trend analysis capability
- Actionable insights for improvement

## Risk Mitigation

### Privacy Risks
- **Mitigation**: Strict data filtering, no text storage
- **Testing**: Automated privacy validation tests

### Performance Risks
- **Mitigation**: Asynchronous collection, batched uploads
- **Testing**: Load testing with analytics enabled

### Reliability Risks
- **Mitigation**: Local storage fallback, retry mechanisms
- **Testing**: Network failure simulation

## Next Actions

1. **Review & Approve**: Get stakeholder approval for this plan
2. **Environment Setup**: Create analytics database and API endpoints
3. **Phase 1 Implementation**: Start with core data collection
4. **Testing**: Implement unit tests alongside development
5. **Documentation**: Create developer documentation for analytics integration

---

**Implementation Timeline**: 5 weeks
**Resource Requirements**: 1 backend developer, 1 frontend developer
**Dependencies**: Existing network layer, database infrastructure
