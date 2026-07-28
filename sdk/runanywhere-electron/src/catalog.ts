// catalog.ts — a curated built-in model catalog so callers can load by id
// (`loadLLM('qwen2.5-1.5b')`) instead of hunting down files. Entries point at
// verified HuggingFace / k2-fsa releases that work with the linked engines.
// Callers can also pass a HuggingFace repo id, a direct URL, or a local path.

export type ModelType = 'llm' | 'vlm' | 'embedder' | 'stt' | 'tts';

export interface CatalogFile {
  url: string;
  /** Filename to save as inside the model's dir. */
  as: string;
}

export interface CatalogEntry {
  type: ModelType;
  files: CatalogFile[];
  /** If true, each downloaded file is a .tar.bz2 to extract in place. */
  archive?: boolean;
  /** Path (relative to the model dir) passed to loadLLM/loadSTT/etc. */
  primary: string;
  /** For VLM: the mmproj path (relative to the model dir). */
  mmproj?: string;
  /** Human-readable name for UIs. */
  label?: string;
  /** Parameter count, e.g. "1.5B". */
  params?: string;
  /** Approximate download size in MB. */
  sizeMB?: number;
  /** Slow / memory-heavy on a CPU-only build. */
  heavy?: boolean;
  /**
   * The weights' licence. NOT all of these are open source — Gemma and Llama
   * carry use restrictions the user accepts by downloading, so a UI that offers
   * the model must be able to say which licence applies and link to it.
   */
  license?: string;
  licenseUrl?: string;
  /**
   * The turn markup this model was trained on. Getting it wrong makes a model
   * ignore the conversation and answer as if every turn were the first.
   */
  chatTemplate?: 'chatml' | 'llama3' | 'gemma' | 'mistral';
}

/** Licences used by the catalog, so a UI can show terms before downloading. */
export const LICENSES: Record<string, { name: string; url: string }> = {
  apache2: { name: 'Apache 2.0', url: 'https://www.apache.org/licenses/LICENSE-2.0' },
  mit: { name: 'MIT', url: 'https://opensource.org/license/mit' },
  gemma: { name: 'Gemma Terms of Use', url: 'https://ai.google.dev/gemma/terms' },
  llama32: { name: 'Llama 3.2 Community License', url: 'https://github.com/meta-llama/llama-models/blob/main/models/llama3_2/LICENSE' },
  nvidiaOpen: { name: 'NVIDIA Open Model License', url: 'https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/' },
};

const HF = 'https://huggingface.co';
const K2 = 'https://github.com/k2-fsa/sherpa-onnx/releases/download';

function llm(repo: string, file: string, label: string, params: string, sizeMB: number, heavy = false,
             license = 'apache2', chatTemplate: CatalogEntry['chatTemplate'] = 'chatml'): CatalogEntry {
  const l = LICENSES[license];
  return { type: 'llm', files: [{ url: `${HF}/${repo}/resolve/main/${file}`, as: 'model.gguf' }],
           primary: 'model.gguf', label, params, sizeMB, heavy, license: l && l.name, licenseUrl: l && l.url, chatTemplate };
}
function vlm(repo: string, file: string, mm: string, label: string, params: string, sizeMB: number, heavy = false,
             license = 'apache2', chatTemplate: CatalogEntry['chatTemplate'] = 'chatml'): CatalogEntry {
  const l = LICENSES[license];
  return {
    type: 'vlm',
    files: [
      { url: `${HF}/${repo}/resolve/main/${file}`, as: 'model.gguf' },
      { url: `${HF}/${repo}/resolve/main/${mm}`, as: 'mmproj.gguf' },
    ],
    primary: 'model.gguf', mmproj: 'mmproj.gguf', label, params, sizeMB, heavy,
    license: l && l.name, licenseUrl: l && l.url, chatTemplate,
  };
}
function whisper(size: string, label: string, sizeMB: number): CatalogEntry {
  return { type: 'stt', files: [{ url: `${K2}/asr-models/sherpa-onnx-whisper-${size}.tar.bz2`, as: 'whisper.tar.bz2' }], archive: true, primary: `sherpa-onnx-whisper-${size}`, label, sizeMB };
}
function piper(voice: string, label: string, sizeMB: number): CatalogEntry {
  return { type: 'tts', files: [{ url: `${K2}/tts-models/vits-piper-en_US-${voice}-medium.tar.bz2`, as: 'piper.tar.bz2' }], archive: true, primary: `vits-piper-en_US-${voice}-medium`, label, sizeMB };
}

export const CATALOG: Record<string, CatalogEntry> = {
  // ---- LLMs (GGUF, llama.cpp) ----
  // Every URL below was HTTP-verified (200 + "GGUF" magic bytes) on 2026-07-27.
  // Sizes are the real content-length, not estimates.
  'qwen3.5-0.8b': llm('unsloth/Qwen3.5-0.8B-GGUF', 'Qwen3.5-0.8B-Q4_K_M.gguf', 'Qwen3.5 0.8B', '0.8B', 508),
  'lfm2.5-1.2b': llm('LiquidAI/LFM2.5-1.2B-Instruct-GGUF', 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf', 'LFM2.5 1.2B', '1.2B', 697),
  'qwen3.5-2b': llm('unsloth/Qwen3.5-2B-GGUF', 'Qwen3.5-2B-Q4_K_M.gguf', 'Qwen3.5 2B', '2B', 1222),
  'llama-3.2-3b': llm('unsloth/Llama-3.2-3B-Instruct-GGUF', 'Llama-3.2-3B-Instruct-Q4_K_M.gguf', 'Llama 3.2 3B', '3B', 1926, true, 'llama32', 'llama3'),
  'ministral-3-3b': llm('mistralai/Ministral-3-3B-Instruct-2512-GGUF', 'Ministral-3-3B-Instruct-2512-Q4_K_M.gguf', 'Ministral 3 3B', '3B', 2048, true, 'apache2', 'mistral'),
  'phi-4-mini': llm('unsloth/Phi-4-mini-instruct-GGUF', 'Phi-4-mini-instruct-Q4_K_M.gguf', 'Phi-4 mini', '3.8B', 2376, true),
  'qwen3.5-4b': llm('unsloth/Qwen3.5-4B-GGUF', 'Qwen3.5-4B-Q4_K_M.gguf', 'Qwen3.5 4B', '4B', 2614, true),
  'nemotron3-nano-4b': llm('nvidia/NVIDIA-Nemotron-3-Nano-4B-GGUF', 'NVIDIA-Nemotron3-Nano-4B-Q4_K_M.gguf', 'Nemotron 3 Nano 4B', '4B', 2706, true, 'nvidiaOpen'),
  'gemma-4-e2b': llm('unsloth/gemma-4-E2B-it-GGUF', 'gemma-4-E2B-it-Q4_K_M.gguf', 'Gemma 4 E2B', '2B eff.', 2963, true, 'gemma', 'gemma'),
  'gemma-4-e4b': llm('unsloth/gemma-4-E4B-it-GGUF', 'gemma-4-E4B-it-Q4_K_M.gguf', 'Gemma 4 E4B', '4B eff.', 4747, true, 'gemma', 'gemma'),
  'qwen3.5-9b': llm('unsloth/Qwen3.5-9B-GGUF', 'Qwen3.5-9B-Q4_K_M.gguf', 'Qwen3.5 9B', '9B', 5417, true),
  // Reasoning / thinking variant — emits <think>…</think>, which the app splits out.
  'lfm2.5-1.2b-thinking': llm('LiquidAI/LFM2.5-1.2B-Thinking-GGUF', 'LFM2.5-1.2B-Thinking-Q4_K_M.gguf', 'LFM2.5 1.2B Thinking', '1.2B', 697),

  // ---- VLMs (GGUF + mmproj, llama.cpp mtmd) ----
  // The Qwen3.5 / Gemma 4 repos ship the projector alongside the model, so the
  // vision entries reuse the same repo with its mmproj.
  'qwen3.5-0.8b-vl': vlm('unsloth/Qwen3.5-0.8B-GGUF', 'Qwen3.5-0.8B-Q4_K_M.gguf', 'mmproj-F16.gguf', 'Qwen3.5 0.8B Vision', '0.8B', 738),
  'lfm2.5-vl-1.6b': vlm('LiquidAI/LFM2.5-VL-1.6B-GGUF', 'LFM2.5-VL-1.6B-Q4_K_M.gguf', 'mmproj-LFM2.5-VL-1.6b-F16.gguf', 'LFM2.5 VL 1.6B', '1.6B', 1585),
  'qwen3.5-2b-vl': vlm('unsloth/Qwen3.5-2B-GGUF', 'Qwen3.5-2B-Q4_K_M.gguf', 'mmproj-F16.gguf', 'Qwen3.5 2B Vision', '2B', 1949, true),
  'qwen3.5-4b-vl': vlm('unsloth/Qwen3.5-4B-GGUF', 'Qwen3.5-4B-Q4_K_M.gguf', 'mmproj-F16.gguf', 'Qwen3.5 4B Vision', '4B', 3413, true),
  'gemma-4-e2b-vl': vlm('unsloth/gemma-4-E2B-it-GGUF', 'gemma-4-E2B-it-Q4_K_M.gguf', 'mmproj-F16.gguf', 'Gemma 4 E2B Vision', '2B eff.', 4092, true, 'gemma', 'gemma'),
  'glm-4.6v-flash': vlm('ggml-org/GLM-4.6V-Flash-GGUF', 'GLM-4.6V-Flash-Q4_K_M.gguf', 'mmproj-GLM-4.6V-Flash-Q8_0.gguf', 'GLM-4.6V Flash', '9B', 7147, true),

  // ---- Embeddings (ONNX) ----
  minilm: {
    type: 'embedder',
    files: [
      { url: `${HF}/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx`, as: 'model.onnx' },
      { url: `${HF}/sentence-transformers/all-MiniLM-L6-v2/resolve/main/vocab.txt`, as: 'vocab.txt' },
    ],
    primary: 'model.onnx', label: 'all-MiniLM-L6-v2', params: '22M', sizeMB: 90,
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

export function isCatalogId(idOrPath: string): boolean {
  return Object.prototype.hasOwnProperty.call(CATALOG, idOrPath);
}
