# Analytics Services - Usage Examples

This document provides practical examples of integrating analytics services into your components.

## STT Component Integration

### Basic Transcription Tracking

```typescript
import { STTAnalyticsService, AnalyticsContext } from '@runanywhere/react-native';

class STTComponent {
  private analytics = STTAnalyticsService.shared;
  private sessionId: string | null = null;

  async initialize(modelId: string) {
    try {
      // Start analytics session
      this.sessionId = this.analytics.startSession({
        id: `stt-${Date.now()}`,
        modelId,
      });

      // ... initialize STT component
    } catch (error) {
      await this.analytics.trackError(error, AnalyticsContext.INITIALIZATION);
      throw error;
    }
  }

  async transcribe(audioData: ArrayBuffer): Promise<string> {
    const startTime = Date.now();
    const audioLength = audioData.byteLength / (16000 * 2); // Assuming 16kHz, 16-bit

    try {
      // Track start
      await this.analytics.trackTranscriptionStarted(audioLength * 1000);

      // Perform transcription
      const result = await this.performTranscription(audioData);

      // Track completion
      const duration = (Date.now() - startTime) / 1000;
      await this.analytics.trackTranscription(
        result.text,
        result.confidence,
        duration,
        audioLength,
        result.speaker
      );

      return result.text;
    } catch (error) {
      await this.analytics.trackError(error, AnalyticsContext.TRANSCRIPTION);
      throw error;
    }
  }

  async cleanup() {
    if (this.sessionId) {
      this.analytics.endSession(this.sessionId);
    }
  }
}
```

### Streaming Transcription with Real-time Updates

```typescript
import { STTAnalyticsService } from '@runanywhere/react-native';

class StreamingSTTComponent {
  private analytics = STTAnalyticsService.shared;

  async transcribeStream(audioStream: AsyncIterable<ArrayBuffer>) {
    const sessionId = this.analytics.startSession({
      id: `stream-${Date.now()}`,
      modelId: 'whisper-streaming',
    });

    try {
      for await (const chunk of audioStream) {
        const result = await this.processChunk(chunk);

        if (result.partial) {
          // Track partial transcripts
          await this.analytics.trackPartialTranscript(result.text);
        }

        if (result.final) {
          // Track final transcript
          await this.analytics.trackFinalTranscript(
            result.text,
            result.confidence,
            result.speaker
          );
        }

        // Track speaker changes
        if (result.speakerChanged) {
          await this.analytics.trackSpeakerChange(
            result.previousSpeaker,
            result.currentSpeaker
          );
        }

        // Track language detection
        if (result.languageDetected) {
          await this.analytics.trackLanguageDetection(
            result.language,
            result.languageConfidence
          );
        }
      }
    } finally {
      this.analytics.endSession(sessionId);
    }
  }
}
```

## TTS Component Integration

### Basic Synthesis Tracking

```typescript
import { TTSAnalyticsService, AnalyticsContext } from '@runanywhere/react-native';

class TTSComponent {
  private analytics = TTSAnalyticsService.shared;
  private sessionId: string | null = null;

  async initialize(modelId: string) {
    this.sessionId = this.analytics.startSession({
      id: `tts-${Date.now()}`,
      modelId,
    });
  }

  async synthesize(text: string, voice: string, language: string): Promise<ArrayBuffer> {
    const startTime = Date.now();

    try {
      // Track synthesis start
      await this.analytics.trackSynthesisStarted(text, voice, language);

      // Perform synthesis
      const audioData = await this.performSynthesis(text, voice, language);

      // Calculate metrics
      const processingTime = Date.now() - startTime;
      const audioDuration = this.getAudioDuration(audioData);

      // Track completion
      await this.analytics.trackSynthesisCompleted(
        text.length,
        audioDuration,
        audioData.byteLength,
        processingTime
      );

      return audioData;
    } catch (error) {
      await this.analytics.trackError(error, AnalyticsContext.TTS_SYNTHESIS);
      throw error;
    }
  }

  async cleanup() {
    if (this.sessionId) {
      this.analytics.endSession(this.sessionId);
    }
  }

  private getAudioDuration(audioData: ArrayBuffer): number {
    // Calculate duration based on sample rate and format
    const sampleRate = 22050; // Example
    const bytesPerSample = 2; // 16-bit
    const duration = (audioData.byteLength / bytesPerSample / sampleRate) * 1000;
    return duration;
  }
}
```

### Batch Synthesis with Progress Tracking

```typescript
import { TTSAnalyticsService } from '@runanywhere/react-native';

class BatchTTSComponent {
  private analytics = TTSAnalyticsService.shared;

  async synthesizeBatch(texts: string[], voice: string, language: string) {
    const sessionId = this.analytics.startSession({
      id: `batch-${Date.now()}`,
      modelId: 'tts-batch',
    });

    const results = [];

    try {
      for (const text of texts) {
        const result = await this.synthesizeWithTracking(text, voice, language);
        results.push(result);
      }

      // Get metrics for the batch
      const metrics = this.analytics.getMetrics();
      console.log(`Batch completed: ${metrics.totalSyntheses} syntheses`);
      console.log(`Average CPS: ${metrics.averageCharactersPerSecond}`);

      return results;
    } finally {
      this.analytics.endSession(sessionId);
    }
  }

  private async synthesizeWithTracking(text: string, voice: string, language: string) {
    const startTime = Date.now();

    await this.analytics.trackSynthesisStarted(text, voice, language);
    const audioData = await this.performSynthesis(text, voice, language);

    const processingTime = Date.now() - startTime;
    const audioDuration = this.getAudioDuration(audioData);

    await this.analytics.trackSynthesisCompleted(
      text.length,
      audioDuration,
      audioData.byteLength,
      processingTime
    );

    return audioData;
  }
}
```

## LLM Component Integration

### Basic Generation Tracking

```typescript
import { LLMAnalyticsService, AnalyticsContext } from '@runanywhere/react-native';

class LLMComponent {
  private analytics = LLMAnalyticsService.shared;
  private sessionId: string | null = null;

  async initialize(modelId: string) {
    this.sessionId = await this.analytics.startGenerationSession(modelId, 'text');
  }

  async generate(prompt: string, maxTokens: number = 100): Promise<string> {
    const generationId = await this.analytics.startGeneration(
      this.modelId,
      'device'
    );

    try {
      // Perform generation
      const result = await this.performGeneration(prompt, maxTokens);

      // Complete tracking
      await this.analytics.completeGeneration(
        generationId,
        result.inputTokens,
        result.outputTokens,
        this.modelId,
        'device'
      );

      return result.text;
    } catch (error) {
      await this.analytics.trackError(error, AnalyticsContext.TEXT_GENERATION);
      throw error;
    }
  }

  async cleanup() {
    if (this.sessionId) {
      await this.analytics.endGenerationSession(this.sessionId);
    }
  }
}
```

### Streaming Generation with TTFT Tracking

```typescript
import { LLMAnalyticsService } from '@runanywhere/react-native';

class StreamingLLMComponent {
  private analytics = LLMAnalyticsService.shared;

  async* generateStream(prompt: string): AsyncGenerator<string> {
    const generationId = await this.analytics.startGeneration(
      this.modelId,
      'device'
    );

    let firstTokenTracked = false;
    let tokenCount = 0;
    const inputTokens = this.countTokens(prompt);

    try {
      for await (const token of this.streamGeneration(prompt)) {
        tokenCount++;

        // Track first token
        if (!firstTokenTracked) {
          await this.analytics.trackFirstToken(generationId);
          firstTokenTracked = true;
        }

        // Track streaming updates every 10 tokens
        if (tokenCount % 10 === 0) {
          await this.analytics.trackStreamingUpdate(generationId, tokenCount);
        }

        yield token;
      }

      // Complete generation
      await this.analytics.completeGeneration(
        generationId,
        inputTokens,
        tokenCount,
        this.modelId,
        'device'
      );
    } catch (error) {
      await this.analytics.trackError(error, AnalyticsContext.TEXT_GENERATION);
      throw error;
    }
  }

  private countTokens(text: string): number {
    // Simple approximation - use actual tokenizer in production
    return Math.ceil(text.split(/\s+/).length * 1.3);
  }
}
```

### Model Lifecycle Tracking

```typescript
import { LLMAnalyticsService, AnalyticsContext } from '@runanywhere/react-native';

class ModelManager {
  private analytics = LLMAnalyticsService.shared;
  private loadedModels = new Map<string, any>();

  async loadModel(modelId: string): Promise<void> {
    const startTime = Date.now();

    try {
      // Load model
      const model = await this.performModelLoad(modelId);
      this.loadedModels.set(modelId, model);

      // Track successful load
      const loadTime = (Date.now() - startTime) / 1000;
      await this.analytics.trackModelLoading(modelId, loadTime, true);
    } catch (error) {
      // Track failed load
      const loadTime = (Date.now() - startTime) / 1000;
      await this.analytics.trackModelLoading(modelId, loadTime, false, error.code);
      await this.analytics.trackError(error, AnalyticsContext.MODEL_LOADING);
      throw error;
    }
  }

  async unloadModel(modelId: string): Promise<void> {
    const model = this.loadedModels.get(modelId);
    if (model) {
      await this.performModelUnload(model);
      this.loadedModels.delete(modelId);
      await this.analytics.trackModelUnloading(modelId);
    }
  }
}
```

## Analytics Queue Management

### Manual Queue Control

```typescript
import { AnalyticsQueueManager } from '@runanywhere/react-native';

class AnalyticsController {
  private queueManager = AnalyticsQueueManager.shared;

  async initialize(telemetryRepository: any) {
    // Initialize with telemetry repository
    this.queueManager.initialize(telemetryRepository);
  }

  async forceFlush() {
    // Force flush all pending events
    await this.queueManager.flush();
  }

  getQueueStatus() {
    return {
      size: this.queueManager.getQueueSize(),
      isHealthy: this.queueManager.getQueueSize() < 100,
    };
  }

  async clearQueue() {
    await this.queueManager.clearPersistedQueue();
  }

  async cleanup() {
    // Cleanup before app exit
    await this.queueManager.cleanup();
  }
}
```

### App Lifecycle Integration

```typescript
import { AppState, AppStateStatus } from 'react-native';
import { AnalyticsQueueManager } from '@runanywhere/react-native';

class AppLifecycleHandler {
  private queueManager = AnalyticsQueueManager.shared;

  constructor() {
    AppState.addEventListener('change', this.handleAppStateChange);
  }

  private handleAppStateChange = async (nextAppState: AppStateStatus) => {
    if (nextAppState === 'background') {
      // Flush analytics before going to background
      await this.queueManager.flush();
    }

    if (nextAppState === 'inactive') {
      // App is closing - cleanup
      await this.queueManager.cleanup();
    }
  };
}
```

## Metrics Dashboard

### Real-time Metrics Display

```typescript
import { STTAnalyticsService, TTSAnalyticsService, LLMAnalyticsService } from '@runanywhere/react-native';

class MetricsDashboard {
  getSTTMetrics() {
    const metrics = STTAnalyticsService.shared.getMetrics();
    return {
      transcriptions: metrics.totalTranscriptions,
      avgConfidence: (metrics.averageConfidence * 100).toFixed(1) + '%',
      avgLatency: metrics.averageLatency.toFixed(2) + 's',
      events: metrics.totalEvents,
    };
  }

  getTTSMetrics() {
    const metrics = TTSAnalyticsService.shared.getMetrics();
    return {
      syntheses: metrics.totalSyntheses,
      avgCPS: metrics.averageCharactersPerSecond.toFixed(0),
      avgProcessingTime: metrics.averageProcessingTimeMs.toFixed(0) + 'ms',
      totalChars: metrics.totalCharactersProcessed,
    };
  }

  getLLMMetrics() {
    const metrics = LLMAnalyticsService.shared.getMetrics();
    return {
      generations: metrics.totalGenerations,
      avgTTFT: metrics.averageTimeToFirstToken.toFixed(0) + 'ms',
      avgTPS: metrics.averageTokensPerSecond.toFixed(1),
      inputTokens: metrics.totalInputTokens,
      outputTokens: metrics.totalOutputTokens,
    };
  }

  getAllMetrics() {
    return {
      stt: this.getSTTMetrics(),
      tts: this.getTTSMetrics(),
      llm: this.getLLMMetrics(),
    };
  }
}
```

## Error Handling Best Practices

```typescript
import { AnalyticsContext } from '@runanywhere/react-native';

class ComponentWithAnalytics {
  async performOperation() {
    try {
      // Main operation
      const result = await this.doWork();
      return result;
    } catch (error) {
      // Track error with appropriate context
      const context = this.determineErrorContext(error);
      await this.analytics.trackError(error, context);

      // Don't let analytics errors break the app
      throw error;
    }
  }

  private determineErrorContext(error: Error): AnalyticsContext {
    if (error.message.includes('model')) {
      return AnalyticsContext.MODEL_LOADING;
    }
    if (error.message.includes('network')) {
      return AnalyticsContext.INITIALIZATION;
    }
    // Default context
    return AnalyticsContext.COMPONENT_EXECUTION;
  }
}
```
