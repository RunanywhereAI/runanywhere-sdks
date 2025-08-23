import { Injectable, OnDestroy } from '@angular/core';
import { BehaviorSubject, Observable, Subject } from 'rxjs';
import { takeUntil, map } from 'rxjs/operators';
import { DIContainer, Result } from '@runanywhere/core';
import { EnhancedVoicePipelineManager } from '@runanywhere/voice';
import type {
  VoicePipelineConfig,
  VoicePipelineState,
  ConversationEntry,
  VoiceMetrics
} from '../types';

@Injectable({
  providedIn: 'root'
})
export class VoicePipelineService implements OnDestroy {
  private pipeline: EnhancedVoicePipelineManager | null = null;
  private container: DIContainer | null = null;
  private destroy$ = new Subject<void>();

  // State observables
  private stateSubject = new BehaviorSubject<VoicePipelineState>({
    isInitialized: false,
    isListening: false,
    isProcessing: false,
    isPlaying: false,
    error: null
  });

  private conversationSubject = new BehaviorSubject<ConversationEntry[]>([]);
  private metricsSubject = new BehaviorSubject<VoiceMetrics>({
    vadLatency: 0,
    sttLatency: 0,
    llmLatency: 0,
    ttsLatency: 0,
    totalLatency: 0
  });

  // Public observables
  public readonly state$ = this.stateSubject.asObservable();
  public readonly conversation$ = this.conversationSubject.asObservable();
  public readonly metrics$ = this.metricsSubject.asObservable();

  // Public getter for current state (for immediate access)
  public get currentState(): VoicePipelineState {
    return this.stateSubject.value;
  }

  // Computed observables
  public readonly isReady$ = this.state$.pipe(
    takeUntil(this.destroy$),
    // Only emit when state changes
    map(state => state.isInitialized && !state.error)
  );

  public readonly buttonText$ = this.state$.pipe(
    takeUntil(this.destroy$),
    map(state => {
      if (!state.isInitialized) return 'Initialize Voice';
      if (state.isProcessing) return 'Processing...';
      if (state.isListening) return 'Stop Listening';
      return 'Start Listening';
    })
  );

  async initialize(config: VoicePipelineConfig = {}): Promise<void> {
    try {
      this.container = new DIContainer();
      this.pipeline = new EnhancedVoicePipelineManager(
        this.container,
        config
      );

      this.setupEventHandlers();

      const result = await this.pipeline.initialize();
      if (Result.isErr(result)) {
        throw result.error;
      }

      this.updateState({ isInitialized: true, error: null });
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      this.updateState({ error: err });
      throw err;
    }
  }

  private setupEventHandlers(): void {
    if (!this.pipeline) return;

    this.pipeline.on('started', () => {
      this.updateState({ isListening: true });
    });

    this.pipeline.on('stopped', () => {
      this.updateState({
        isListening: false,
        isProcessing: false
      });
    });

    this.pipeline.on('vadSpeechStart', () => {
      this.updateState({ isProcessing: true });
    });

    this.pipeline.on('vadSpeechEnd', () => {
      // Keep processing true until transcription completes
    });

    this.pipeline.on('transcription', (result) => {
      this.addConversationEntry({
        id: `user-${Date.now()}`,
        type: 'user',
        text: result.text,
        timestamp: new Date()
      });

      this.updateMetrics({ sttLatency: result.latency || 0 });
      this.updateTotalLatency();
    });

    this.pipeline.on('llmResponse', (result) => {
      this.addConversationEntry({
        id: `assistant-${Date.now()}`,
        type: 'assistant',
        text: result.text,
        timestamp: new Date()
      });

      this.updateMetrics({ llmLatency: result.latency || 0 });
      this.updateTotalLatency();
      this.updateState({ isProcessing: false });
    });

    this.pipeline.on('ttsPlaybackStart', () => {
      this.updateState({ isPlaying: true });
    });

    this.pipeline.on('ttsPlaybackEnd', () => {
      this.updateState({ isPlaying: false });
    });

    this.pipeline.on('error', (error) => {
      this.updateState({
        error,
        isProcessing: false,
        isPlaying: false
      });
    });
  }

  async start(): Promise<void> {
    if (!this.pipeline) {
      throw new Error('Pipeline not initialized. Call initialize() first.');
    }
    try {
      this.updateState({ error: null });
      await this.pipeline.start();
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      this.updateState({ error: err });
      throw err;
    }
  }

  async stop(): Promise<void> {
    if (!this.pipeline) return;
    try {
      await this.pipeline.stop();
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      this.updateState({ error: err });
      throw err;
    }
  }

  clearConversation(): void {
    this.conversationSubject.next([]);
  }

  clearError(): void {
    this.updateState({ error: null });
  }

  private updateState(update: Partial<VoicePipelineState>): void {
    const currentState = this.stateSubject.value;
    this.stateSubject.next({ ...currentState, ...update });
  }

  private updateMetrics(update: Partial<VoiceMetrics>): void {
    const currentMetrics = this.metricsSubject.value;
    this.metricsSubject.next({ ...currentMetrics, ...update });
  }

  private updateTotalLatency(): void {
    const metrics = this.metricsSubject.value;
    const totalLatency =
      metrics.vadLatency +
      metrics.sttLatency +
      metrics.llmLatency +
      metrics.ttsLatency;

    this.updateMetrics({ totalLatency });
  }

  private addConversationEntry(entry: ConversationEntry): void {
    const current = this.conversationSubject.value;
    this.conversationSubject.next([...current, entry]);
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();

    if (this.pipeline) {
      this.pipeline.destroy();
      this.pipeline = null;
    }

    if (this.container) {
      this.container = null;
    }
  }
}
