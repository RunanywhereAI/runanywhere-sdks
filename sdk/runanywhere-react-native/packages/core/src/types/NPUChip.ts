/**
 * Supported NPU chipsets for on-device Genie model inference.
 *
 * Each chip has an `identifier` used in model IDs and an `npuSuffix` used
 * to construct download URLs from the HuggingFace model repository.
 *
 * @example
 * ```typescript
 * const chip = await RunAnywhere.getChip();
 * if (chip) {
 *   const url = getNPUDownloadUrl(chip, 'qwen3-4b');
 *   // → https://huggingface.co/runanywhere/genie-npu-models/resolve/main/qwen3-4b-genie-w4a16-8elite-gen5.tar.gz
 * }
 * ```
 */

export interface NPUChip {
  identifier: string;
  displayName: string;
  socModel: string;
  npuSuffix: string;
}

/** Base URL for NPU model downloads on HuggingFace. */
export const NPU_BASE_URL =
  'https://huggingface.co/runanywhere/genie-npu-models/resolve/main/';

/** All supported NPU chipsets. */
export const NPU_CHIPS: readonly NPUChip[] = [
  {
    identifier: '8elite',
    displayName: 'Snapdragon 8 Elite',
    socModel: 'SM8750',
    npuSuffix: '8elite',
  },
  {
    identifier: '8elite-gen5',
    displayName: 'Snapdragon 8 Elite Gen 5',
    socModel: 'SM8850',
    npuSuffix: '8elite-gen5',
  },
] as const;

/**
 * Build a HuggingFace download URL for a chip.
 * @param chip - The detected NPU chip
 * @param modelSlug - Model slug (e.g. "qwen3-4b") → produces
 *   "qwen3-4b-genie-w4a16-8elite-gen5.tar.gz"
 * @param quant - Quantization format (e.g. "w4a16", "w8a16"). Defaults to "w4a16".
 */
export function getNPUDownloadUrl(chip: NPUChip, modelSlug: string, quant = 'w4a16'): string {
  return `${NPU_BASE_URL}${modelSlug}-genie-${quant}-${chip.npuSuffix}.tar.gz`;
}

/**
 * Match an NPU chip from a SoC model string (e.g. "SM8750").
 * Returns undefined if the SoC is not a supported NPU chipset.
 */
export function npuChipFromSocModel(socModel: string): NPUChip | undefined {
  const upper = socModel.toUpperCase();
  return NPU_CHIPS.find((chip) => upper.includes(chip.socModel));
}
