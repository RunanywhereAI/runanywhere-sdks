/**
 * VLMComponent.ts
 *
 * Vision Language Model component following the clean architecture
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/VLM/VLMComponent.swift
 */

import { BaseComponent } from '../../Core/Components/BaseComponent';
import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import { ModuleRegistry } from '../../Core/ModuleRegistry';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';
import type { VLMConfiguration } from './VLMConfiguration';
import { ImageFormat, type VLMInput, type VLMOutput, type VLMOptions, type DetectedObject } from './VLMModels';
import type { VLMService } from '../../Core/Protocols/VLM/VLMService';
import type { VLMServiceProvider } from '../../Core/Protocols/VLM/VLMServiceProvider';
import type { VLMResult } from '../../Core/Models/VLM/VLMResult';
import { AnyServiceWrapper } from '../../Core/Components/BaseComponent';

/**
 * Unavailable VLM Service (placeholder)
 */
class UnavailableVLMService implements VLMService {
  async initialize(_modelPath?: string | null): Promise<void> {
    throw new SDKError(SDKErrorCode.ComponentNotInitialized, 'VLM service not available');
  }

  async process(
    _imageData: string | ArrayBuffer,
    _textPrompt: string,
    _options?: {
      maxTokens?: number;
      temperature?: number;
    }
  ): Promise<VLMResult> {
    throw new SDKError(SDKErrorCode.ComponentNotInitialized, 'VLM service not available');
  }

  get isReady(): boolean {
    return false;
  }

  get currentModel(): string | null {
    return null;
  }

  async cleanup(): Promise<void> {}
}

/**
 * VLM Service Wrapper
 */
export class VLMServiceWrapper extends AnyServiceWrapper<VLMService> {
  constructor(service: VLMService | null = null) {
    super(service);
  }
}

/**
 * Vision Language Model component
 */
export class VLMComponent extends BaseComponent<VLMServiceWrapper> {
  // MARK: - Properties

  public static override componentType: SDKComponent = SDKComponent.VLM;

  private readonly vlmConfiguration: VLMConfiguration;
  private isModelLoaded = false;
  private modelPath: string | null = null;

  // MARK: - Initialization

  constructor(configuration: VLMConfiguration) {
    super(configuration);
    this.vlmConfiguration = configuration;
  }

  // MARK: - Service Creation

  protected override async createService(): Promise<VLMServiceWrapper> {
    // Try to get a registered VLM provider from central registry
    const provider = ModuleRegistry.shared.vlmProvider();

    if (!provider) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'VLM service requires an external implementation. Please add a vision model provider as a dependency.'
      );
    }

    try {
      // Create service through provider
      const vlmService = await provider.createVLMService(this.vlmConfiguration);

      // Initialize the service
      await vlmService.initialize(this.vlmConfiguration.modelId ?? undefined);
      this.isModelLoaded = true;

      // Wrap and return the service
      return new VLMServiceWrapper(vlmService);
    } catch (error) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        `Failed to create VLM service: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  protected override async performCleanup(): Promise<void> {
    if (this.service?.wrappedService) {
      await this.service.wrappedService.cleanup();
    }
    this.isModelLoaded = false;
    this.modelPath = null;
  }

  // MARK: - Public API

  /**
   * Analyze an image with a text prompt
   */
  public async analyze(
    image: Buffer | Uint8Array,
    prompt: string,
    format: ImageFormat = ImageFormat.JPEG
  ): Promise<VLMOutput> {
    this.ensureReady();

    const input: VLMInput = {
      image,
      prompt,
      imageFormat: format,
      options: null,
      validate: () => {
        if (!image || image.length === 0) {
          throw new SDKError(SDKErrorCode.ValidationFailed, 'Image data cannot be empty');
        }
        if (!prompt || prompt.trim().length === 0) {
          throw new SDKError(SDKErrorCode.ValidationFailed, 'Prompt cannot be empty');
        }
      },
      timestamp: new Date(),
    };

    return await this.process(input);
  }

  /**
   * Describe an image
   */
  public async describeImage(
    image: Buffer | Uint8Array,
    format: ImageFormat = ImageFormat.JPEG
  ): Promise<VLMOutput> {
    return await this.analyze(image, 'Describe this image in detail', format);
  }

  /**
   * Answer a question about an image
   */
  public async answerQuestion(
    image: Buffer | Uint8Array,
    question: string,
    format: ImageFormat = ImageFormat.JPEG
  ): Promise<VLMOutput> {
    return await this.analyze(image, question, format);
  }

  /**
   * Detect objects in an image
   */
  public async detectObjects(
    image: Buffer | Uint8Array,
    format: ImageFormat = ImageFormat.JPEG
  ): Promise<DetectedObject[]> {
    this.ensureReady();

    const output = await this.analyze(image, 'Detect and list all objects in this image', format);
    return output.detectedObjects ?? [];
  }

  /**
   * Process VLM input
   */
  public async process(input: VLMInput): Promise<VLMOutput> {
    this.ensureReady();

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'VLM service not available');
    }

    // Validate input
    input.validate();

    // Convert image to ArrayBuffer for service
    let imageBuffer: ArrayBuffer;
    if (Buffer.isBuffer(input.image)) {
      // Get the underlying ArrayBuffer, slicing to avoid shared buffer issues
      imageBuffer = input.image.buffer.slice(
        input.image.byteOffset,
        input.image.byteOffset + input.image.byteLength
      ) as ArrayBuffer;
    } else if (input.image instanceof Uint8Array) {
      imageBuffer = input.image.buffer.slice(
        input.image.byteOffset,
        input.image.byteOffset + input.image.byteLength
      ) as ArrayBuffer;
    } else {
      imageBuffer = Buffer.from(input.image).buffer as ArrayBuffer;
    }

    // Track processing time
    const startTime = Date.now();

    // Process image
    const result: VLMResult = await this.service.wrappedService.process(
      imageBuffer,
      input.prompt,
      input.options
        ? {
            maxTokens: input.options.maxTokens,
            temperature: input.options.temperature,
          }
        : undefined
    );

    const processingTime = (Date.now() - startTime) / 1000; // seconds

    // Convert result to output
    return {
      text: result.text ?? '',
      detectedObjects: result.detections?.map((det) => ({
        label: det.label,
        confidence: det.confidence,
        boundingBox: {
          x: det.bbox.x,
          y: det.bbox.y,
          width: det.bbox.width,
          height: det.bbox.height,
        },
      })) ?? null,
      regions: result.regions?.map((reg) => ({
        id: reg.id,
        description: reg.description,
        boundingBox: {
          x: reg.bbox.x,
          y: reg.bbox.y,
          width: reg.bbox.width,
          height: reg.bbox.height,
        },
        importance: reg.importance,
      })) ?? null,
      confidence: result.confidence ?? 1.0,
      metadata: {
        modelId: this.service.wrappedService.currentModel ?? 'unknown',
        processingTime,
        imageSize: { width: this.vlmConfiguration.imageSize, height: this.vlmConfiguration.imageSize },
        tokenCount: 0, // Would be provided by service
      },
      timestamp: new Date(),
    };
  }
}
