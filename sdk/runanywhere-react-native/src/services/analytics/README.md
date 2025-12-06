# Analytics Services

Component-specific analytics services for the RunAnywhere React Native SDK.

## Overview

The analytics services provide event tracking and batch submission for STT, TTS, and LLM components. They follow the Swift SDK pattern with event queueing, batch processing, and offline support.

## Architecture

### AnalyticsQueueManager

Centralized queue management for all analytics events.

**Features:**
- Event batching (batch size: 50)
- Time-based flushing (30 seconds)
- Retry logic with exponential backoff (max 3 retries)
- Offline support with AsyncStorage persistence
- Automatic queue restoration on app restart

**Usage:**

```typescript
import { AnalyticsQueueManager } from './services/analytics';

// Get shared instance
const queueManager = AnalyticsQueueManager.shared;

// Initialize with telemetry repository
queueManager.initialize(telemetryRepository);

// Enqueue single event
await queueManager.enqueue(event);

// Enqueue batch
await queueManager.enqueueBatch(events);

// Force flush
await queueManager.flush();

// Cleanup
await queueManager.cleanup();
```

### STTAnalyticsService

Speech-to-text analytics service.

**Tracked Metrics:**
- Transcription started/completed events
- Processing time and real-time factor
- Word count and character count
- Confidence scores
- Language detection
- Speaker detection and changes
- Errors

**Usage:**

```typescript
import { STTAnalyticsService } from './services/analytics';

const analytics = STTAnalyticsService.shared;

// Start session
const sessionId = analytics.startSession({ id: 'session-123', modelId: 'whisper-base' });

// Track transcription start
await analytics.trackTranscriptionStarted(5000); // 5 seconds of audio

// Track transcription completion
await analytics.trackTranscription(
  'Hello world',  // text
  0.95,           // confidence
  0.8,            // duration (seconds)
  5.0,            // audio length (seconds)
  'speaker-1'     // speaker ID (optional)
);

// Track final transcript
await analytics.trackFinalTranscript('Hello world', 0.95, 'speaker-1');

// Track partial transcript
await analytics.trackPartialTranscript('Hello');

// Track speaker detection
await analytics.trackSpeakerDetection('speaker-1', 0.92);

// Track speaker change
await analytics.trackSpeakerChange('speaker-1', 'speaker-2');

// Track language detection
await analytics.trackLanguageDetection('en', 0.98);

// Track error
await analytics.trackError(error, AnalyticsContext.TRANSCRIPTION);

// Get metrics
const metrics = analytics.getMetrics();
console.log('Total transcriptions:', metrics.totalTranscriptions);
console.log('Average confidence:', metrics.averageConfidence);
console.log('Average latency:', metrics.averageLatency);

// End session
analytics.endSession(sessionId);
```

### TTSAnalyticsService

Text-to-speech analytics service.

**Tracked Metrics:**
- Synthesis started/completed events
- Character count and processing time
- Characters per second
- Audio duration
- Voice used
- Errors

**Usage:**

```typescript
import { TTSAnalyticsService } from './services/analytics';

const analytics = TTSAnalyticsService.shared;

// Start session
const sessionId = analytics.startSession({ id: 'session-456', modelId: 'tts-model' });

// Track synthesis start
await analytics.trackSynthesisStarted(
  'Hello world',     // text
  'en-US-neural',    // voice
  'en'               // language
);

// Track synthesis completion
await analytics.trackSynthesisCompleted(
  11,           // character count
  2500,         // audio duration (ms)
  48000,        // audio size (bytes)
  150           // processing time (ms)
);

// Or track full synthesis in one call
await analytics.trackSynthesis(
  'Hello world',     // text
  'en-US-neural',    // voice
  'en',              // language
  2500,              // audio duration (ms)
  48000,             // audio size (bytes)
  150                // processing time (ms)
);

// Track error
await analytics.trackError(error, AnalyticsContext.TTS_SYNTHESIS);

// Get metrics
const metrics = analytics.getMetrics();
console.log('Total syntheses:', metrics.totalSyntheses);
console.log('Average CPS:', metrics.averageCharactersPerSecond);
console.log('Total characters:', metrics.totalCharactersProcessed);

// End session
analytics.endSession(sessionId);
```

### LLMAnalyticsService

Large language model analytics service.

**Tracked Metrics:**
- Generation started/completed events
- Time to first token
- Tokens per second
- Input/output token counts
- Model used
- Errors

**Usage:**

```typescript
import { LLMAnalyticsService } from './services/analytics';

const analytics = LLMAnalyticsService.shared;

// Start session
const sessionId = await analytics.startGenerationSession('llama-3-8b', 'text');

// Start generation
const generationId = await analytics.startGeneration(
  'llama-3-8b',      // model ID
  'device'           // execution target
);

// Track first token
await analytics.trackFirstToken(generationId);

// Track streaming updates
await analytics.trackStreamingUpdate(generationId, 10);
await analytics.trackStreamingUpdate(generationId, 25);

// Complete generation
await analytics.completeGeneration(
  generationId,
  50,              // input tokens
  100,             // output tokens
  'llama-3-8b',    // model ID
  'device'         // execution target
);

// Track model loading
await analytics.trackModelLoading(
  'llama-3-8b',    // model ID
  2.5,             // load time (seconds)
  true             // success
);

// Track model unloading
await analytics.trackModelUnloading('llama-3-8b');

// Track error
await analytics.trackError(error, AnalyticsContext.TEXT_GENERATION);

// Get metrics
const metrics = analytics.getMetrics();
console.log('Total generations:', metrics.totalGenerations);
console.log('Avg TTFT:', metrics.averageTimeToFirstToken);
console.log('Avg tokens/sec:', metrics.averageTokensPerSecond);
console.log('Total input tokens:', metrics.totalInputTokens);
console.log('Total output tokens:', metrics.totalOutputTokens);

// End session
await analytics.endGenerationSession(sessionId);
```

## Event Types

### STT Events

- `STT_TRANSCRIPTION_STARTED`
- `STT_TRANSCRIPTION_COMPLETED`
- `STT_PARTIAL_TRANSCRIPT`
- `STT_FINAL_TRANSCRIPT`
- `STT_SPEAKER_DETECTED`
- `STT_SPEAKER_CHANGED`
- `STT_LANGUAGE_DETECTED`
- `STT_MODEL_LOADED`
- `STT_MODEL_LOAD_FAILED`
- `STT_ERROR`

### TTS Events

- `TTS_SYNTHESIS_STARTED`
- `TTS_SYNTHESIS_COMPLETED`
- `TTS_SYNTHESIS_CHUNK`
- `TTS_MODEL_LOADED`
- `TTS_MODEL_LOAD_FAILED`
- `TTS_ERROR`

### LLM/Generation Events

- `GENERATION_SESSION_STARTED`
- `GENERATION_SESSION_ENDED`
- `GENERATION_STARTED`
- `GENERATION_COMPLETED`
- `GENERATION_FIRST_TOKEN`
- `GENERATION_STREAMING_UPDATE`
- `GENERATION_ERROR`
- `GENERATION_MODEL_LOADED`
- `GENERATION_MODEL_LOAD_FAILED`
- `GENERATION_MODEL_UNLOADED`

## Analytics Context

Error contexts for categorizing errors:

- `TRANSCRIPTION`
- `PIPELINE_PROCESSING`
- `INITIALIZATION`
- `COMPONENT_EXECUTION`
- `MODEL_LOADING`
- `AUDIO_PROCESSING`
- `TEXT_GENERATION`
- `SPEAKER_DIARIZATION`
- `TTS_SYNTHESIS`

## Metrics

### STT Metrics

```typescript
interface STTMetrics {
  totalEvents: number;
  startTime: Date;
  lastEventTime?: Date;
  totalTranscriptions: number;
  averageConfidence: number;
  averageLatency: number;
}
```

### TTS Metrics

```typescript
interface TTSMetrics {
  totalEvents: number;
  startTime: Date;
  lastEventTime?: Date;
  totalSyntheses: number;
  averageCharactersPerSecond: number;
  averageProcessingTimeMs: number;
  totalCharactersProcessed: number;
}
```

### LLM/Generation Metrics

```typescript
interface GenerationMetrics {
  totalEvents: number;
  startTime: Date;
  lastEventTime?: Date;
  totalGenerations: number;
  averageTimeToFirstToken: number;
  averageTokensPerSecond: number;
  totalInputTokens: number;
  totalOutputTokens: number;
}
```

## Best Practices

1. **Use Singleton Pattern**: Access services via `.shared` property
2. **Start Sessions**: Create sessions for related operations
3. **Track All Events**: Don't skip events for complete analytics
4. **Handle Errors Silently**: Analytics should never block main operations
5. **Flush on Cleanup**: Call `cleanup()` or `flush()` before app exit
6. **Check Queue Size**: Monitor queue size to prevent memory issues

## Implementation Notes

- Events are queued asynchronously and don't block main operations
- Failed batches are retried with exponential backoff
- Offline events are persisted to AsyncStorage
- Queue is automatically restored on app restart
- Metrics are calculated in real-time as events are tracked

## Reference

This implementation follows the Swift SDK pattern from:
- `/Users/shubhammalhotra/Desktop/RunanywhereAI/master/runanywhere-sdks/sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Analytics/AnalyticsQueueManager.swift`
- `/Users/shubhammalhotra/Desktop/RunanywhereAI/master/runanywhere-sdks/sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Analytics/`
