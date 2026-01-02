/**
 * VLMModels.ts
 *
 * Input/Output models for VLM component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/VLM/VLMComponent.swift
 */

import type { ComponentInput, ComponentOutput } from '../../Core/Components/BaseComponent';

/**
 * Image format
 */
export enum ImageFormat {
  JPEG = 'jpeg',
  PNG = 'png',
  HEIC = 'heic',
  WEBP = 'webp',
}

/**
 * Options for VLM processing
 */
export interface VLMOptions {
  readonly imageSize: number;
  readonly maxTokens: number;
  readonly temperature: number;
  readonly topP: number | null;
}

/**
 * Input for Vision Language Model (conforms to ComponentInput protocol)
 */
export interface VLMInput extends ComponentInput {
  /** Image data to process */
  readonly image: Buffer | Uint8Array;
  /** Text prompt or question about the image */
  readonly prompt: string;
  /** Image format */
  readonly imageFormat: ImageFormat;
  /** Optional processing options */
  readonly options: VLMOptions | null;
}

/**
 * Output from Vision Language Model (conforms to ComponentOutput protocol)
 */
export interface VLMOutput extends ComponentOutput {
  /** Generated text response */
  readonly text: string;
  /** Detected objects in the image */
  readonly detectedObjects: DetectedObject[] | null;
  /** Regions of interest */
  readonly regions: ImageRegion[] | null;
  /** Overall confidence score */
  readonly confidence: number;
  /** Processing metadata */
  readonly metadata: VLMMetadata;
}

/**
 * VLM processing metadata
 */
export interface VLMMetadata {
  readonly modelId: string;
  readonly processingTime: number; // seconds
  readonly imageSize: { width: number; height: number };
  readonly tokenCount: number;
}

/**
 * Detected object in image
 */
export interface DetectedObject {
  readonly label: string;
  readonly confidence: number;
  readonly boundingBox: BoundingBox;
}

/**
 * Image region of interest
 */
export interface ImageRegion {
  readonly id: string;
  readonly description: string;
  readonly boundingBox: BoundingBox;
  readonly importance: number;
}

/**
 * Bounding box for object detection
 */
export interface BoundingBox {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}
