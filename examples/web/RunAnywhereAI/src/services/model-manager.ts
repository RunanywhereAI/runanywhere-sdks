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
  EventBus,
  type CompactModelDef,
  type ManagedModel,
  type ModelFileDescriptor,
} from '../../../../../sdk/runanywhere-web/packages/core/src/index';
import { VLMWorkerBridge } from '../../../../../sdk/runanywhere-web/packages/llamacpp/src/index';
import { showToast } from '../components/dialogs';

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

  // ── Tool Calling Optimized Models (Liquid AI LFM2-Tool) ──
  // These models are designed for concise, precise tool/function calling.
  // Auto-detected as LFM2 Pythonic format by the SDK's ToolCalling extension.
  {
    id: 'lfm2-1.2b-tool-q4_k_m',
    name: 'LFM2 1.2B Tool Q4_K_M',
    repo: 'LiquidAI/LFM2-1.2B-Tool-GGUF',
    files: ['LFM2-1.2B-Tool-Q4_K_M.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Language,
    memoryRequirement: 800_000_000,
  },
  {
    id: 'lfm2-1.2b-tool-q8_0',
    name: 'LFM2 1.2B Tool Q8_0',
    repo: 'LiquidAI/LFM2-1.2B-Tool-GGUF',
    files: ['LFM2-1.2B-Tool-Q8_0.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Language,
    memoryRequirement: 1_400_000_000,
  },

  // =========================================================================
  // VLM models (llama.cpp + mmproj) — hosted on runanywhere HuggingFace org
  // =========================================================================
  {
    id: 'smolvlm-500m-instruct-q8_0',
    name: 'SmolVLM 500M Instruct Q8_0',
    repo: 'runanywhere/SmolVLM-500M-Instruct-GGUF',
    files: ['SmolVLM-500M-Instruct-Q8_0.gguf', 'mmproj-SmolVLM-500M-Instruct-f16.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Multimodal,
    memoryRequirement: 600_000_000,
  },
  // NOTE: Qwen2-VL uses M-RoPE which produces NaN logits on WebGPU. It falls
  // back to CPU WASM (~1 tok/s) — noticeably slower than LFM2-VL on WebGPU.
  {
    id: 'qwen2-vl-2b-instruct-q4_k_m',
    name: 'Qwen2-VL 2B Instruct Q4_K_M',
    repo: 'runanywhere/Qwen2-VL-2B-Instruct-GGUF',
    files: ['Qwen2-VL-2B-Instruct-Q4_K_M.gguf', 'mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Multimodal,
    memoryRequirement: 1_800_000_000,
  },
  {
    id: 'lfm2-vl-450m-q4_0',
    name: 'LFM2-VL 450M Q4_0',
    repo: 'runanywhere/LFM2-VL-450M-GGUF',
    files: ['LFM2-VL-450M-Q4_0.gguf', 'mmproj-LFM2-VL-450M-Q8_0.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Multimodal,
    memoryRequirement: 500_000_000,
  },
  {
    id: 'lfm2-vl-450m-q8_0',
    name: 'LFM2-VL 450M Q8_0',
    repo: 'runanywhere/LFM2-VL-450M-GGUF',
    files: ['LFM2-VL-450M-Q8_0.gguf', 'mmproj-LFM2-VL-450M-Q8_0.gguf'],
    framework: LLMFramework.LlamaCpp,
    modality: ModelCategory.Multimodal,
    memoryRequirement: 600_000_000,
  },

  // =========================================================================
  // STT models (sherpa-onnx Whisper, tar.gz archive — matches Swift SDK)
  // =========================================================================
  {
    id: 'sherpa-onnx-whisper-tiny.en',
    name: 'Whisper Tiny English (ONNX)',
    url: 'https://huggingface.co/runanywhere/sherpa-onnx-whisper-tiny.en/resolve/main/sherpa-onnx-whisper-tiny.en.tar.gz',
    framework: LLMFramework.ONNX,
    modality: ModelCategory.SpeechRecognition,
    memoryRequirement: 105_000_000,
    artifactType: 'archive',
  },

  // =========================================================================
  // TTS models (sherpa-onnx Piper VITS, tar.gz archives — matches Swift SDK)
  // Archives bundle model.onnx + tokens.txt + espeak-ng-data/ in one file.
  // =========================================================================
  {
    id: 'vits-piper-en_US-lessac-medium',
    name: 'Piper TTS US English (Lessac)',
    url: 'https://huggingface.co/runanywhere/vits-piper-en_US-lessac-medium/resolve/main/vits-piper-en_US-lessac-medium.tar.gz',
    framework: LLMFramework.ONNX,
    modality: ModelCategory.SpeechSynthesis,
    memoryRequirement: 65_000_000,
    artifactType: 'archive',
  },
  {
    id: 'vits-piper-en_GB-alba-medium',
    name: 'Piper TTS British English (Alba)',
    url: 'https://huggingface.co/runanywhere/vits-piper-en_GB-alba-medium/resolve/main/vits-piper-en_GB-alba-medium.tar.gz',
    framework: LLMFramework.ONNX,
    modality: ModelCategory.SpeechSynthesis,
    memoryRequirement: 65_000_000,
    artifactType: 'archive',
  },

  // =========================================================================
  // VAD model (Silero VAD, single ONNX file)
  // =========================================================================
  {
    id: 'silero-vad-v5',
    name: 'Silero VAD v5',
    url: 'https://huggingface.co/runanywhere/silero-vad-v5/resolve/main/silero_vad.onnx',
    files: ['silero_vad.onnx'],
    framework: LLMFramework.ONNX,
    modality: ModelCategory.Audio,
    memoryRequirement: 5_000_000,
  },
];

// ---------------------------------------------------------------------------
// VAD Helper — auto-download + load on demand (5MB, fast)
// ---------------------------------------------------------------------------

/**
 * Ensure the Silero VAD model is downloaded and loaded.
 * Called transparently by views that need VAD (live transcription, voice assistant).
 * Returns true if VAD is ready, false if no VAD model is registered.
 */
export async function ensureVADLoaded(): Promise<boolean> {
  // Already loaded?
  if (ModelManager.getLoadedModel(ModelCategory.Audio)) return true;

  // VAD is a tiny helper model (~2MB) that must always coexist with
  // pipeline models (STT, LLM, TTS). Never unload other models for it.
  const coexistOpts = { coexist: true };

  // Try ensureLoaded (loads an already-downloaded model)
  const loaded = await ModelManager.ensureLoaded(ModelCategory.Audio, coexistOpts);
  if (loaded) return true;

  // Not downloaded yet — find the VAD model and download + load it
  const vadModel = ModelManager.getModels().find(m => m.modality === ModelCategory.Audio);
  if (!vadModel) return false;

  await ModelManager.downloadModel(vadModel.id);
  await ModelManager.loadModel(vadModel.id, coexistOpts);
  return !!ModelManager.getLoadedModel(ModelCategory.Audio);
}

// ---------------------------------------------------------------------------
// Register models and plug in VLM loader via RunAnywhere API
// ---------------------------------------------------------------------------

RunAnywhere.registerModels(REGISTERED_MODELS);

// Import the VLM worker using Vite's ?worker&url suffix so it gets compiled
// as a standalone bundle with all dependencies resolved — no raw-source data URLs.
// @ts-ignore — Vite-specific import query
import vlmWorkerUrl from '../../../../../sdk/runanywhere-web/packages/llamacpp/src/workers/vlm-worker.ts?worker&url';
VLMWorkerBridge.shared.workerUrl = vlmWorkerUrl;

// Plug in VLM worker loading using the SDK's VLMWorkerBridge
RunAnywhere.setVLMLoader({
  get isInitialized() { return VLMWorkerBridge.shared.isInitialized; },
  init: () => VLMWorkerBridge.shared.init(),
  loadModel: (params) => VLMWorkerBridge.shared.loadModel(params),
  unloadModel: () => VLMWorkerBridge.shared.unloadModel(),
});

// ---------------------------------------------------------------------------
// Storage event listeners — show toasts when auto-eviction happens
// ---------------------------------------------------------------------------

EventBus.shared.on('model.evicted', (event) => {
  const name = (event as Record<string, unknown>).modelName as string;
  const freed = (event as Record<string, unknown>).freedBytes as number;
  const freedMB = (freed / 1024 / 1024).toFixed(0);
  showToast(`Removed ${name} to free ${freedMB} MB`, 'warning');
});
