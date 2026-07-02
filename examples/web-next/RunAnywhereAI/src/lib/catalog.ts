import { InferenceFramework, ModelArtifactType, ModelCategory, ModelFileRole, ModelFormat } from '@runanywhere/proto-ts/model_types';
import type { Modality, ModelItem } from './types';

export interface CatalogFile {
  url: string;
  filename: string;
  role: ModelFileRole;
  sizeBytes: number;
}

export interface CatalogEntry {
  id: string;
  name: string;
  meta: string;
  modality: Modality;
  loadable: boolean;
  category: ModelCategory;
  framework: InferenceFramework;
  format: ModelFormat;
  downloadUrl: string;
  downloadSizeBytes: number;
  memoryRequiredBytes: number;
  contextLength?: number;
  supportsThinking?: boolean;
  files?: CatalogFile[];
  artifactType?: ModelArtifactType;
}

const LLAMA = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP;
const GGUF = ModelFormat.MODEL_FORMAT_GGUF;
const LANG = ModelCategory.MODEL_CATEGORY_LANGUAGE;

const llm: CatalogEntry[] = [
  {
    id: 'qwen3-0.6b-q4_k_m', name: 'Qwen3 0.6B', meta: '0.6B · Q4_K_M · 477 MB',
    modality: 'llm', loadable: true, category: LANG, framework: LLAMA, format: GGUF,
    downloadUrl: 'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
    downloadSizeBytes: 477_000_000, memoryRequiredBytes: 500_000_000, contextLength: 4096, supportsThinking: true,
  },
  {
    id: 'qwen2.5-0.5b-instruct-q6_k', name: 'Qwen 2.5 0.5B Instruct', meta: '0.5B · Q6_K · 505 MB',
    modality: 'llm', loadable: true, category: LANG, framework: LLAMA, format: GGUF,
    downloadUrl: 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
    downloadSizeBytes: 505_000_000, memoryRequiredBytes: 600_000_000, contextLength: 4096,
  },
  {
    id: 'lfm2-350m-q4_k_m', name: 'LiquidAI LFM2 350M', meta: '350M · Q4_K_M · 250 MB',
    modality: 'llm', loadable: true, category: LANG, framework: LLAMA, format: GGUF,
    downloadUrl: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
    downloadSizeBytes: 250_000_000, memoryRequiredBytes: 250_000_000, contextLength: 2048,
  },
  {
    id: 'smollm2-360m-q8_0', name: 'SmolLM2 360M', meta: '360M · Q8_0 · 386 MB',
    modality: 'llm', loadable: true, category: LANG, framework: LLAMA, format: GGUF,
    downloadUrl: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
    downloadSizeBytes: 386_404_416, memoryRequiredBytes: 500_000_000, contextLength: 2048,
  },
  {
    id: 'qwen3-4b-q4_k_m', name: 'Qwen3 4B', meta: '4B · Q4_K_M · 2.5 GB',
    modality: 'llm', loadable: true, category: LANG, framework: LLAMA, format: GGUF,
    downloadUrl: 'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
    downloadSizeBytes: 2_500_000_000, memoryRequiredBytes: 3_000_000_000, contextLength: 4096, supportsThinking: true,
  },
];

const speech: CatalogEntry[] = [
  {
    id: 'sherpa-onnx-whisper-tiny.en', name: 'Whisper Tiny (en)', meta: 'STT · ONNX · 100 MB', modality: 'stt', loadable: true,
    category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA, format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main/tiny.en-encoder.int8.onnx',
    downloadSizeBytes: 103_600_000, memoryRequiredBytes: 200_000_000,
    files: [
      { url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main/tiny.en-encoder.int8.onnx', filename: 'tiny.en-encoder.int8.onnx', role: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL, sizeBytes: 12_937_772 },
      { url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main/tiny.en-decoder.int8.onnx', filename: 'tiny.en-decoder.int8.onnx', role: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL, sizeBytes: 89_853_865 },
      { url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main/tiny.en-tokens.txt', filename: 'tiny.en-tokens.txt', role: ModelFileRole.MODEL_FILE_ROLE_VOCABULARY, sizeBytes: 835_554 },
    ],
  },
  {
    id: 'vits-ljs', name: 'VITS · LJSpeech', meta: 'TTS · ONNX · 38 MB', modality: 'tts', loadable: true,
    category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS, framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA, format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadUrl: 'https://huggingface.co/csukuangfj/vits-ljs/resolve/main/vits-ljs.int8.onnx',
    downloadSizeBytes: 40_000_000, memoryRequiredBytes: 90_000_000,
    files: [
      { url: 'https://huggingface.co/csukuangfj/vits-ljs/resolve/main/vits-ljs.int8.onnx', filename: 'model.int8.onnx', role: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL, sizeBytes: 37_423_560 },
      { url: 'https://huggingface.co/csukuangfj/vits-ljs/resolve/main/tokens.txt', filename: 'tokens.txt', role: ModelFileRole.MODEL_FILE_ROLE_VOCABULARY, sizeBytes: 1_200 },
      { url: 'https://huggingface.co/csukuangfj/vits-ljs/resolve/main/lexicon.txt', filename: 'lexicon.txt', role: ModelFileRole.MODEL_FILE_ROLE_VOCABULARY, sizeBytes: 1_600_000 },
    ],
  },
  { id: 'silero-vad', name: 'Silero VAD', meta: 'VAD · ONNX · 2 MB', modality: 'vad', loadable: false, category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION, framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA, format: ModelFormat.MODEL_FORMAT_ONNX, downloadUrl: '', downloadSizeBytes: 2_000_000, memoryRequiredBytes: 10_000_000 },
];

const PRIMARY = ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL;
const PROJECTOR = ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR;
const MULTIMODAL = ModelCategory.MODEL_CATEGORY_MULTIMODAL;

const vision: CatalogEntry[] = [
  {
    id: 'smolvlm2-256m-video-instruct-q8_0', name: 'SmolVLM2 256M', meta: '256M · Q8_0 · 279 MB',
    modality: 'vlm', loadable: true, category: MULTIMODAL, framework: LLAMA, format: GGUF,
    downloadUrl: 'https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
    downloadSizeBytes: 278_828_032, memoryRequiredBytes: 420_000_000, contextLength: 2048,
    files: [
      { url: 'https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/SmolVLM2-256M-Video-Instruct-Q8_0.gguf', filename: 'SmolVLM2-256M-Video-Instruct-Q8_0.gguf', role: PRIMARY, sizeBytes: 175_056_352 },
      { url: 'https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf', filename: 'mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf', role: PROJECTOR, sizeBytes: 103_771_680 },
    ],
  },
  {
    id: 'lfm2-vl-450m-q8_0', name: 'LFM2-VL 450M', meta: '450M · Q8_0 · 460 MB',
    modality: 'vlm', loadable: true, category: MULTIMODAL, framework: LLAMA, format: GGUF,
    downloadUrl: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf',
    downloadSizeBytes: 460_000_000, memoryRequiredBytes: 600_000_000, contextLength: 2048,
    files: [
      { url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf', filename: 'LFM2-VL-450M-Q8_0.gguf', role: PRIMARY, sizeBytes: 370_000_000 },
      { url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf', filename: 'mmproj-LFM2-VL-450M-Q8_0.gguf', role: PROJECTOR, sizeBytes: 90_000_000 },
    ],
  },
];

const ONNX = InferenceFramework.INFERENCE_FRAMEWORK_ONNX;
const ONNX_FMT = ModelFormat.MODEL_FORMAT_ONNX;
const VOCAB = ModelFileRole.MODEL_FILE_ROLE_VOCABULARY;

const embedding: CatalogEntry[] = [
  {
    id: 'all-minilm-l6-v2', name: 'All MiniLM L6 v2', meta: 'Embedding · ONNX · 23 MB',
    modality: 'embedding', loadable: true, category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    framework: ONNX, format: ONNX_FMT,
    downloadUrl: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx',
    downloadSizeBytes: 25_500_000, memoryRequiredBytes: 60_000_000,
    files: [
      { url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx', filename: 'model.onnx', role: PRIMARY, sizeBytes: 22_700_000 },
      { url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt', filename: 'vocab.txt', role: VOCAB, sizeBytes: 232_000 },
    ],
  },
];

export const catalog: Record<Modality, CatalogEntry[]> = {
  llm,
  vlm: vision,
  stt: speech.filter((e) => e.modality === 'stt'),
  tts: speech.filter((e) => e.modality === 'tts'),
  vad: speech.filter((e) => e.modality === 'vad'),
  embedding,
};

export const loadableEntries: CatalogEntry[] = [...llm, ...vision, ...embedding, ...speech].filter((e) => e.loadable);

export function displayItems(modality: Modality): ModelItem[] {
  return catalog[modality].map((e) => ({ id: e.id, name: e.name, meta: e.meta, state: 'available' }));
}
