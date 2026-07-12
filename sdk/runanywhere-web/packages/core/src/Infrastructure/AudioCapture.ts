/**
 * RunAnywhere Web SDK - Audio Capture
 *
 * Captures microphone audio using Web Audio API and provides
 * Float32Array PCM samples suitable for STT and VAD processing.
 *
 * Supports:
 *   - Real-time microphone capture via getUserMedia
 *   - Configurable sample rate (resampling via AudioContext)
 *   - Chunk-based callbacks for streaming STT/VAD
 *   - Buffer accumulation (getAudioBuffer, drainBuffer, clearBuffer)
 *   - Audio level monitoring via AnalyserNode (currentLevel getter)
 */

import { SDKLogger } from '../Foundation/SDKLogger.js';

const logger = new SDKLogger('AudioCapture');

export type AudioChunkCallback = (samples: Float32Array) => void;
export type AudioLevelCallback = (level: number) => void;

export interface AudioCaptureConfig {
  /** Target sample rate (default: 16000 for STT) */
  sampleRate?: number;
  /** Chunk size in samples (default: 1600 = 100ms at 16kHz) */
  chunkSize?: number;
  /** Number of audio channels (default: 1, mono) */
  channels?: number;
}

/**
 * AudioCapture - Captures microphone audio for STT/VAD processing.
 *
 * Uses Web Audio API (AudioContext + AudioWorkletNode) to capture microphone
 * audio, resample to the target rate, and deliver exact-size Float32Array PCM
 * chunks to the consumer without running audio processing on the main thread.
 *
 * Includes buffer accumulation for batch STT and an AnalyserNode for
 * real-time audio level metering (0-1 range).
 */
export class AudioCapture {
  private activeResources: AudioCaptureResources | null = null;
  private pendingStart: PendingAudioCaptureStart | null = null;
  private _animFrameId: number | null = null;
  private _isCapturing = false;
  private _currentLevel = 0;
  private _pcmChunks: Float32Array[] = [];
  /**
   * Invalidates an in-flight getUserMedia request when capture is stopped or
   * restarted before the permission prompt settles.
   */
  private lifecycleGeneration = 0;

  private readonly config: Required<AudioCaptureConfig>;
  private chunkCallback: AudioChunkCallback | null = null;
  private levelCallback: AudioLevelCallback | null = null;

  constructor(config: AudioCaptureConfig = {}) {
    this.config = {
      sampleRate: config.sampleRate ?? 16000,
      chunkSize: config.chunkSize ?? 1600,
      channels: config.channels ?? 1,
    };
  }

  get isCapturing(): boolean {
    return this._isCapturing;
  }

  /** Current normalized audio level (0..1), updated per animation frame. */
  get currentLevel(): number {
    return this._currentLevel;
  }

  /**
   * Get the actual sample rate of the audio context.
   * May differ from requested rate if browser doesn't support it.
   */
  get actualSampleRate(): number {
    return this.activeResources?.context.sampleRate ?? this.config.sampleRate;
  }

  /** Duration of collected audio in seconds based on configured sample rate. */
  get bufferDurationSeconds(): number {
    const samples = this._pcmChunks.reduce((acc, c) => acc + c.length, 0);
    return samples / this.config.sampleRate;
  }

  /**
   * Start capturing microphone audio.
   *
   * @param onChunk - Optional callback receiving Float32Array chunks of PCM audio (streaming)
   * @param onLevel - Optional callback invoked per animation frame with audio level 0..1
   * @throws If microphone permission is denied
   */
  async start(onChunk?: AudioChunkCallback, onLevel?: AudioLevelCallback): Promise<void> {
    if (this._isCapturing) {
      logger.debug('Already capturing');
      return;
    }

    const generation = ++this.lifecycleGeneration;
    this.cancelPendingStart();
    this.chunkCallback = onChunk ?? null;
    this.levelCallback = onLevel ?? null;
    this._pcmChunks = [];
    this._currentLevel = 0;

    logger.info(`Starting audio capture (${this.config.sampleRate}Hz, chunk=${this.config.chunkSize})`);

    let acquiredStream: MediaStream | null = null;
    let pendingStart: PendingAudioCaptureStart | null = null;
    try {
      // Request microphone access
      acquiredStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          sampleRate: { ideal: this.config.sampleRate },
          channelCount: { exact: this.config.channels },
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
      });

      // stop() or a newer start() won while the permission prompt was open.
      // Release the just-granted stream without installing it on this capture.
      if (generation !== this.lifecycleGeneration) {
        acquiredStream.getTracks().forEach((track) => track.stop());
        return;
      }
      // Create AudioContext at target sample rate
      const context = new AudioContext({
        sampleRate: this.config.sampleRate,
      });
      pendingStart = {
        generation,
        context,
        stream: acquiredStream,
        disposed: false,
      };
      this.pendingStart = pendingStart;
      acquiredStream = null;

      await context.audioWorklet.addModule(
        new URL('./AudioCaptureProcessor.js', import.meta.url).href,
      );

      if (!this.isCurrentPendingStart(pendingStart)) {
        this.disposePendingStart(pendingStart);
        return;
      }

      if (context.state === 'suspended') {
        await context.resume();
      }

      if (!this.isCurrentPendingStart(pendingStart)) {
        this.disposePendingStart(pendingStart);
        return;
      }

      // Connect microphone to AudioContext
      const sourceNode = context.createMediaStreamSource(pendingStart.stream);

      // --- AnalyserNode for level metering ---
      const analyser = context.createAnalyser();
      analyser.fftSize = 256;

      // AudioWorklet owns render-quantum aggregation off the main thread and
      // posts one transferable Float32Array per configured chunk.
      const workletNode = new AudioWorkletNode(context, AUDIO_CAPTURE_PROCESSOR_NAME, {
        numberOfInputs: 1,
        numberOfOutputs: 1,
        outputChannelCount: [1],
        channelCount: this.config.channels,
        channelCountMode: 'explicit',
        channelInterpretation: 'discrete',
        processorOptions: { chunkSize: this.config.chunkSize },
      });
      workletNode.port.onmessage = (event: MessageEvent<unknown>) => {
        this.handleWorkletMessage(event.data);
      };
      workletNode.onprocessorerror = () => {
        logger.error('Audio capture worklet stopped unexpectedly');
        this.stop();
      };

      sourceNode.connect(analyser);
      sourceNode.connect(workletNode);
      // Keep the worklet in the active graph. Its output remains silent, so
      // microphone audio is never played back through the speakers.
      workletNode.connect(context.destination);

      this.pendingStart = null;
      this.activeResources = {
        context,
        stream: pendingStart.stream,
        sourceNode,
        analyser,
        workletNode,
      };

      this._isCapturing = true;

      // Start level monitoring loop
      this.startLevelMonitoring();

      logger.info('Audio capture started');
    } catch (error) {
      acquiredStream?.getTracks().forEach((track) => track.stop());
      if (pendingStart) {
        if (this.pendingStart === pendingStart) this.pendingStart = null;
        this.disposePendingStart(pendingStart);
      }
      // Cancellation or a newer start is not a microphone failure.
      if (generation !== this.lifecycleGeneration) {
        return;
      }
      this.chunkCallback = null;
      this.levelCallback = null;
      const message = error instanceof Error ? error.message : String(error);
      logger.error(`Failed to start audio capture: ${message}`);
      throw new Error(`Audio capture failed: ${message}`);
    }
  }

  /**
   * Stop capturing audio and release resources.
   */
  stop(): void {
    // Invalidate a pending getUserMedia request even before _isCapturing flips.
    this.lifecycleGeneration += 1;
    this._isCapturing = false;
    this._currentLevel = 0;
    this.chunkCallback = null;
    this.levelCallback = null;
    this.cancelPendingStart();
    this.cleanupResources();

    logger.info('Audio capture stopped');
  }

  /**
   * Get all collected PCM audio as a single Float32Array.
   * Does NOT clear the buffer — call `clearBuffer()` separately.
   */
  getAudioBuffer(): Float32Array {
    if (this._pcmChunks.length === 0) return new Float32Array(0);
    const totalLength = this._pcmChunks.reduce((acc, c) => acc + c.length, 0);
    const merged = new Float32Array(totalLength);
    let offset = 0;
    for (const chunk of this._pcmChunks) {
      merged.set(chunk, offset);
      offset += chunk.length;
    }
    return merged;
  }

  /**
   * Drain: return the current buffer and clear it for the next segment.
   * Useful for live mode where we transcribe segments incrementally.
   */
  drainBuffer(): Float32Array {
    const buffer = this.getAudioBuffer();
    this._pcmChunks = [];
    return buffer;
  }

  /** Clear collected PCM data without stopping capture. */
  clearBuffer(): void {
    this._pcmChunks = [];
  }

  /** Start the requestAnimationFrame loop that reads the AnalyserNode. */
  private startLevelMonitoring(): void {
    const resources = this.activeResources;
    if (!resources) return;

    const dataArray = new Uint8Array(resources.analyser.frequencyBinCount);
    const tick = () => {
      if (!this._isCapturing || this.activeResources !== resources) return;
      resources.analyser.getByteFrequencyData(dataArray);
      let sum = 0;
      for (let i = 0; i < dataArray.length; i++) sum += dataArray[i];
      const avg = sum / dataArray.length / 255;
      this._currentLevel = avg;
      this.levelCallback?.(avg);
      this._animFrameId = requestAnimationFrame(tick);
    };
    this._animFrameId = requestAnimationFrame(tick);
  }

  private cleanupResources(): void {
    if (this._animFrameId !== null) {
      cancelAnimationFrame(this._animFrameId);
      this._animFrameId = null;
    }
    const resources = this.activeResources;
    this.activeResources = null;
    if (!resources) return;

    resources.workletNode.port.onmessage = null;
    resources.workletNode.port.close();
    resources.workletNode.onprocessorerror = null;
    resources.workletNode.disconnect();
    resources.analyser.disconnect();
    resources.sourceNode.disconnect();
    resources.context.close().catch(() => { /* ignore */ });
    resources.stream.getTracks().forEach((track) => track.stop());
  }

  private handleWorkletMessage(message: unknown): void {
    if (!this._isCapturing) return;
    if (!(message instanceof Float32Array)) {
      logger.warning('Ignoring invalid audio worklet message');
      return;
    }
    this._pcmChunks.push(message);
    this.chunkCallback?.(message);
  }

  private isCurrentPendingStart(pendingStart: PendingAudioCaptureStart): boolean {
    return pendingStart.generation === this.lifecycleGeneration
      && this.pendingStart === pendingStart;
  }

  private cancelPendingStart(): void {
    const pendingStart = this.pendingStart;
    this.pendingStart = null;
    if (pendingStart) this.disposePendingStart(pendingStart);
  }

  private disposePendingStart(pendingStart: PendingAudioCaptureStart): void {
    if (pendingStart.disposed) return;
    pendingStart.disposed = true;
    pendingStart.context.close().catch(() => { /* ignore */ });
    pendingStart.stream.getTracks().forEach((track) => track.stop());
  }
}

const AUDIO_CAPTURE_PROCESSOR_NAME = 'runanywhere-audio-capture';

interface PendingAudioCaptureStart {
  generation: number;
  context: AudioContext;
  stream: MediaStream;
  disposed: boolean;
}

interface AudioCaptureResources {
  context: AudioContext;
  stream: MediaStream;
  sourceNode: MediaStreamAudioSourceNode;
  analyser: AnalyserNode;
  workletNode: AudioWorkletNode;
}
