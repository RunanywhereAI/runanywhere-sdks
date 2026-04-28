/**
 * helpers/diffusion — ergonomic helpers for proto-encoded Diffusion types.
 */

import {
  DiffusionConfiguration,
  DiffusionGenerationOptions,
  DiffusionMode,
  DiffusionScheduler,
  DiffusionModelVariant,
} from '@runanywhere/proto-ts/diffusion_options';

export {
  DiffusionConfiguration,
  DiffusionGenerationOptions,
  type DiffusionProgress,
  type DiffusionResult,
  type DiffusionCapabilities,
  type DiffusionTokenizerSource,
  DiffusionMode,
  DiffusionScheduler,
  DiffusionModelVariant,
  DiffusionTokenizerSourceKind,
} from '@runanywhere/proto-ts/diffusion_options';

/** Default `DiffusionConfiguration`. */
export function defaultDiffusionConfig(
  variant: DiffusionModelVariant = DiffusionModelVariant.DIFFUSION_MODEL_VARIANT_SD_1_5,
): DiffusionConfiguration {
  return DiffusionConfiguration.create({
    modelVariant: variant,
    enableSafetyChecker: true,
    maxMemoryMb: 0,
  });
}

/** Default `DiffusionGenerationOptions`. */
export function defaultDiffusionOptions(prompt = ''): DiffusionGenerationOptions {
  return DiffusionGenerationOptions.create({
    prompt,
    negativePrompt: '',
    width: 0,
    height: 0,
    numInferenceSteps: 0,
    guidanceScale: 7.5,
    seed: -1,
    scheduler: DiffusionScheduler.DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS,
    mode: DiffusionMode.DIFFUSION_MODE_TEXT_TO_IMAGE,
  });
}

/** True when the configuration is plausibly runnable. */
export function isDiffusionConfigValid(config: DiffusionConfiguration): boolean {
  return config.modelVariant !== DiffusionModelVariant.DIFFUSION_MODEL_VARIANT_UNSPECIFIED;
}
