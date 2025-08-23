# Healthcare STT Analytics Specification v1.0

## Executive Summary
This document defines the bare minimum, highest-value analytics for healthcare Speech-to-Text transcription service used by doctors for recording patient encounters and generating SOAP summaries.

## High-Value Analytics (MVP)

### 1. Session Metrics
**Why Critical**: Track overall system usage and performance for healthcare environments

```swift
struct SessionMetrics {
    let sessionId: String
    let timestamp: Date
    let duration: TimeInterval
    let totalWords: Int
    let speakerCount: Int
    let whisperModel: String
    let completionStatus: String // "completed", "error", "interrupted"
}
```

**Dashboard Value**:
- Session volume trends
- Average session duration
- Success/failure rates
- Model performance comparison

### 2. Real-Time Quality Metrics
**Why Critical**: Ensure transcription accuracy for medical records

```swift
struct QualityMetrics {
    let sessionId: String
    let confidence: Float
    let processingLatency: TimeInterval // Critical for real-time use
    let speechToSilenceRatio: Float
    let errorCount: Int
}
```

**Dashboard Value**:
- Real-time quality monitoring
- Latency alerts for poor user experience
- Confidence score trends

### 3. Speaker Analytics
**Why Critical**: Multi-speaker scenarios (doctor-patient, medical team discussions)

```swift
struct SpeakerMetrics {
    let sessionId: String
    let totalSpeakers: Int
    let primarySpeakerRatio: Float // Usually the doctor
    let speakerSwitchCount: Int
    let speakerIdentificationAccuracy: Float?
}
```

**Dashboard Value**:
- Speaker detection performance
- Conversation dynamics analysis
- Quality of multi-speaker transcription

### 4. Error Tracking
**Why Critical**: Medical transcription errors can impact patient care

```swift
struct ErrorMetrics {
    let sessionId: String
    let errorType: String
    let errorMessage: String
    let timestamp: Date
    let audioContext: String? // What was happening when error occurred
}
```

**Dashboard Value**:
- Error pattern identification
- System reliability monitoring
- Proactive issue detection

### 5. Content Analytics
**Why Critical**: Healthcare-specific performance tracking

```swift
struct ContentMetrics {
    let sessionId: String
    let medicalTermsCount: Int
    let averageWordLength: Float
    let languageDetected: String
    let silenceDuration: TimeInterval
}
```

**Dashboard Value**:
- Medical vocabulary performance
- Content complexity analysis
- Language detection accuracy

## Key Performance Indicators (KPIs)

### Primary KPIs
1. **Session Success Rate**: % of sessions completing successfully
2. **Average Processing Latency**: Time from speech to text output
3. **Speaker Detection Accuracy**: % of speakers correctly identified
4. **System Uptime**: % of time service is available
5. **Daily Active Sessions**: Number of transcription sessions per day

### Secondary KPIs
1. **Average Session Duration**: Length of typical doctor encounters
2. **Multi-Speaker Session %**: Percentage of sessions with >1 speaker
3. **Error Rate**: Errors per 1000 words transcribed
4. **Medical Term Detection**: Accuracy of healthcare vocabulary
5. **User Retention**: Doctors continuing to use the service

## Dashboard Layouts

### 1. Real-Time Operations Dashboard
- **Live Session Counter**: Current active transcriptions
- **System Health**: Green/Yellow/Red status indicators
- **Average Latency**: Real-time processing speed
- **Error Alert Panel**: Recent errors requiring attention

### 2. Quality Metrics Dashboard
- **Confidence Score Trends**: Line chart over time
- **Speaker Detection Performance**: Success rate trends
- **Session Completion Rates**: Daily/weekly success percentages
- **Error Pattern Analysis**: Most common error types

### 3. Usage Analytics Dashboard
- **Daily Session Volume**: Bar chart of transcription counts
- **Peak Usage Times**: Heatmap of busy periods
- **Average Session Duration**: Trends over time
- **User Adoption Metrics**: Active doctors using service

## Data Collection Points

### From TranscriptionViewModel
- Session start/stop events
- Speaker detection events
- Final transcript segments
- Error occurrences
- User interactions (start/stop/clear)

### From WhisperKitService
- Processing latency measurements
- Confidence scores
- Audio quality metrics
- Model performance data

### From Pipeline Events
- VAD speech detection
- Speaker changes
- Partial/final transcripts
- Component initialization status

## Privacy & Compliance

### Data to NEVER Collect
- **Actual transcription text**: Contains PHI
- **Audio recordings**: Contains patient information
- **Speaker identities**: Real names or IDs
- **Patient identifiers**: Any information linking to patients

### Safe Analytics Data
- **Aggregate metrics**: Counts, averages, percentages
- **Performance data**: Latency, confidence, error rates
- **Usage patterns**: Session times, duration trends
- **Technical metrics**: Model performance, system health

### HIPAA Compliance Requirements
- All analytics data must be de-identified
- No storage of PHI in analytics systems
- Audit trails for all data access
- Encryption in transit and at rest
- Regular security assessments

## Implementation Priority

### Phase 1 (Week 1-2): Core Metrics
1. Session tracking (start/stop/duration)
2. Basic error logging
3. Speaker count detection
4. Simple quality metrics

### Phase 2 (Week 3-4): Quality Analytics
1. Confidence score tracking
2. Latency measurements
3. Speaker switching analysis
4. Error categorization

### Phase 3 (Week 5-6): Dashboard & Alerts
1. Real-time dashboard implementation
2. Error alerting system
3. Trend analysis
4. Usage pattern detection

## Success Criteria

### Technical Success
- < 2 second processing latency for real-time use
- > 95% session completion rate
- < 1% data collection failure rate
- 99.9% analytics system uptime

### Business Success
- Clear visibility into transcription quality
- Proactive error detection and resolution
- Usage pattern insights for optimization
- Compliance with healthcare regulations

### User Success
- Doctors can rely on transcription accuracy
- Quick identification of quality issues
- Smooth integration into clinical workflow
- No impact on transcription performance

## Next Steps

1. Review and approve this specification
2. Create detailed implementation plan
3. Set up analytics infrastructure
4. Implement Phase 1 metrics collection
5. Create initial dashboard mockups
6. Begin testing with sample data

---

**Document Version**: 1.0
**Last Updated**: Current Date
**Next Review**: After Phase 1 implementation
