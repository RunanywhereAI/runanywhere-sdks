/**
 * helpers/lora — ergonomic helpers for proto-encoded LoRA types.
 */

import { LoRAAdapterConfig } from '@runanywhere/proto-ts/lora_options';

export {
  LoRAAdapterConfig,
  type LoRAAdapterInfo,
  type LoraAdapterCatalogEntry,
  type LoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';

/** Default `LoRAAdapterConfig`. */
export function defaultLoRAAdapterConfig(adapterPath = ''): LoRAAdapterConfig {
  return LoRAAdapterConfig.create({
    adapterPath,
    scale: 1.0,
  });
}
