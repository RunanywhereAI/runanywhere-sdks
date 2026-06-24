/**
 * Curated NPU (QHexRT) model catalog.
 *
 * Source of truth: the npu-tagged repo `runanywhere/genie-npu-models` on
 * Hugging Face (tags: qualcomm, genie, npu, snapdragon). These are Snapdragon
 * Hexagon NPU LLM bundles (w4a16/w8a16, Snapdragon 8 Elite / 8 Elite Gen5).
 * The NPU Models screen lists exactly these — not the generic SDK registry.
 */
const HF = 'https://huggingface.co/runanywhere/genie-npu-models/resolve/main';

export interface NpuModel {
  id: string;
  name: string;
  /** Short spec line: params · quant · target SoC. */
  detail: string;
  sizeBytes: number;
  url: string;
}

export const NPU_MODELS: NpuModel[] = [
  {
    id: 'llama3.2-1b-instruct-genie-w4a16-8elite-gen5',
    name: 'Llama 3.2 1B Instruct',
    detail: '1B · w4a16 · 8 Elite Gen5',
    sizeBytes: 1373507483,
    url: `${HF}/llama3.2-1b-instruct-genie-w4a16-8elite-gen5.tar.gz`,
  },
  {
    id: 'llama3.2-1b-instruct-genie-w4a16-8elite',
    name: 'Llama 3.2 1B Instruct',
    detail: '1B · w4a16 · 8 Elite',
    sizeBytes: 1369601674,
    url: `${HF}/llama3.2-1b-instruct-genie-w4a16-8elite.tar.gz`,
  },
  {
    id: 'qwen3-4b-genie-w4a16-8elite-gen5',
    name: 'Qwen3 4B',
    detail: '4B · w4a16 · 8 Elite Gen5',
    sizeBytes: 2538981899,
    url: `${HF}/qwen3-4b-genie-w4a16-8elite-gen5.tar.gz`,
  },
  {
    id: 'qwen2.5-7b-instruct-genie-w8a16-8elite',
    name: 'Qwen2.5 7B Instruct',
    detail: '7B · w8a16 · 8 Elite',
    sizeBytes: 4184248574,
    url: `${HF}/qwen2.5-7b-instruct-genie-w8a16-8elite.tar.gz`,
  },
  {
    id: 'sea-lion3.5-8b-instruct-genie-w4a16-8elite-gen5',
    name: 'SEA-LION 3.5 8B Instruct',
    detail: '8B · w4a16 · 8 Elite Gen5',
    sizeBytes: 4724747321,
    url: `${HF}/sea-lion3.5-8b-instruct-genie-w4a16-8elite-gen5.tar.gz`,
  },
  {
    id: 'sea-lion3.5-8b-instruct-genie-w4a16-8elite',
    name: 'SEA-LION 3.5 8B Instruct',
    detail: '8B · w4a16 · 8 Elite',
    sizeBytes: 4722492367,
    url: `${HF}/sea-lion3.5-8b-instruct-genie-w4a16-8elite.tar.gz`,
  },
];

/** Human-readable size, e.g. "1.4 GB". */
export function formatBytes(bytes: number): string {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)} GB`;
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(0)} MB`;
  return `${bytes} B`;
}
