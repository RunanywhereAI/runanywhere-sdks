/** RunAnywhere Web SDK - Diffusion Types */

import type {
  DiffusionGenerationOptions as ProtoDiffusionGenerationOptions,
  DiffusionResult,
} from '@runanywhere/proto-ts/diffusion_options';
export {
  DiffusionScheduler,
  DiffusionModelVariant,
  DiffusionMode,
} from '@runanywhere/proto-ts/diffusion_options';

export type DiffusionGenerationOptions =
  Pick<ProtoDiffusionGenerationOptions, 'prompt'> &
  Partial<Omit<ProtoDiffusionGenerationOptions, 'prompt'>>;

export type DiffusionGenerationResult = DiffusionResult;

export type DiffusionProgressCallback = (step: number, totalSteps: number, progress: number) => void;
