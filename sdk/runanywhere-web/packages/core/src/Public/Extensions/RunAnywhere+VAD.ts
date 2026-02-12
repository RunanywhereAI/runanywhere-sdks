/**
 * RunAnywhere Web SDK - Voice Activity Detection Extension
 *
 * Adds VAD capabilities for detecting speech in audio streams.
 * Includes both the RACommons C++ VAD (energy-based, built-in)
 * and the framework for silero VAD via sherpa-onnx WASM.
 *
 * Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VAD/
 *
 * Usage:
 *   import { VAD } from '@runanywhere/web';
 *
 *   await VAD.initialize({ energyThreshold: 0.02 });
 *   VAD.onSpeechActivity((activity) => {
 *     if (activity === 'started') console.log('Speech detected!');
 *   });
 *   VAD.processSamples(audioFloat32Array);
 */

import { RunAnywhere } from '../RunAnywhere';
import { WASMBridge } from '../../Foundation/WASMBridge';
import { SDKError } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { EventBus } from '../../Foundation/EventBus';
import { SDKEventType } from '../../types/enums';

const logger = new SDKLogger('VAD');

let _vadComponentHandle = 0;
let _activityCallbackPtr = 0;

function requireBridge(): WASMBridge {
  if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
  return WASMBridge.shared;
}

function ensureVADComponent(): number {
  if (_vadComponentHandle !== 0) return _vadComponentHandle;

  const bridge = requireBridge();
  const m = bridge.module;
  const handlePtr = m._malloc(4);
  const result = m.ccall('rac_vad_component_create', 'number', ['number'], [handlePtr]) as number;

  if (result !== 0) {
    m._free(handlePtr);
    bridge.checkResult(result, 'rac_vad_component_create');
  }

  _vadComponentHandle = m.getValue(handlePtr, 'i32');
  m._free(handlePtr);
  logger.debug('VAD component created');
  return _vadComponentHandle;
}

// ---------------------------------------------------------------------------
// VAD Types
// ---------------------------------------------------------------------------

export type SpeechActivity = 'started' | 'ended' | 'ongoing';

export type SpeechActivityCallback = (activity: SpeechActivity) => void;

export interface VADConfig {
  energyThreshold?: number;
  sampleRate?: number;
  frameLength?: number;
  enableAutoCalibration?: boolean;
  calibrationMultiplier?: number;
}

// ---------------------------------------------------------------------------
// VAD Extension
// ---------------------------------------------------------------------------

/** Active JS callback for speech activity */
let _jsActivityCallback: SpeechActivityCallback | null = null;

export const VAD = {
  /**
   * Initialize the VAD component with configuration.
   * Uses the built-in energy-based VAD (no model download needed).
   */
  async initialize(config: VADConfig = {}): Promise<void> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureVADComponent();

    logger.info('Initializing VAD component');

    // Build rac_vad_config_t
    const configSize = 28; // approximate size
    const configPtr = m._malloc(configSize);
    for (let i = 0; i < configSize; i++) m.setValue(configPtr + i, 0, 'i8');

    // model_id at offset 0 (null = use energy VAD)
    m.setValue(configPtr, 0, '*');
    // preferred_framework at offset 4
    m.setValue(configPtr + 4, -1, 'i32');
    // energy_threshold at offset 8
    m.setValue(configPtr + 8, config.energyThreshold ?? 0.015, 'float');
    // sample_rate at offset 12
    m.setValue(configPtr + 12, config.sampleRate ?? 16000, 'i32');
    // frame_length at offset 16
    m.setValue(configPtr + 16, config.frameLength ?? 0.1, 'float');
    // enable_auto_calibration at offset 20
    m.setValue(configPtr + 20, config.enableAutoCalibration ? 1 : 0, 'i32');
    // calibration_multiplier at offset 24
    m.setValue(configPtr + 24, config.calibrationMultiplier ?? 2.0, 'float');

    try {
      let result = m.ccall(
        'rac_vad_component_configure', 'number',
        ['number', 'number'], [handle, configPtr],
      ) as number;
      bridge.checkResult(result, 'rac_vad_component_configure');

      result = m.ccall(
        'rac_vad_component_initialize', 'number',
        ['number'], [handle],
      ) as number;
      bridge.checkResult(result, 'rac_vad_component_initialize');

      logger.info('VAD initialized');
    } finally {
      m._free(configPtr);
    }
  },

  /** Whether VAD is initialized. */
  get isInitialized(): boolean {
    if (_vadComponentHandle === 0) return false;
    try {
      return (WASMBridge.shared.module.ccall(
        'rac_vad_component_is_initialized', 'number', ['number'], [_vadComponentHandle],
      ) as number) === 1;
    } catch { return false; }
  },

  /**
   * Register a callback for speech activity events.
   */
  onSpeechActivity(callback: SpeechActivityCallback): () => void {
    _jsActivityCallback = callback;

    if (_vadComponentHandle === 0) return () => { _jsActivityCallback = null; };

    const m = WASMBridge.shared.module;

    // Register C callback that forwards to JS
    if (_activityCallbackPtr !== 0) {
      m.removeFunction(_activityCallbackPtr);
    }

    _activityCallbackPtr = m.addFunction((activity: number, _userData: number): number => {
      const activityMap: Record<number, SpeechActivity> = {
        0: 'started',
        1: 'ended',
        2: 'ongoing',
      };
      const mapped = activityMap[activity] ?? 'ongoing';
      _jsActivityCallback?.(mapped);

      EventBus.shared.emit(`vad.speech${mapped.charAt(0).toUpperCase() + mapped.slice(1)}`, SDKEventType.Voice, {
        activity: mapped,
      });

      return 0;
    }, 'iii');

    m.ccall(
      'rac_vad_component_set_activity_callback', 'number',
      ['number', 'number', 'number'],
      [_vadComponentHandle, _activityCallbackPtr, 0],
    );

    return () => {
      _jsActivityCallback = null;
      if (_activityCallbackPtr !== 0) {
        m.removeFunction(_activityCallbackPtr);
        _activityCallbackPtr = 0;
      }
    };
  },

  /**
   * Process audio samples through VAD.
   *
   * @param samples - Float32Array of PCM audio samples
   * @returns Whether speech was detected in this frame
   */
  processSamples(samples: Float32Array): boolean {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureVADComponent();

    // Copy to WASM memory
    const audioPtr = m._malloc(samples.length * 4);
    new Float32Array(m.HEAPU8.buffer, audioPtr, samples.length).set(samples);

    const outPtr = m._malloc(4);

    try {
      const result = m.ccall(
        'rac_vad_component_process', 'number',
        ['number', 'number', 'number', 'number'],
        [handle, audioPtr, samples.length, outPtr],
      ) as number;

      if (result !== 0) return false;
      return m.getValue(outPtr, 'i32') === 1;
    } finally {
      m._free(audioPtr);
      m._free(outPtr);
    }
  },

  /** Whether speech is currently active. */
  get isSpeechActive(): boolean {
    if (_vadComponentHandle === 0) return false;
    try {
      return (WASMBridge.shared.module.ccall(
        'rac_vad_component_is_speech_active', 'number', ['number'], [_vadComponentHandle],
      ) as number) === 1;
    } catch { return false; }
  },

  /** Set energy threshold dynamically. */
  setEnergyThreshold(threshold: number): void {
    if (_vadComponentHandle === 0) return;
    WASMBridge.shared.module.ccall(
      'rac_vad_component_set_energy_threshold', 'number',
      ['number', 'number'], [_vadComponentHandle, threshold],
    );
  },

  /** Reset VAD state. */
  reset(): void {
    if (_vadComponentHandle === 0) return;
    WASMBridge.shared.module.ccall(
      'rac_vad_component_reset', 'number', ['number'], [_vadComponentHandle],
    );
  },

  /** Clean up the VAD component. */
  cleanup(): void {
    if (_activityCallbackPtr !== 0) {
      try { WASMBridge.shared.module.removeFunction(_activityCallbackPtr); } catch { /* ignore */ }
      _activityCallbackPtr = 0;
    }
    if (_vadComponentHandle !== 0) {
      try {
        WASMBridge.shared.module.ccall(
          'rac_vad_component_destroy', null, ['number'], [_vadComponentHandle],
        );
      } catch { /* ignore */ }
      _vadComponentHandle = 0;
    }
    _jsActivityCallback = null;
  },
};
