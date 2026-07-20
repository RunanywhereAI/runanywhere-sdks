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
}

const HF = 'https://huggingface.co';
const K2 = 'https://github.com/k2-fsa/sherpa-onnx/releases/download';

function llm(repo: string, file: string, label: string, params: string, sizeMB: number, heavy = false): CatalogEntry {
  return { type: 'llm', files: [{ url: `${HF}/${repo}/resolve/main/${file}`, as: 'model.gguf' }], primary: 'model.gguf', label, params, sizeMB, heavy };
}
function vlm(repo: string, file: string, mm: string, label: string, params: string, sizeMB: number, heavy = false): CatalogEntry {
  return {
    type: 'vlm',
    files: [
      { url: `${HF}/${repo}/resolve/main/${file}`, as: 'model.gguf' },
      { url: `${HF}/${repo}/resolve/main/${mm}`, as: 'mmproj.gguf' },
    ],
    primary: 'model.gguf', mmproj: 'mmproj.gguf', label, params, sizeMB, heavy,
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
  'smollm2-135m': llm('bartowski/SmolLM2-135M-Instruct-GGUF', 'SmolLM2-135M-Instruct-Q4_K_M.gguf', 'SmolLM2 135M', '135M', 92),
  'smollm2-360m': llm('bartowski/SmolLM2-360M-Instruct-GGUF', 'SmolLM2-360M-Instruct-Q4_K_M.gguf', 'SmolLM2 360M', '360M', 258),
  'smollm2-1.7b': llm('bartowski/SmolLM2-1.7B-Instruct-GGUF', 'SmolLM2-1.7B-Instruct-Q4_K_M.gguf', 'SmolLM2 1.7B', '1.7B', 1007),
  'qwen2.5-0.5b': llm('bartowski/Qwen2.5-0.5B-Instruct-GGUF', 'Qwen2.5-0.5B-Instruct-Q4_K_M.gguf', 'Qwen2.5 0.5B', '0.5B', 398),
  'qwen2.5-1.5b': llm('bartowski/Qwen2.5-1.5B-Instruct-GGUF', 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf', 'Qwen2.5 1.5B', '1.5B', 940),
  'qwen2.5-3b': llm('bartowski/Qwen2.5-3B-Instruct-GGUF', 'Qwen2.5-3B-Instruct-Q4_K_M.gguf', 'Qwen2.5 3B', '3B', 1841, true),
  'llama-3.2-1b': llm('bartowski/Llama-3.2-1B-Instruct-GGUF', 'Llama-3.2-1B-Instruct-Q4_K_M.gguf', 'Llama 3.2 1B', '1B', 770),
  'llama-3.2-3b': llm('bartowski/Llama-3.2-3B-Instruct-GGUF', 'Llama-3.2-3B-Instruct-Q4_K_M.gguf', 'Llama 3.2 3B', '3B', 1926, true),
  'gemma-2-2b': llm('bartowski/gemma-2-2b-it-GGUF', 'gemma-2-2b-it-Q4_K_M.gguf', 'Gemma 2 2B', '2B', 1629, true),
  'phi-3.5-mini': llm('bartowski/Phi-3.5-mini-instruct-GGUF', 'Phi-3.5-mini-instruct-Q4_K_M.gguf', 'Phi 3.5 mini', '3.8B', 2283, true),

  // ---- VLMs (GGUF + mmproj, llama.cpp mtmd) ----
  'smolvlm-256m': vlm('ggml-org/SmolVLM-256M-Instruct-GGUF', 'SmolVLM-256M-Instruct-Q8_0.gguf', 'mmproj-SmolVLM-256M-Instruct-Q8_0.gguf', 'SmolVLM 256M', '256M', 300),
  'smolvlm-500m': vlm('ggml-org/SmolVLM-500M-Instruct-GGUF', 'SmolVLM-500M-Instruct-Q8_0.gguf', 'mmproj-SmolVLM-500M-Instruct-Q8_0.gguf', 'SmolVLM 500M', '500M', 521),
  'smolvlm-2.2b': vlm('ggml-org/SmolVLM-Instruct-GGUF', 'SmolVLM-Instruct-Q8_0.gguf', 'mmproj-SmolVLM-Instruct-Q8_0.gguf', 'SmolVLM 2.2B', '2.2B', 2402, true),
  'smolvlm2-500m': vlm('ggml-org/SmolVLM2-500M-Video-Instruct-GGUF', 'SmolVLM2-500M-Video-Instruct-Q8_0.gguf', 'mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf', 'SmolVLM2 500M (video)', '500M', 521),
  'qwen2-vl-2b': vlm('ggml-org/Qwen2-VL-2B-Instruct-GGUF', 'Qwen2-VL-2B-Instruct-Q8_0.gguf', 'mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf', 'Qwen2-VL 2B', '2B', 2247, true),

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
