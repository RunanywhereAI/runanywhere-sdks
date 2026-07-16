// catalog.ts — a small built-in model catalog so callers can load by id
// (`loadLLM('smollm2-135m')`) instead of hunting down files. Entries are small,
// verified models that work with the linked engines. Callers can always pass a
// local path instead of an id.

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
}

const HF = 'https://huggingface.co';
const K2 = 'https://github.com/k2-fsa/sherpa-onnx/releases/download';

export const CATALOG: Record<string, CatalogEntry> = {
  'smollm2-135m': {
    type: 'llm',
    files: [
      {
        url: `${HF}/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf`,
        as: 'model.gguf',
      },
    ],
    primary: 'model.gguf',
  },
  'qwen2.5-0.5b': {
    type: 'llm',
    files: [
      {
        url: `${HF}/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`,
        as: 'model.gguf',
      },
    ],
    primary: 'model.gguf',
  },
  'smolvlm-256m': {
    type: 'vlm',
    files: [
      {
        url: `${HF}/ggml-org/SmolVLM-256M-Instruct-GGUF/resolve/main/SmolVLM-256M-Instruct-Q8_0.gguf`,
        as: 'model.gguf',
      },
      {
        url: `${HF}/ggml-org/SmolVLM-256M-Instruct-GGUF/resolve/main/mmproj-SmolVLM-256M-Instruct-Q8_0.gguf`,
        as: 'mmproj.gguf',
      },
    ],
    primary: 'model.gguf',
    mmproj: 'mmproj.gguf',
  },
  minilm: {
    type: 'embedder',
    files: [
      { url: `${HF}/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx`, as: 'model.onnx' },
      { url: `${HF}/sentence-transformers/all-MiniLM-L6-v2/resolve/main/vocab.txt`, as: 'vocab.txt' },
    ],
    primary: 'model.onnx',
  },
  'whisper-tiny': {
    type: 'stt',
    files: [{ url: `${K2}/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2`, as: 'whisper.tar.bz2' }],
    archive: true,
    primary: 'sherpa-onnx-whisper-tiny.en',
  },
  'piper-lessac': {
    type: 'tts',
    files: [{ url: `${K2}/tts-models/vits-piper-en_US-lessac-medium.tar.bz2`, as: 'piper.tar.bz2' }],
    archive: true,
    primary: 'vits-piper-en_US-lessac-medium',
  },
};

export function isCatalogId(idOrPath: string): boolean {
  return Object.prototype.hasOwnProperty.call(CATALOG, idOrPath);
}
