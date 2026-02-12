/**
 * Model Manager - App-level model catalog and registration.
 *
 * The ModelManager class and all infrastructure live in the SDK.
 * This file defines the app's model catalog and plugs in the VLM worker loader.
 */

import {
  RunAnywhere,
  ModelManager,
  ModelCategory,
  LLMFramework,
  type CompactModelDef,
  type ManagedModel,
  type ModelFileDescriptor,
} from '../../../../../sdk/runanywhere-web/packages/core/src/index';

// Re-export SDK types for existing consumers (ManagedModel aliased as ModelInfo
// so the 5 view/component files that import ModelInfo need zero changes).
export { ModelManager, ModelCategory };
export type { ManagedModel as ModelInfo, ModelFileDescriptor };

// ---------------------------------------------------------------------------
// App Model Catalog
// ---------------------------------------------------------------------------

const REGISTERED_MODELS: CompactModelDef[] = [
  // =========================================================================
  // LLM models (llama.cpp GGUF)
  // =========================================================================
  {
    id: 'smollm2-360m-q8_0',
    name: 'SmolLM2 360M Q8_0',
    repo: 'prithivMLmods/SmolLM2-360M-GGUF',
    files: ['SmolLM2-360M.Q8_0.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Language,
    memoryRequirement: 500_000_000,
  },
  {
    id: 'qwen2.5-0.5b-instruct-q6_k',
    name: 'Qwen 2.5 0.5B Q6_K',
    repo: 'Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF',
    files: ['qwen2.5-0.5b-instruct-q6_k.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Language,
    memoryRequirement: 600_000_000,
  },
  {
    id: 'lfm2-350m-q4_k_m',
    name: 'LFM2 350M Q4_K_M',
    repo: 'LiquidAI/LFM2-350M-GGUF',
    files: ['LFM2-350M-Q4_K_M.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Language,
    memoryRequirement: 250_000_000,
  },
  {
    id: 'lfm2-350m-q8_0',
    name: 'LFM2 350M Q8_0',
    repo: 'LiquidAI/LFM2-350M-GGUF',
    files: ['LFM2-350M-Q8_0.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Language,
    memoryRequirement: 400_000_000,
  },

  // =========================================================================
  // VLM models (llama.cpp + mmproj)
  // =========================================================================
  {
    id: 'smolvlm-500m-instruct-q8_0',
    name: 'SmolVLM 500M Instruct Q8_0',
    repo: 'ggml-org/SmolVLM-500M-Instruct-GGUF',
    files: ['SmolVLM-500M-Instruct-Q8_0.gguf', 'mmproj-SmolVLM-500M-Instruct-f16.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Multimodal,
    memoryRequirement: 600_000_000,
  },
  {
    id: 'qwen2-vl-2b-instruct-q4_k_m',
    name: 'Qwen2-VL 2B Instruct Q4_K_M',
    repo: 'ggml-org/Qwen2-VL-2B-Instruct-GGUF',
    files: ['Qwen2-VL-2B-Instruct-Q4_K_M.gguf', 'mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Multimodal,
    memoryRequirement: 1_800_000_000,
  },
  {
    id: 'lfm2-vl-450m-q4_0',
    name: 'LFM2-VL 450M Q4_0',
    repo: 'LiquidAI/LFM2-VL-450M-GGUF',
    files: ['LFM2-VL-450M-Q4_0.gguf', 'mmproj-LFM2-VL-450M-Q8_0.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Multimodal,
    memoryRequirement: 500_000_000,
  },
  {
    id: 'lfm2-vl-450m-q8_0',
    name: 'LFM2-VL 450M Q8_0',
    repo: 'LiquidAI/LFM2-VL-450M-GGUF',
    files: ['LFM2-VL-450M-Q8_0.gguf', 'mmproj-LFM2-VL-450M-Q8_0.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Multimodal,
    memoryRequirement: 600_000_000,
  },

  // =========================================================================
  // STT models (sherpa-onnx Whisper, individual ONNX files)
  // =========================================================================
  {
    id: 'sherpa-onnx-whisper-tiny.en',
    name: 'Whisper Tiny English (ONNX)',
    repo: 'csukuangfj/sherpa-onnx-whisper-tiny.en',
    files: ['tiny.en-encoder.int8.onnx', 'tiny.en-decoder.int8.onnx', 'tiny.en-tokens.txt'],
    framework: LLMFramework.ONNX,
    modality: ModelCategory.SpeechRecognition,
    memoryRequirement: 105_000_000,
  },

  // =========================================================================
  // TTS models (sherpa-onnx Piper VITS, individual ONNX files)
  // =========================================================================
  {
    id: 'vits-piper-en_US-lessac-medium',
    name: 'Piper TTS US English (Lessac)',
    repo: 'csukuangfj/vits-piper-en_US-lessac-medium',
    files: ['en_US-lessac-medium.onnx', 'tokens.txt', 'en_US-lessac-medium.onnx.json'],
    framework: LLMFramework.ONNX,
    modality: ModelCategory.SpeechSynthesis,
    memoryRequirement: 65_000_000,
  },
  {
    id: 'vits-piper-en_GB-vctk-medium',
    name: 'Piper TTS British English (VCTK)',
    repo: 'csukuangfj/vits-piper-en_GB-vctk-medium',
    files: ['en_GB-vctk-medium.onnx', 'tokens.txt', 'en_GB-vctk-medium.onnx.json'],
    framework: LLMFramework.ONNX,
    modality: ModelCategory.SpeechSynthesis,
    memoryRequirement: 77_000_000,
  },

  // =========================================================================
  // VAD model (Silero VAD, single ONNX file — hosted on GitHub, not HuggingFace)
  // =========================================================================
  {
    id: 'silero-vad-v5',
    name: 'Silero VAD v5',
    url: 'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx',
    files: ['silero_vad.onnx'],
    framework: LLMFramework.ONNX,
    modality: ModelCategory.Audio,
    memoryRequirement: 5_000_000,
  },
];

// ---------------------------------------------------------------------------
// Register models and plug in VLM loader via RunAnywhere API
// ---------------------------------------------------------------------------

RunAnywhere.registerModels(REGISTERED_MODELS);

// Plug in VLM worker loading (lazy import to avoid bundling the worker eagerly)
import('./vlm-worker-bridge').then(({ VLMWorkerBridge }) => {
  RunAnywhere.setVLMLoader({
    get isInitialized() { return VLMWorkerBridge.shared.isInitialized; },
    init: () => VLMWorkerBridge.shared.init(),
    loadModel: (params) => VLMWorkerBridge.shared.loadModel(params),
    unloadModel: () => VLMWorkerBridge.shared.unloadModel(),
  });
}).catch((err) => {
  console.warn('[ModelManager] VLM worker bridge not available:', err);
});
