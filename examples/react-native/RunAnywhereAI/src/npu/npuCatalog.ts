/**
 * NPU (QHexRT) model catalog — Google-Drive-hosted ZIP bundles.
 *
 * Each model is a .zip archive on Google Drive. The Models screen registers it
 * as a ZIP archive (DIRECTORY_BASED) and the SDK downloads + extracts it into
 * the standard model dir, then loads it like any other model.
 *
 * To wire a model: paste its Google Drive FILE ID into `driveId` (the long id
 * from the share link `https://drive.google.com/file/d/<FILE_ID>/view`). An
 * empty `driveId` renders the row as "link pending" with Download disabled.
 */
export type NpuModality = 'llm' | 'vlm';

export interface NpuModel {
  id: string;
  name: string;
  /** Short spec line: modality · params · target arch. */
  detail: string;
  modality: NpuModality;
  /** Google Drive file id of the .zip bundle; '' until the link is provided. */
  driveId: string;
  /** Optional size hint in bytes (for display only). */
  sizeBytes?: number;
}

export const NPU_MODELS: NpuModel[] = [
  {
    id: 'llama3_2_1b_v79',
    name: 'Llama 3.2 1B (HNPU)',
    detail: 'LLM · 1B · Hexagon v79',
    modality: 'llm',
    driveId: '1UeEE08KpZU-rFSwf_FRnu1z2KRwImdX5',
  },
  {
    id: 'llama3_2_1b_v81',
    name: 'Llama 3.2 1B (HNPU)',
    detail: 'LLM · 1B · Hexagon v81',
    modality: 'llm',
    driveId: '1mbshG-jO684dCEUjKKcJ7AUJYRU7_oWX',
  },
  {
    id: 'qwen3_vl_v79',
    name: 'Qwen3-VL (HNPU)',
    detail: 'VLM · Hexagon v79',
    modality: 'vlm',
    driveId: '1Uj1yLliJCJVYuJV0gF_i4Sc_XhBMx1bA',
  },
];

/**
 * Direct-download URL for a Google Drive file id. Uses the usercontent host with
 * `confirm=t` so large files skip the virus-scan HTML interstitial and stream
 * the bytes.
 */
export function driveZipUrl(driveId: string): string {
  return `https://drive.usercontent.google.com/download?id=${driveId}&export=download&confirm=t`;
}

/** Human-readable size, e.g. "1.4 GB". */
export function formatBytes(bytes: number): string {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)} GB`;
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(0)} MB`;
  return `${bytes} B`;
}
