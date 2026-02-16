/**
 * Model Loader Interfaces
 *
 * Defines the contracts that model-loading extensions must implement.
 * ModelManager depends on these interfaces (Infrastructure layer) rather
 * than on the concrete extension objects in the Public layer, keeping the
 * dependency flow correct: Public -> Infrastructure -> Foundation.
 *
 * Registrations are performed by the Public layer during SDK initialisation.
 */

import type { STTModelConfig } from '../Public/Extensions/STTTypes';
import type { TTSVoiceConfig } from '../Public/Extensions/TTSTypes';
import type { VADModelConfig } from '../Public/Extensions/VADTypes';

// ---------------------------------------------------------------------------
// Loader Interfaces
// ---------------------------------------------------------------------------

/** Loader for LLM text generation models (RACommons WASM). */
export interface LLMModelLoader {
  loadModel(modelPath: string, modelId: string, modelName?: string): Promise<void>;
  unloadModel(): Promise<void>;
}

/** Loader for STT models (sherpa-onnx). */
export interface STTModelLoader {
  loadModel(config: STTModelConfig): Promise<void>;
  unloadModel(): Promise<void>;
}

/** Loader for TTS voice models (sherpa-onnx). */
export interface TTSModelLoader {
  loadVoice(config: TTSVoiceConfig): Promise<void>;
  unloadVoice(): Promise<void>;
}

/** Loader for VAD models (sherpa-onnx). */
export interface VADModelLoader {
  loadModel(config: VADModelConfig): Promise<void>;
  cleanup(): void;
}
