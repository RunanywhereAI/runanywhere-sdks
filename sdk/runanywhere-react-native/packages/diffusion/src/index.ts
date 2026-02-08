/**
 * @runanywhere/diffusion
 *
 * Image generation using Stable Diffusion models. iOS only (CoreML/ANE).
 * On Android, register() returns false and other methods throw.
 */

// Main module
export { Diffusion } from './Diffusion';
export { DiffusionProvider } from './DiffusionProvider';

// Types
export type {
  DiffusionTokenizerSource,
  DiffusionModelVariant,
  DiffusionScheduler,
  DiffusionMode,
  DiffusionConfiguration,
  DiffusionGenerationOptions,
  DiffusionProgress,
  DiffusionResult,
  DiffusionModelInfo,
} from './types';

export {
  DiffusionTokenizerSources,
  DiffusionModelVariants,
  DiffusionSchedulers,
  DiffusionModes,
  getTokenizerBaseURL,
  getDefaultResolution,
  getDefaultSteps,
  createTextToImageOptions,
} from './types';

// Native module (for advanced use cases)
export {
  requireNativeDiffusionModule,
  isNativeDiffusionModuleAvailable,
} from './native';
