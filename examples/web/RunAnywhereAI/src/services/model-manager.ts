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
} from '@runanywhere/web';
import { VLMWorkerBridge } from '@runanywhere/web-llamacpp';
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
  // ── LFM2 + Qwen entries removed from web catalog (B-WEB-4-001b) ──
  // LFM2 + Qwen architectures hit a generate_stream WASM trap on both CPU
  // and WebGPU builds (FA cross-backend bug on WebGPU; chat-template /
  // decode trap on CPU). SmolLM2 360M Q8_0 is the only fully-working chat
  // model on web. The CPU-fallback regex in
  // `sdk/runanywhere-web/packages/llamacpp/src/Extensions/RunAnywhere+TextGeneration.ts`
  // is left in place as scaffolding for when LFM2/Qwen come back.

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
  // Served by the Sherpa-ONNX engine plugin (framework = SHERPA).
  // =========================================================================
  {
    id: 'sherpa-onnx-whisper-tiny.en',
    name: 'Whisper Tiny English (ONNX)',
    url: 'https://huggingface.co/runanywhere/sherpa-onnx-whisper-tiny.en/resolve/main/sherpa-onnx-whisper-tiny.en.tar.gz',
    framework: LLMFramework.Sherpa,
    modality: ModelCategory.SpeechRecognition,
    memoryRequirement: 105_000_000,
    artifactType: 'archive',
  },

  // =========================================================================
  // TTS models (sherpa-onnx Piper VITS, tar.gz archives — matches Swift SDK)
  // Archives bundle model.onnx + tokens.txt + espeak-ng-data/ in one file.
  // Served by the Sherpa-ONNX engine plugin (framework = SHERPA).
  // =========================================================================
  {
    id: 'vits-piper-en_US-lessac-medium',
    name: 'Piper TTS US English (Lessac)',
    url: 'https://huggingface.co/runanywhere/vits-piper-en_US-lessac-medium/resolve/main/vits-piper-en_US-lessac-medium.tar.gz',
    framework: LLMFramework.Sherpa,
    modality: ModelCategory.SpeechSynthesis,
    memoryRequirement: 65_000_000,
    artifactType: 'archive',
  },
  {
    id: 'vits-piper-en_GB-alba-medium',
    name: 'Piper TTS British English (Alba)',
    url: 'https://huggingface.co/runanywhere/vits-piper-en_GB-alba-medium/resolve/main/vits-piper-en_GB-alba-medium.tar.gz',
    framework: LLMFramework.Sherpa,
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
    modality: ModelCategory.VoiceActivityDetection,
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
  if (ModelManager.getLoadedModel(ModelCategory.VoiceActivityDetection)) return true;

  // VAD is a tiny helper model (~2MB) that must always coexist with
  // pipeline models (STT, LLM, TTS). Never unload other models for it.
  const coexistOpts = { coexist: true };

  // Try ensureLoaded (loads an already-downloaded model)
  const loaded = await ModelManager.ensureLoaded(ModelCategory.VoiceActivityDetection, coexistOpts);
  if (loaded) return true;

  // Not downloaded yet — find the VAD model and download + load it
  const vadModel = ModelManager.getModels().find(m => m.modality === ModelCategory.VoiceActivityDetection);
  if (!vadModel) return false;

  await ModelManager.downloadModel(vadModel.id);
  await ModelManager.loadModel(vadModel.id, coexistOpts);
  return !!ModelManager.getLoadedModel(ModelCategory.VoiceActivityDetection);
}

// ---------------------------------------------------------------------------
// Register models and plug in VLM loader via RunAnywhere API
// ---------------------------------------------------------------------------

// Per-entry registration matches the other 4 example apps (Swift / Kotlin /
// Flutter / RN). The SDK does not expose a `registerModels` plural; the
// canonical batch path is a loop over `registerModel`. Any per-entry failure
// is logged but must not abort the loop — each catalog entry is independent.
for (const model of REGISTERED_MODELS) {
  try {
    RunAnywhere.registerModel(model);
  } catch (err) {
    console.error('[model-manager] registerModel failed', model.id, err);
  }
}

// Visibility check for G-DV28 regression watch: if the catalog size drops
// below what was declared, something silently dropped entries.
{
  const registered = RunAnywhere.modelManagement.list();
  if (registered.length !== REGISTERED_MODELS.length) {
    console.warn(
      `[model-manager] registered ${registered.length} / ${REGISTERED_MODELS.length} models`,
      { registered: registered.map((m) => m.id), declared: REGISTERED_MODELS.map((m) => m.id) },
    );
  }
}

// Import the VLM worker using Vite's ?worker&url suffix so it gets compiled
// as a standalone bundle with all dependencies resolved — no raw-source data URLs.
// @ts-ignore — Vite-specific import query
import vlmWorkerUrl from '@runanywhere/web-llamacpp/vlm-worker?worker&url';
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
