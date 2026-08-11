/**
 * RunAnywhere+VisionLanguage.ts
 *
 * Public VLM namespace matching Swift's RunAnywhere+VisionLanguage. The Web
 * implementation delegates to a backend-installed provider so app code never
 * imports backend worker bridges directly.
 *
 * `VLMGenerationOptions` was deleted outright from idl/vlm_options.proto:
 * `VLMGenerationRequest.options` is now a plain `LLMGenerationOptions` (same
 * names/defaults/validation as the text API) and `VLMGenerationRequest.vision`
 * carries only the four genuinely vision-specific knobs
 * (`VLMVisionOptions`: modelFamily, customChatTemplate, imageMarkerOverride,
 * maxImageTokens). `prompt` lives directly on the request, not inside options.
 */

import type {
  VLMImage,
  VLMResult,
  VLMStreamEvent,
  VLMVisionOptions,
} from '@runanywhere/proto-ts/vlm_options';
import type { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';
import { lLMGenerationOptionsDefaults } from '@runanywhere/proto-ts/convenience/llm_options_convenience';
import {
  ModelCategory,
  type CurrentModelResult,
} from '@runanywhere/proto-ts/model_types';
import { SDKException } from '../../Foundation/SDKException.js';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle.js';

export interface VisionLanguageProvider {
  readonly isInitialized: boolean;
  readonly isModelLoaded: boolean;
  loadCurrentModel?(currentModel: CurrentModelResult): Promise<void>;
  unloadModel?(): Promise<void>;
  processImage(
    image: VLMImage,
    prompt: string,
    options: Partial<LLMGenerationOptions>,
    vision?: VLMVisionOptions,
  ): Promise<VLMResult>;
  /** Typed stream: STARTED → TOKEN* → exactly one terminal COMPLETED/ERROR
   *  (COMPLETED carries the full VLMResult). Canonical cross-SDK shape. */
  processImageStream?(
    image: VLMImage,
    prompt: string,
    options: Partial<LLMGenerationOptions>,
    vision?: VLMVisionOptions,
  ): Promise<AsyncIterable<VLMStreamEvent>>;
  cancelVLMGeneration(): Promise<void> | void;
}

let provider: VisionLanguageProvider | null = null;

export function setVisionLanguageProvider(next: VisionLanguageProvider | null): void {
  provider = next;
}

function requireProvider(feature: string): VisionLanguageProvider {
  if (provider) return provider;
  throw SDKException.backendNotAvailable(
    feature,
    'No Web vision-language provider is registered. Call LlamaCPP.register() first.',
  );
}

/**
 * Fill gaps from the IDL text-generation defaults -- VLM options are the
 * same `LLMGenerationOptions` shape and defaults as the text API now.
 */
function normalizeVLMGenerationOptions(
  options?: Partial<LLMGenerationOptions>,
): LLMGenerationOptions {
  const defaults = lLMGenerationOptionsDefaults();
  return {
    ...defaults,
    ...options,
  };
}

export const VisionLanguage = {
  get isInitialized(): boolean {
    return provider?.isInitialized ?? false;
  },

  get isModelLoaded(): boolean {
    return provider?.isModelLoaded ?? false;
  },

  async loadCurrentModel(): Promise<void> {
    // Swift parity (RunAnywhere+VisionLanguage.swift): VLM accepts both
    // `.multimodal` and `.vision` — try `.multimodal` first (the canonical
    // category), fall back to `.vision`. No any-category fallback: a loaded
    // LLM/STT model must not satisfy the VLM guard.
    const current =
      WebModelLifecycle.currentModel({
        category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        includeModelMetadata: true,
      }) ??
      WebModelLifecycle.currentModel({
        category: ModelCategory.MODEL_CATEGORY_VISION,
        includeModelMetadata: true,
      });

    if (!current?.modelId) {
      // Swift parity: RunAnywhere+VisionLanguage.swift:40 throws `.notInitialized` ("VLM model not loaded").
      throw SDKException.notInitialized(
        'No VLM model is loaded. Call RunAnywhere.loadModel(...) with a multimodal model before RunAnywhere.processImage().',
      );
    }

    const active = requireProvider('visionLanguage.loadCurrentModel');
    if (!active.loadCurrentModel) {
      throw SDKException.backendNotAvailable(
        'visionLanguage.loadCurrentModel',
        'The active Web vision-language provider cannot load C++ lifecycle resolved artifacts.',
      );
    }
    await active.loadCurrentModel(current);
  },

  async unloadModel(): Promise<void> {
    const active = requireProvider('visionLanguage.unloadModel');
    if (!active.unloadModel) return;
    await active.unloadModel();
  },

  processImage(
    image: VLMImage,
    prompt: string,
    options?: Partial<LLMGenerationOptions>,
    vision?: VLMVisionOptions,
  ): Promise<VLMResult> {
    return requireProvider('visionLanguage.processImage').processImage(
      image,
      prompt,
      normalizeVLMGenerationOptions(options),
      vision,
    );
  },

  /** Typed VLM event stream. */
  processImageStream(
    image: VLMImage,
    prompt: string,
    options?: Partial<LLMGenerationOptions>,
    vision?: VLMVisionOptions,
  ): Promise<AsyncIterable<VLMStreamEvent>> {
    const active = requireProvider('visionLanguage.processImageStream');
    if (!active.processImageStream) {
      throw SDKException.backendNotAvailable(
        'visionLanguage.processImageStream',
        'The active Web vision-language provider does not expose streaming.',
      );
    }
    return active.processImageStream(
      image,
      prompt,
      normalizeVLMGenerationOptions(options),
      vision,
    );
  },

  async cancelVLMGeneration(): Promise<void> {
    await requireProvider('visionLanguage.cancelVLMGeneration').cancelVLMGeneration();
  },
};

export type VisionLanguageCapability = typeof VisionLanguage;
