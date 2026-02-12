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

import { RunAnywhere } from '../RunAnywhere';
import { SherpaONNXBridge } from '../../Foundation/SherpaONNXBridge';
import { SDKError, SDKErrorCode } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { EventBus } from '../../Foundation/EventBus';
import { SDKEventType } from '../../types/enums';

const logger = new SDKLogger('VAD');

// ---------------------------------------------------------------------------
// Internal State
// ---------------------------------------------------------------------------

let _vadHandle = 0;
let _sampleRate = 16000;
let _jsActivityCallback: SpeechActivityCallback | null = null;
let _lastSpeechState = false;

// ---------------------------------------------------------------------------
// VAD Types
// ---------------------------------------------------------------------------

export type SpeechActivity = 'started' | 'ended' | 'ongoing';

export type SpeechActivityCallback = (activity: SpeechActivity) => void;

export interface VADModelConfig {
  /** Path to Silero VAD ONNX model in sherpa-onnx virtual FS */
  modelPath: string;
  /** Detection threshold (default: 0.5, range 0-1) */
  threshold?: number;
  /** Minimum silence duration in seconds to split segments (default: 0.5) */
  minSilenceDuration?: number;
  /** Minimum speech duration in seconds (default: 0.25) */
  minSpeechDuration?: number;
  /** Maximum speech duration in seconds (default: 5.0 for streaming) */
  maxSpeechDuration?: number;
  /** Sample rate (default: 16000) */
  sampleRate?: number;
  /** Window size in samples (default: 512 for Silero) */
  windowSize?: number;
}

export interface SpeechSegment {
  /** Start time in seconds */
  startTime: number;
  /** Audio samples of the speech segment */
  samples: Float32Array;
}

// ---------------------------------------------------------------------------
// VAD Extension
// ---------------------------------------------------------------------------

export const VAD = {
  /**
   * Load the Silero VAD model via sherpa-onnx.
   * The model file must already be in the sherpa-onnx virtual FS.
   */
  async loadModel(config: VADModelConfig): Promise<void> {
    const sherpa = requireSherpa();
    await sherpa.ensureLoaded();
    const m = sherpa.module;

    // Clean up previous
    VAD.cleanup();

    _sampleRate = config.sampleRate ?? 16000;

    logger.info('Loading Silero VAD model');
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, {
      modelId: 'silero-vad', component: 'vad',
    });

    const startMs = performance.now();

    // Build config JSON for sherpa-onnx VAD
    const configJson = JSON.stringify({
      'silero-vad': {
        'model': config.modelPath,
        'threshold': config.threshold ?? 0.5,
        'min-silence-duration': config.minSilenceDuration ?? 0.5,
        'min-speech-duration': config.minSpeechDuration ?? 0.25,
        'max-speech-duration': config.maxSpeechDuration ?? 5.0,
        'window-size': config.windowSize ?? 512,
      },
      'sample-rate': _sampleRate,
      'num-threads': 1,
      'provider': 'cpu',
      'debug': 0,
    });

    const configPtr = sherpa.allocString(configJson);
    const bufferSizeInSeconds = 30; // 30 second circular buffer

    try {
      _vadHandle = m._SherpaOnnxCreateVoiceActivityDetector(configPtr as unknown as number, bufferSizeInSeconds);

      if (_vadHandle === 0) {
        throw new SDKError(SDKErrorCode.ModelLoadFailed, 'Failed to create VAD from Silero model');
      }

      const loadTimeMs = Math.round(performance.now() - startMs);
      logger.info(`Silero VAD loaded in ${loadTimeMs}ms`);
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, {
        modelId: 'silero-vad', component: 'vad', loadTimeMs,
      });
    } catch (error) {
      VAD.cleanup();
      throw error;
    } finally {
      sherpa.free(configPtr);
    }
  },

  /** Whether VAD model is loaded. */
  get isInitialized(): boolean {
    return _vadHandle !== 0;
  },

  /**
   * Register a callback for speech activity events.
   * Called when speech starts, ends, or is ongoing.
   */
  onSpeechActivity(callback: SpeechActivityCallback): () => void {
    _jsActivityCallback = callback;
    return () => { _jsActivityCallback = null; };
  },

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
    if (_vadHandle === 0) {
      logger.warning('VAD not initialized. Call loadModel() first.');
      return false;
    }

    const m = SherpaONNXBridge.shared.module;

    // Copy samples to WASM memory
    const audioPtr = m._malloc(samples.length * 4);
    m.HEAPF32.set(samples, audioPtr / 4);

    try {
      // Feed samples to VAD
      m._SherpaOnnxVoiceActivityDetectorAcceptWaveform(_vadHandle, audioPtr, samples.length);

      // Check detection state
      const detected = m._SherpaOnnxVoiceActivityDetectorDetected(_vadHandle) !== 0;

      // Emit speech activity callbacks
      if (detected && !_lastSpeechState) {
        _jsActivityCallback?.('started');
        EventBus.shared.emit('vad.speechStarted', SDKEventType.Voice, { activity: 'started' });
      } else if (!detected && _lastSpeechState) {
        _jsActivityCallback?.('ended');
        EventBus.shared.emit('vad.speechEnded', SDKEventType.Voice, { activity: 'ended' });
      } else if (detected) {
        _jsActivityCallback?.('ongoing');
      }

      _lastSpeechState = detected;
      return detected;
    } finally {
      m._free(audioPtr);
    }
  },

  /**
   * Get the next available speech segment (if any).
   * Returns null if no complete segments are available.
   *
   * After calling processSamples(), check for available segments
   * using this method. Call repeatedly until it returns null.
   */
  popSpeechSegment(): SpeechSegment | null {
    if (_vadHandle === 0) return null;

    const m = SherpaONNXBridge.shared.module;

    // Check if there's a segment available
    if (m._SherpaOnnxVoiceActivityDetectorEmpty(_vadHandle) !== 0) {
      return null;
    }

    // Get the front segment
    const segmentPtr = m._SherpaOnnxVoiceActivityDetectorFront(_vadHandle);
    if (segmentPtr === 0) return null;

    // Read segment struct: { float start; int32_t n; const float* samples; }
    const startTime = m.getValue(segmentPtr, 'float');
    const numSamples = m.getValue(segmentPtr + 4, 'i32');
    const samplesPtr = m.getValue(segmentPtr + 8, '*');

    // Copy samples
    const samples = new Float32Array(numSamples);
    if (samplesPtr && numSamples > 0) {
      samples.set(m.HEAPF32.subarray(samplesPtr / 4, samplesPtr / 4 + numSamples));
    }

    // Destroy the segment and pop
    m._SherpaOnnxDestroySpeechSegment(segmentPtr);
    m._SherpaOnnxVoiceActivityDetectorPop(_vadHandle);

    return { startTime, samples };
  },

  /** Whether speech is currently detected. */
  get isSpeechActive(): boolean {
    if (_vadHandle === 0) return false;
    return SherpaONNXBridge.shared.module._SherpaOnnxVoiceActivityDetectorDetected(_vadHandle) !== 0;
  },

  /** Reset VAD state. */
  reset(): void {
    if (_vadHandle === 0) return;
    SherpaONNXBridge.shared.module._SherpaOnnxVoiceActivityDetectorReset(_vadHandle);
    _lastSpeechState = false;
  },

  /** Flush remaining audio through VAD. */
  flush(): void {
    if (_vadHandle === 0) return;
    SherpaONNXBridge.shared.module._SherpaOnnxVoiceActivityDetectorFlush(_vadHandle);
  },

  /** Clean up the VAD resources. */
  cleanup(): void {
    if (_vadHandle !== 0) {
      try {
        SherpaONNXBridge.shared.module._SherpaOnnxDestroyVoiceActivityDetector(_vadHandle);
      } catch { /* ignore */ }
      _vadHandle = 0;
    }
    _jsActivityCallback = null;
    _lastSpeechState = false;
  },
};

// ---------------------------------------------------------------------------
// Internal Helpers
// ---------------------------------------------------------------------------

function requireSherpa(): SherpaONNXBridge {
  if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
  return SherpaONNXBridge.shared;
}
