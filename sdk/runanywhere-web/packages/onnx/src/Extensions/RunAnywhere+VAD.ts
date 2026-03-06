/**
 * RunAnywhere Web SDK - Voice Activity Detection Extension
 *
 * Adds VAD capabilities via sherpa-onnx WASM using Silero VAD model.
 * Detects speech segments in audio streams with high accuracy.
 *
 * Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VAD/
 *
 * Usage:
 *   import { VAD } from '@runanywhere/web';
 *
 *   await VAD.loadModel({
 *     modelPath: '/models/vad/silero_vad.onnx',
 *     threshold: 0.5,
 *   });
 *
 *   const hasVoice = VAD.processSamples(audioFloat32Array);
 *   if (hasVoice) console.log('Speech detected!');
 */

import { RunAnywhere, SDKError, SDKErrorCode, SDKLogger, EventBus, SDKEventType, AnalyticsEmitter } from '@runanywhere/web';
import { SherpaONNXBridge } from '../Foundation/SherpaONNXBridge';
import { SpeechActivity } from './VADTypes';
import type { SpeechActivityCallback, VADModelConfig, SpeechSegment } from './VADTypes';

import { loadVADHelpers } from '../Foundation/SherpaHelperLoader';

export type { VADModelConfig } from './VADTypes';

const logger = new SDKLogger('VAD');

// ---------------------------------------------------------------------------
// Internal Helpers
// ---------------------------------------------------------------------------

function requireSherpa(): SherpaONNXBridge {
  if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
  return SherpaONNXBridge.shared;
}

// ---------------------------------------------------------------------------
// VAD Extension
// ---------------------------------------------------------------------------

class VADImpl {
  readonly extensionName = 'VAD';
  private _vadHandle = 0;
  private _sampleRate = 16000;
  private _jsActivityCallback: SpeechActivityCallback | null = null;
  private _lastSpeechState = false;
  private _speechStartMs = 0;

  /**
   * Load the Silero VAD model via sherpa-onnx.
   * The model file must already be in the sherpa-onnx virtual FS.
   */
  async loadModel(config: VADModelConfig): Promise<void> {
    const sherpa = requireSherpa();
    await sherpa.ensureLoaded();
    const m = sherpa.module;

    // Clean up previous
    this.cleanup();

    this._sampleRate = config.sampleRate ?? 16000;

    logger.info('Loading Silero VAD model');
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, {
      modelId: 'silero-vad', component: 'vad',
    });

    const startMs = performance.now();
    const bufferSizeInSeconds = 30; // 30 second circular buffer

    // Build the struct-based config matching sherpa-onnx C API layout.
    // Uses initSherpaOnnxVadModelConfig from sherpa-onnx-vad.js which
    // allocates a C struct in WASM memory (not JSON).
    const configObj = {
      sileroVad: {
        model: config.modelPath,
        threshold: config.threshold ?? 0.5,
        minSilenceDuration: config.minSilenceDuration ?? 0.5,
        minSpeechDuration: config.minSpeechDuration ?? 0.25,
        maxSpeechDuration: config.maxSpeechDuration ?? 5.0,
        windowSize: config.windowSize ?? 512,
      },
      tenVad: {
        model: '',
        threshold: 0.5,
        minSilenceDuration: 0.5,
        minSpeechDuration: 0.25,
        maxSpeechDuration: 20,
        windowSize: 256,
      },
      sampleRate: this._sampleRate,
      numThreads: 1,
      provider: 'cpu',
      debug: 0,
    };

    const { initSherpaOnnxVadModelConfig, freeConfig } = await loadVADHelpers();
    const configStruct = initSherpaOnnxVadModelConfig(configObj, m);

    try {
      this._vadHandle = m._SherpaOnnxCreateVoiceActivityDetector(
        configStruct.ptr, bufferSizeInSeconds
      );
      freeConfig(configStruct, m);

      if (this._vadHandle === 0) {
        throw new SDKError(SDKErrorCode.ModelLoadFailed, 'Failed to create VAD from Silero model');
      }

      const loadTimeMs = Math.round(performance.now() - startMs);
      logger.info(`Silero VAD loaded in ${loadTimeMs}ms`);
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, {
        modelId: 'silero-vad', component: 'vad', loadTimeMs,
      });
    } catch (error) {
      this.cleanup();
      throw error;
    }
  }

  /** Whether VAD model is loaded. */
  get isInitialized(): boolean {
    return this._vadHandle !== 0;
  }

  /**
   * Register a callback for speech activity events.
   * Called when speech starts, ends, or is ongoing.
   */
  onSpeechActivity(callback: SpeechActivityCallback): () => void {
    this._jsActivityCallback = callback;
    return () => { this._jsActivityCallback = null; };
  }

  /**
   * Process audio samples through VAD.
   * Returns whether speech was detected in this frame.
   *
   * The Silero VAD expects 512-sample windows at 16kHz.
   * This method handles arbitrary-length input by feeding in chunks.
   *
   * @param samples - Float32Array of PCM audio samples (mono, 16kHz)
   * @returns Whether speech is currently detected
   */
  processSamples(samples: Float32Array): boolean {
    if (this._vadHandle === 0) {
      logger.warning('VAD not initialized. Call loadModel() first.');
      return false;
    }

    const m = SherpaONNXBridge.shared.module;

    // Copy samples to WASM memory
    const audioPtr = m._malloc(samples.length * 4);
    m.HEAPF32.set(samples, audioPtr / 4);

    try {
      // Feed samples to VAD
      m._SherpaOnnxVoiceActivityDetectorAcceptWaveform(this._vadHandle, audioPtr, samples.length);

      // Check detection state
      const detected = m._SherpaOnnxVoiceActivityDetectorDetected(this._vadHandle) !== 0;

      // Emit speech activity callbacks and analytics
      if (detected && !this._lastSpeechState) {
        this._speechStartMs = performance.now();
        this._jsActivityCallback?.(SpeechActivity.Started);
        EventBus.shared.emit('vad.speechStarted', SDKEventType.Voice, { activity: SpeechActivity.Started });
        AnalyticsEmitter.emitVADSpeechStarted();
      } else if (!detected && this._lastSpeechState) {
        const speechDurationMs = this._speechStartMs > 0 ? performance.now() - this._speechStartMs : 0;
        this._speechStartMs = 0;
        this._jsActivityCallback?.(SpeechActivity.Ended);
        EventBus.shared.emit('vad.speechEnded', SDKEventType.Voice, { activity: SpeechActivity.Ended });
        AnalyticsEmitter.emitVADSpeechEnded(speechDurationMs, 0);
      } else if (detected) {
        this._jsActivityCallback?.(SpeechActivity.Ongoing);
      }

      this._lastSpeechState = detected;
      return detected;
    } finally {
      m._free(audioPtr);
    }
  }

  /**
   * Get the next available speech segment (if any).
   * Returns null if no complete segments are available.
   *
   * After calling processSamples(), check for available segments
   * using this method. Call repeatedly until it returns null.
   */
  popSpeechSegment(): SpeechSegment | null {
    if (this._vadHandle === 0) return null;

    const m = SherpaONNXBridge.shared.module;

    // Check if there's a segment available
    if (m._SherpaOnnxVoiceActivityDetectorEmpty(this._vadHandle) !== 0) {
      return null;
    }

    // Get the front segment
    const segmentPtr = m._SherpaOnnxVoiceActivityDetectorFront(this._vadHandle);
    if (segmentPtr === 0) return null;

    // Read segment struct: { int32_t start; const float* samples; int32_t n; }
    // (matches sherpa-onnx-vad.js Vad.front() layout)
    const startTime = m.HEAP32[segmentPtr / 4];
    const samplesPtr = m.HEAP32[segmentPtr / 4 + 1];
    const numSamples = m.HEAP32[segmentPtr / 4 + 2];

    // Copy samples from WASM heap
    const samples = new Float32Array(numSamples);
    if (samplesPtr && numSamples > 0) {
      samples.set(m.HEAPF32.subarray(samplesPtr / 4, samplesPtr / 4 + numSamples));
    }

    // Destroy the segment and pop
    m._SherpaOnnxDestroySpeechSegment(segmentPtr);
    m._SherpaOnnxVoiceActivityDetectorPop(this._vadHandle);

    return { startTime, samples };
  }

  /** Whether speech is currently detected. */
  get isSpeechActive(): boolean {
    if (this._vadHandle === 0) return false;
    return SherpaONNXBridge.shared.module._SherpaOnnxVoiceActivityDetectorDetected(this._vadHandle) !== 0;
  }

  /** Reset VAD state. */
  reset(): void {
    if (this._vadHandle === 0) return;
    SherpaONNXBridge.shared.module._SherpaOnnxVoiceActivityDetectorReset(this._vadHandle);
    this._lastSpeechState = false;
  }

  /** Flush remaining audio through VAD. */
  flush(): void {
    if (this._vadHandle === 0) return;
    SherpaONNXBridge.shared.module._SherpaOnnxVoiceActivityDetectorFlush(this._vadHandle);
  }

  /** Clean up the VAD resources. */
  cleanup(): void {
    if (this._vadHandle !== 0) {
      try {
        SherpaONNXBridge.shared.module._SherpaOnnxDestroyVoiceActivityDetector(this._vadHandle);
      } catch { /* ignore */ }
      this._vadHandle = 0;
    }
    this._jsActivityCallback = null;
    this._lastSpeechState = false;
    this._speechStartMs = 0;
  }
}

export const VAD = new VADImpl();
