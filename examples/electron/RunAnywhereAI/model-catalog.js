// model-catalog.js — THIS APP's model table.
//
// The catalog lives here, not in the SDK. The SDK owns the entry SHAPE and the
// lookup surface (`registerCatalog` / `isCatalogId` in `src/catalog.ts`); the app
// owns WHICH models it offers. Every other platform in this repo does the same —
// iOS `ModelCatalogBootstrap.swift`, Android `ModelCatalog.kt`, web
// `model-catalog.ts`, Flutter `model_catalog_bootstrap.dart`, React Native
// `ModelCatalogBootstrap.ts` — all in `examples/`, none in an SDK. That split is
// what lets two apps ship different model lists against one SDK build.
//
// Plain CommonJS on purpose: this app has no build step, and the SDK's tsc has
// `rootDir: "src"` so it cannot compile a file that lives out here.
//
// Registration is PER PROCESS, and this app has two that resolve models: the
// renderer preload (`preload.js`) and the forked utility host (which downloads
// and resolves). `main.js` passes this file's path to `RunAnywhereMain` so the
// host can register it too. See `registerCatalog` in the SDK for why.
//
// Rows are grouped BY FAMILY (matching the Swift catalog's organization), so a
// family's chat model and its vision variant sit together.

const LICENSES = {
  apache2: { name: 'Apache 2.0', url: 'https://www.apache.org/licenses/LICENSE-2.0' },
  mit: { name: 'MIT', url: 'https://opensource.org/license/mit' },
  gemma: { name: 'Gemma Terms of Use', url: 'https://ai.google.dev/gemma/terms' },
  llama32: {
    name: 'Llama 3.2 Community License',
    url: 'https://github.com/meta-llama/llama-models/blob/main/models/llama3_2/LICENSE',
  },
  nvidiaOpen: {
    name: 'NVIDIA Open Model License',
    url: 'https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/',
  },
};

const HF = 'https://huggingface.co';
const K2 = 'https://github.com/k2-fsa/sherpa-onnx/releases/download';

function llm(repo, file, label, params, sizeMB, heavy = false, license = 'apache2', chatTemplate = 'chatml') {
  const l = LICENSES[license];
  return {
    type: 'llm',
    files: [{ url: `${HF}/${repo}/resolve/main/${file}`, as: 'model.gguf' }],
    primary: 'model.gguf',
    label, params, sizeMB, heavy,
    license: l && l.name, licenseUrl: l && l.url, chatTemplate,
  };
}

function vlm(repo, file, mm, label, params, sizeMB, heavy = false, license = 'apache2', chatTemplate = 'chatml') {
  const l = LICENSES[license];
  return {
    type: 'vlm',
    files: [
      { url: `${HF}/${repo}/resolve/main/${file}`, as: 'model.gguf' },
      { url: `${HF}/${repo}/resolve/main/${mm}`, as: 'mmproj.gguf' },
    ],
    primary: 'model.gguf',
    mmproj: 'mmproj.gguf',
    label, params, sizeMB, heavy,
    license: l && l.name, licenseUrl: l && l.url, chatTemplate,
  };
}

function whisper(size, label, sizeMB) {
  return {
    type: 'stt',
    files: [{ url: `${K2}/asr-models/sherpa-onnx-whisper-${size}.tar.bz2`, as: 'whisper.tar.bz2' }],
    archive: true,
    primary: `sherpa-onnx-whisper-${size}`,
    label, sizeMB,
  };
}

function piper(voice, label, sizeMB) {
  return {
    type: 'tts',
    files: [{ url: `${K2}/tts-models/vits-piper-en_US-${voice}-medium.tar.bz2`, as: 'piper.tar.bz2' }],
    archive: true,
    primary: `vits-piper-en_US-${voice}-medium`,
    label, sizeMB,
  };
}

// Every URL below was HTTP-verified (200 + "GGUF" magic bytes) on 2026-07-27,
// and the LFM2.5 230M row on 2026-08-05. Sizes are the real content-length, not
// estimates.
const CATALOG = {
  // ---- Qwen3.5 (chat + vision; one repo ships both the model and its projector) ----
  'qwen3.5-0.8b': llm('unsloth/Qwen3.5-0.8B-GGUF', 'Qwen3.5-0.8B-Q4_K_M.gguf', 'Qwen3.5 0.8B', '0.8B', 508),
  'qwen3.5-0.8b-vl': vlm('unsloth/Qwen3.5-0.8B-GGUF', 'Qwen3.5-0.8B-Q4_K_M.gguf', 'mmproj-F16.gguf', 'Qwen3.5 0.8B Vision', '0.8B', 738),
  'qwen3.5-2b': llm('unsloth/Qwen3.5-2B-GGUF', 'Qwen3.5-2B-Q4_K_M.gguf', 'Qwen3.5 2B', '2B', 1222),
  'qwen3.5-2b-vl': vlm('unsloth/Qwen3.5-2B-GGUF', 'Qwen3.5-2B-Q4_K_M.gguf', 'mmproj-F16.gguf', 'Qwen3.5 2B Vision', '2B', 1949, true),
  'qwen3.5-4b': llm('unsloth/Qwen3.5-4B-GGUF', 'Qwen3.5-4B-Q4_K_M.gguf', 'Qwen3.5 4B', '4B', 2614, true),
  'qwen3.5-4b-vl': vlm('unsloth/Qwen3.5-4B-GGUF', 'Qwen3.5-4B-Q4_K_M.gguf', 'mmproj-F16.gguf', 'Qwen3.5 4B Vision', '4B', 3413, true),
  'qwen3.5-9b': llm('unsloth/Qwen3.5-9B-GGUF', 'Qwen3.5-9B-Q4_K_M.gguf', 'Qwen3.5 9B', '9B', 5417, true),

  // ---- LFM2.5 (Liquid AI) — chat, a reasoning variant that emits <think>…</think>
  //      (the app splits it out), and vision ----
  'lfm2.5-230m': llm('LiquidAI/LFM2.5-230M-GGUF', 'LFM2.5-230M-Q4_K_M.gguf', 'LFM2.5 230M', '230M', 146),
  'lfm2.5-1.2b': llm('LiquidAI/LFM2.5-1.2B-Instruct-GGUF', 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf', 'LFM2.5 1.2B', '1.2B', 697),
  'lfm2.5-1.2b-thinking': llm('LiquidAI/LFM2.5-1.2B-Thinking-GGUF', 'LFM2.5-1.2B-Thinking-Q4_K_M.gguf', 'LFM2.5 1.2B Thinking', '1.2B', 697),
  'lfm2.5-vl-1.6b': vlm('LiquidAI/LFM2.5-VL-1.6B-GGUF', 'LFM2.5-VL-1.6B-Q4_K_M.gguf', 'mmproj-LFM2.5-VL-1.6b-F16.gguf', 'LFM2.5 VL 1.6B', '1.6B', 1585),

  // ---- Gemma 4 (Google) — weights carry use restrictions, see LICENSES.gemma ----
  'gemma-4-e2b': llm('unsloth/gemma-4-E2B-it-GGUF', 'gemma-4-E2B-it-Q4_K_M.gguf', 'Gemma 4 E2B', '2B eff.', 2963, true, 'gemma', 'gemma'),
  'gemma-4-e2b-vl': vlm('unsloth/gemma-4-E2B-it-GGUF', 'gemma-4-E2B-it-Q4_K_M.gguf', 'mmproj-F16.gguf', 'Gemma 4 E2B Vision', '2B eff.', 4092, true, 'gemma', 'gemma'),
  'gemma-4-e4b': llm('unsloth/gemma-4-E4B-it-GGUF', 'gemma-4-E4B-it-Q4_K_M.gguf', 'Gemma 4 E4B', '4B eff.', 4747, true, 'gemma', 'gemma'),

  // ---- Llama (Meta) — Llama 3.2 Community License ----
  'llama-3.2-3b': llm('unsloth/Llama-3.2-3B-Instruct-GGUF', 'Llama-3.2-3B-Instruct-Q4_K_M.gguf', 'Llama 3.2 3B', '3B', 1926, true, 'llama32', 'llama3'),

  // ---- Ministral (Mistral AI) ----
  'ministral-3-3b': llm('mistralai/Ministral-3-3B-Instruct-2512-GGUF', 'Ministral-3-3B-Instruct-2512-Q4_K_M.gguf', 'Ministral 3 3B', '3B', 2048, true, 'apache2', 'mistral'),

  // ---- Phi (Microsoft) ----
  'phi-4-mini': llm('unsloth/Phi-4-mini-instruct-GGUF', 'Phi-4-mini-instruct-Q4_K_M.gguf', 'Phi-4 mini', '3.8B', 2376, true),

  // ---- Nemotron (NVIDIA) — NVIDIA Open Model License ----
  'nemotron3-nano-4b': llm('nvidia/NVIDIA-Nemotron-3-Nano-4B-GGUF', 'NVIDIA-Nemotron3-Nano-4B-Q4_K_M.gguf', 'Nemotron 3 Nano 4B', '4B', 2706, true, 'nvidiaOpen'),

  // ---- GLM (Zhipu) — vision only ----
  'glm-4.6v-flash': vlm('ggml-org/GLM-4.6V-Flash-GGUF', 'GLM-4.6V-Flash-Q4_K_M.gguf', 'mmproj-GLM-4.6V-Flash-Q8_0.gguf', 'GLM-4.6V Flash', '9B', 7147, true),

  // ---- Embeddings (ONNX) ----
  minilm: {
    type: 'embedder',
    files: [
      { url: `${HF}/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx`, as: 'model.onnx' },
      { url: `${HF}/sentence-transformers/all-MiniLM-L6-v2/resolve/main/vocab.txt`, as: 'vocab.txt' },
    ],
    primary: 'model.onnx',
    label: 'all-MiniLM-L6-v2',
    params: '22M',
    sizeMB: 90,
  },

  // ---- Speech-to-text (Whisper via sherpa-onnx) ----
  'whisper-tiny': whisper('tiny.en', 'Whisper tiny (en)', 75),
  'whisper-base': whisper('base.en', 'Whisper base (en)', 142),
  'whisper-small': whisper('small.en', 'Whisper small (en)', 466),

  // ---- Text-to-speech (Piper via sherpa-onnx) ----
  'piper-lessac': piper('lessac', 'Piper · Lessac', 64),
  'piper-amy': piper('amy', 'Piper · Amy', 64),
  'piper-ryan': piper('ryan', 'Piper · Ryan', 64),
};

module.exports = { CATALOG, LICENSES };
