/**
 * Supported NPU chipsets for on-device Genie model inference.
 *
 * Each chip has an `identifier` used to construct dynamic download URLs
 * for chipset-specific NPU model binaries.
 *
 * @example
 * ```typescript
 * const chip = await RunAnywhere.getChip();
 * if (chip) {
 *   const url = getNPUDownloadUrl(chip, 'qwen');
 *   // → https://huggingface.co/Void2377/npu-models/resolve/main/qwen-gen1.zip?download=true
 * }
 * ```
 */

export interface NPUChip {
  identifier: string;
  displayName: string;
  socModel: string;
}

/** Base URL for NPU model downloads on HuggingFace. */
export const NPU_BASE_URL =
  'https://huggingface.co/Void2377/npu-models/resolve/main/';

/** All supported NPU chipsets. */
export const NPU_CHIPS: readonly NPUChip[] = [
  {
    identifier: 'gen1',
    displayName: 'Snapdragon 8 Elite',
    socModel: 'SM8750',
  },
  {
    identifier: 'gen2',
    displayName: 'Snapdragon 8 Elite Gen 5',
    socModel: 'SM8850',
  },
] as const;

/**
 * Build a HuggingFace download URL for a chip.
 * @param chip - The detected NPU chip
 * @param modelName - Model prefix (e.g. "qwen") → produces "qwen-gen1.zip"
 */
export function getNPUDownloadUrl(chip: NPUChip, modelName: string): string {
  return `${NPU_BASE_URL}${modelName}-${chip.identifier}.zip?download=true`;
}

/**
 * Match an NPU chip from a SoC model string (e.g. "SM8750").
 * Returns undefined if the SoC is not a supported NPU chipset.
 */
export function npuChipFromSocModel(socModel: string): NPUChip | undefined {
  const upper = socModel.toUpperCase();
  return NPU_CHIPS.find((chip) => upper.includes(chip.socModel));
}
