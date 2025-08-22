import { EventEmitter } from 'eventemitter3';
import {
  logger,
  InitializationError,
  DIContainer,
  Result,
  PipelineId
} from '@runanywhere/core';
import { WebVADService, VAD_SERVICE_TOKEN } from '../services/vad/vad-service';
import { PipelineState } from './types';
import type {
  PipelineConfig,
  PipelineEvent,
  PipelineComponent,
  PipelineMetrics,
  PipelineHealth
} from './types';

/**
 * Modern Voice Pipeline Manager
 * Orchestrates voice processing components with async/await patterns
 */
export class VoicePipelineManager extends EventEmitter {
  private readonly id: PipelineId;
  private config: PipelineConfig;
  private state: PipelineState = PipelineState.IDLE;
  private container: DIContainer;
  private vadService: WebVADService | null = null;

  // Metrics tracking
  private metrics: PipelineMetrics = {
    sessionsProcessed: 0,
    totalProcessingTime: 0,
    averageLatency: 0,
    componentMetrics: new Map()
  };

  // Performance tracking
  private processingStartTimes = new Map<PipelineComponent, number>();

  constructor(config: PipelineConfig = {}, container?: DIContainer) {
    super();
    this.id = PipelineId(`pipeline-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`);
    this.config = this.normalizeConfig(config);
    this.container = container || new DIContainer();
    this.initializeMetrics();
  }

  private normalizeConfig(config: PipelineConfig): PipelineConfig {
    return {
      vad: { enabled: true, ...config.vad },
      stt: { enabled: false, ...config.stt },
      llm: { enabled: false, ...config.llm },
      tts: { enabled: false, ...config.tts },
      performance: {
        useWebWorkers: true,
        bufferSize: 4096,
        maxConcurrentOperations: 2,
        ...config.performance
      }
    };
  }

  private initializeMetrics(): void {
    const components: PipelineComponent[] = ['vad', 'stt', 'llm', 'tts'];
    components.forEach(component => {
      this.metrics.componentMetrics.set(component, {
        invocations: 0,
        totalTime: 0,
        errors: 0
      });
    });
  }

  /**
   * Initialize the pipeline and all enabled components
   */
  async initialize(): Promise<void> {
    if (this.state !== PipelineState.IDLE) {
      logger.warn('Pipeline already initialized or in progress', 'Pipeline', {
        state: this.state,
        id: this.id
      });
      return;
    }

    this.setState(PipelineState.INITIALIZING);
    logger.info('Initializing voice pipeline', 'Pipeline', {
      id: this.id,
      config: this.config
    });

    const enabledComponents: PipelineComponent[] = [];

    try {
      // Initialize VAD if enabled
      if (this.config.vad?.enabled) {
        await this.initializeVAD();
        enabledComponents.push('vad');
      }

      // Future: Initialize STT (Phase 2)
      if (this.config.stt?.enabled) {
        logger.debug('STT initialization skipped (Phase 2)', 'Pipeline');
        // await this.initializeSTT();
        // enabledComponents.push('stt');
      }

      // Future: Initialize LLM (Phase 2)
      if (this.config.llm?.enabled) {
        logger.debug('LLM initialization skipped (Phase 2)', 'Pipeline');
        // await this.initializeLLM();
        // enabledComponents.push('llm');
      }

      // Future: Initialize TTS (Phase 2)
      if (this.config.tts?.enabled) {
        logger.debug('TTS initialization skipped (Phase 2)', 'Pipeline');
        // await this.initializeTTS();
        // enabledComponents.push('tts');
      }

      this.setState(PipelineState.READY);
      this.emitEvent({
        type: 'initialized',
        components: enabledComponents
      });

      logger.info('Voice pipeline initialized successfully', 'Pipeline', {
        id: this.id,
        components: enabledComponents
      });

    } catch (error) {
      this.setState(PipelineState.ERROR);
      const err = error instanceof Error ? error : new Error(String(error));
      this.emitEvent({ type: 'error', error: err });
      logger.error('Failed to initialize pipeline', 'Pipeline', {
        id: this.id,
        error: err.message
      });
      throw err;
    }
  }

  private async initializeVAD(): Promise<void> {
    logger.debug('Initializing VAD service', 'Pipeline');

    // Register VAD service in container
    this.container.register(VAD_SERVICE_TOKEN, {
      factory: async () => {
        const vad = new WebVADService();
        await vad.initialize(this.config.vad?.config);
        return vad;
      },
      lifecycle: 'singleton',
      healthCheck: async () => {
        const service = await this.container.resolve<WebVADService>(VAD_SERVICE_TOKEN);
        return service.isHealthy();
      }
    });

    // Resolve and store VAD service
    const vadResult = await this.container.tryResolve<WebVADService>(VAD_SERVICE_TOKEN);
    if (Result.isErr(vadResult)) {
      throw vadResult.error;
    }

    this.vadService = vadResult.value;

    // Set up VAD event handlers
    if (this.vadService) {
      this.vadService.onSpeechStart(() => {
        this.trackComponentStart('vad');
        this.emitEvent({
          type: 'vad:speech_start',
          timestamp: Date.now()
        });
      });

      this.vadService.onSpeechEnd((audio) => {
        const duration = audio.length / 16000; // Assuming 16kHz sample rate
        this.trackComponentEnd('vad');
        this.emitEvent({
          type: 'vad:speech_end',
          audio,
          duration
        });

        // Process audio through pipeline
        this.processAudio(audio);
      });

      this.vadService.onAudioLevel((level) => {
        this.emitEvent({
          type: 'vad:audio_level',
          level
        });
      });
    }
  }

  /**
   * Start the pipeline
   */
  async start(): Promise<void> {
    if (this.state !== PipelineState.READY && this.state !== PipelineState.PAUSED) {
      throw new InitializationError(
        `Cannot start pipeline in state: ${this.state}. Pipeline must be READY or PAUSED.`
      );
    }

    logger.info('Starting voice pipeline', 'Pipeline', { id: this.id });

    try {
      if (this.vadService) {
        await this.vadService.start();
      }

      this.setState(PipelineState.RUNNING);
      this.emitEvent({
        type: 'started',
        timestamp: Date.now()
      });

      logger.info('Voice pipeline started', 'Pipeline', { id: this.id });

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      this.emitEvent({ type: 'error', error: err });
      logger.error('Failed to start pipeline', 'Pipeline', {
        id: this.id,
        error: err.message
      });
      throw err;
    }
  }

  /**
   * Stop the pipeline
   */
  stop(): void {
    if (this.state !== PipelineState.RUNNING && this.state !== PipelineState.PAUSED) {
      logger.warn('Pipeline not running', 'Pipeline', {
        id: this.id,
        state: this.state
      });
      return;
    }

    logger.info('Stopping voice pipeline', 'Pipeline', { id: this.id });

    if (this.vadService) {
      this.vadService.stop();
    }

    this.setState(PipelineState.READY);
    this.emitEvent({
      type: 'stopped',
      timestamp: Date.now()
    });

    logger.info('Voice pipeline stopped', 'Pipeline', { id: this.id });
  }

  /**
   * Pause the pipeline
   */
  pause(): void {
    if (this.state !== PipelineState.RUNNING) {
      logger.warn('Cannot pause - pipeline not running', 'Pipeline', {
        id: this.id,
        state: this.state
      });
      return;
    }

    logger.debug('Pausing voice pipeline', 'Pipeline', { id: this.id });

    if (this.vadService) {
      this.vadService.pause();
    }

    this.setState(PipelineState.PAUSED);
    this.emitEvent({
      type: 'paused',
      timestamp: Date.now()
    });
  }

  /**
   * Resume the pipeline
   */
  resume(): void {
    if (this.state !== PipelineState.PAUSED) {
      logger.warn('Cannot resume - pipeline not paused', 'Pipeline', {
        id: this.id,
        state: this.state
      });
      return;
    }

    logger.debug('Resuming voice pipeline', 'Pipeline', { id: this.id });

    if (this.vadService) {
      this.vadService.resume();
    }

    this.setState(PipelineState.RUNNING);
    this.emitEvent({
      type: 'resumed',
      timestamp: Date.now()
    });
  }

  /**
   * Process audio through the pipeline stages
   */
  private async processAudio(audio: Float32Array): Promise<void> {
    const sessionStart = performance.now();

    this.emitEvent({
      type: 'processing:start',
      stage: 'vad'
    });

    try {
      // Phase 1: Just log the audio info
      logger.info('Processing audio segment', 'Pipeline', {
        id: this.id,
        duration: `${(audio.length / 16000).toFixed(2)}s`,
        samples: audio.length
      });

      // Future phases will process through STT -> LLM -> TTS

      this.metrics.sessionsProcessed++;
      const processingTime = performance.now() - sessionStart;
      this.metrics.totalProcessingTime += processingTime;
      this.metrics.averageLatency =
        this.metrics.totalProcessingTime / this.metrics.sessionsProcessed;

      this.emitEvent({
        type: 'processing:complete',
        stage: 'vad',
        duration: processingTime
      });

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      this.incrementComponentErrors('vad');
      this.emitEvent({
        type: 'error',
        error: err,
        component: 'vad'
      });
      logger.error('Audio processing failed', 'Pipeline', {
        id: this.id,
        error: err.message
      });
    }
  }

  /**
   * Get pipeline health status
   */
  async getHealth(): Promise<PipelineHealth> {
    const componentHealth = new Map<PipelineComponent, { healthy: boolean; message?: string }>();

    // Check VAD health
    if (this.config.vad?.enabled && this.vadService) {
      componentHealth.set('vad', {
        healthy: this.vadService.isHealthy()
      });
    }

    // Future: Check other component health

    const overall = Array.from(componentHealth.values())
      .every(health => health.healthy);

    return {
      overall,
      components: componentHealth,
      lastCheck: new Date()
    };
  }

  /**
   * Get pipeline metrics
   */
  getMetrics(): PipelineMetrics {
    return {
      ...this.metrics,
      componentMetrics: new Map(this.metrics.componentMetrics)
    };
  }

  /**
   * Get current pipeline state
   */
  getState(): PipelineState {
    return this.state;
  }

  /**
   * Get pipeline ID
   */
  getId(): PipelineId {
    return this.id;
  }

  /**
   * Update pipeline configuration
   */
  async updateConfig(config: Partial<PipelineConfig>): Promise<void> {
    if (this.state === PipelineState.RUNNING) {
      throw new Error('Cannot update config while pipeline is running');
    }

    this.config = this.normalizeConfig({ ...this.config, ...config });
    logger.info('Pipeline configuration updated', 'Pipeline', {
      id: this.id,
      config: this.config
    });

    // Reinitialize if needed
    if (this.state === PipelineState.READY) {
      await this.initialize();
    }
  }

  /**
   * Destroy the pipeline and clean up resources
   */
  destroy(): void {
    logger.info('Destroying voice pipeline', 'Pipeline', { id: this.id });

    this.stop();

    if (this.vadService) {
      this.vadService.destroy();
      this.vadService = null;
    }

    this.container.clear();
    this.setState(PipelineState.DESTROYED);
    this.emitEvent({ type: 'destroyed' });
    this.removeAllListeners();

    logger.info('Voice pipeline destroyed', 'Pipeline', { id: this.id });
  }

  // Helper methods

  private setState(state: PipelineState): void {
    this.state = state;
    this.emit('state:change', state);
  }

  private emitEvent(event: PipelineEvent): void {
    this.emit('event', event);

    // Also emit specific event types for convenience
    this.emit(event.type, event);
  }

  private trackComponentStart(component: PipelineComponent): void {
    this.processingStartTimes.set(component, performance.now());
    const metrics = this.metrics.componentMetrics.get(component);
    if (metrics) {
      metrics.invocations++;
    }
  }

  private trackComponentEnd(component: PipelineComponent): void {
    const startTime = this.processingStartTimes.get(component);
    if (startTime) {
      const duration = performance.now() - startTime;
      const metrics = this.metrics.componentMetrics.get(component);
      if (metrics) {
        metrics.totalTime += duration;
      }
      this.processingStartTimes.delete(component);
    }
  }

  private incrementComponentErrors(component: PipelineComponent): void {
    const metrics = this.metrics.componentMetrics.get(component);
    if (metrics) {
      metrics.errors++;
    }
  }
}

/**
 * Pipeline manager token for DI container
 */
export const PIPELINE_MANAGER_TOKEN = Symbol.for('PipelineManager');
