/**
 * VLMConfiguration.ts
 *
 * Configuration for VLM component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/VLM/VLMComponent.swift
 */

import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import type { ComponentConfiguration } from '../../Core/Components/BaseComponent';
import type { ComponentInitParameters } from '../../Core/Models/Common/ComponentInitParameters';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';

/**
 * Image preprocessing options
 */
export enum ImagePreprocessing {
  None = 'none',
  Normalize = 'normalize',
  CenterCrop = 'center_crop',
  Resize = 'resize',
}

/**
 * Configuration for VLM component (conforms to ComponentConfiguration and ComponentInitParameters protocols)
 */
export interface VLMConfiguration extends ComponentConfiguration, ComponentInitParameters {
  readonly componentType: SDKComponent;
  readonly modelId: string | null;
  readonly imageSize: number; // Square image size (e.g., 224, 384, 512)
  readonly maxImageTokens: number;
  readonly contextLength: number;
  readonly useGPUIfAvailable: boolean;
  readonly imagePreprocessing: ImagePreprocessing;
}

/**
 * Create VLM configuration
 */
export class VLMConfigurationImpl implements VLMConfiguration {
  public readonly componentType: SDKComponent = SDKComponent.VLM;
  public readonly modelId: string | null;
  public readonly imageSize: number;
  public readonly maxImageTokens: number;
  public readonly contextLength: number;
  public readonly useGPUIfAvailable: boolean;
  public readonly imagePreprocessing: ImagePreprocessing;

  constructor(options: {
    modelId?: string | null;
    imageSize?: number;
    maxImageTokens?: number;
    contextLength?: number;
    useGPUIfAvailable?: boolean;
    imagePreprocessing?: ImagePreprocessing;
  } = {}) {
    this.modelId = options.modelId ?? null;
    this.imageSize = options.imageSize ?? 384;
    this.maxImageTokens = options.maxImageTokens ?? 576;
    this.contextLength = options.contextLength ?? 2048;
    this.useGPUIfAvailable = options.useGPUIfAvailable ?? true;
    this.imagePreprocessing = options.imagePreprocessing ?? ImagePreprocessing.Normalize;
  }

  public validate(): void {
    const validImageSizes = [224, 256, 384, 512, 768, 1024];
    if (!validImageSizes.includes(this.imageSize)) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        `Image size must be one of: ${validImageSizes.join(', ')}`
      );
    }
    if (this.maxImageTokens <= 0 || this.maxImageTokens > 2048) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Max image tokens must be between 1 and 2048'
      );
    }
    if (this.contextLength <= 0 || this.contextLength > 32768) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Context length must be between 1 and 32768'
      );
    }
  }
}
