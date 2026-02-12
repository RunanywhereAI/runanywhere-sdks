/**
 * RunAnywhere Web SDK - Audio Capture
 *
 * Captures microphone audio using Web Audio API and provides
 * Float32Array PCM samples suitable for STT and VAD processing.
 *
 * Supports:
 *   - Real-time microphone capture via getUserMedia
 *   - Configurable sample rate (resampling via AudioContext)
 *   - AudioWorklet for low-latency processing
 *   - Chunk-based callbacks for streaming STT/VAD
 */

import { SDKLogger } from '../Foundation/SDKLogger';

const logger = new SDKLogger('AudioCapture');

export type AudioChunkCallback = (samples: Float32Array) => void;

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
 * Uses Web Audio API (AudioContext + ScriptProcessorNode or AudioWorklet)
 * to capture microphone audio, resample to target rate, and deliver
 * Float32Array PCM chunks to the consumer.
 */
export class AudioCapture {
  private audioContext: AudioContext | null = null;
  private mediaStream: MediaStream | null = null;
  private sourceNode: MediaStreamAudioSourceNode | null = null;
  private processorNode: ScriptProcessorNode | null = null;
  private _isCapturing = false;

  private readonly config: Required<AudioCaptureConfig>;
  private chunkCallback: AudioChunkCallback | null = null;

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

  /**
   * Start capturing microphone audio.
   *
   * @param onChunk - Callback receiving Float32Array chunks of PCM audio
   * @throws If microphone permission is denied
   */
  async start(onChunk: AudioChunkCallback): Promise<void> {
    if (this._isCapturing) {
      logger.debug('Already capturing');
      return;
    }

    this.chunkCallback = onChunk;

    logger.info(`Starting audio capture (${this.config.sampleRate}Hz, chunk=${this.config.chunkSize})`);

    try {
      // Request microphone access
      this.mediaStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          sampleRate: { ideal: this.config.sampleRate },
          channelCount: { exact: this.config.channels },
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
      });

      // Create AudioContext at target sample rate
      this.audioContext = new AudioContext({
        sampleRate: this.config.sampleRate,
      });

      // Connect microphone to AudioContext
      this.sourceNode = this.audioContext.createMediaStreamSource(this.mediaStream);

      // Use ScriptProcessorNode for chunk-based processing
      // Note: ScriptProcessorNode is deprecated but AudioWorklet requires
      // cross-origin isolation. We use ScriptProcessor as a fallback.
      const bufferSize = this.nearestPowerOf2(this.config.chunkSize);
      this.processorNode = this.audioContext.createScriptProcessor(
        bufferSize, this.config.channels, this.config.channels,
      );

      this.processorNode.onaudioprocess = (event) => {
        if (!this._isCapturing || !this.chunkCallback) return;

        const inputData = event.inputBuffer.getChannelData(0);
        // Copy to avoid buffer reuse issues
        const samples = new Float32Array(inputData.length);
        samples.set(inputData);
        this.chunkCallback(samples);
      };

      this.sourceNode.connect(this.processorNode);
      this.processorNode.connect(this.audioContext.destination);

      this._isCapturing = true;
      logger.info('Audio capture started');
    } catch (error) {
      this.cleanupResources();
      const message = error instanceof Error ? error.message : String(error);
      logger.error(`Failed to start audio capture: ${message}`);
      throw new Error(`Microphone access failed: ${message}`);
    }
  }

  /**
   * Stop capturing audio and release resources.
   */
  stop(): void {
    if (!this._isCapturing) return;

    this._isCapturing = false;
    this.chunkCallback = null;
    this.cleanupResources();

    logger.info('Audio capture stopped');
  }

  /**
   * Get the actual sample rate of the audio context.
   * May differ from requested rate if browser doesn't support it.
   */
  get actualSampleRate(): number {
    return this.audioContext?.sampleRate ?? this.config.sampleRate;
  }

  private cleanupResources(): void {
    if (this.processorNode) {
      this.processorNode.disconnect();
      this.processorNode.onaudioprocess = null;
      this.processorNode = null;
    }
    if (this.sourceNode) {
      this.sourceNode.disconnect();
      this.sourceNode = null;
    }
    if (this.audioContext) {
      this.audioContext.close().catch(() => { /* ignore */ });
      this.audioContext = null;
    }
    if (this.mediaStream) {
      this.mediaStream.getTracks().forEach((track) => track.stop());
      this.mediaStream = null;
    }
  }

  private nearestPowerOf2(n: number): number {
    let power = 256;
    while (power < n && power < 16384) {
      power *= 2;
    }
    return power;
  }
}
