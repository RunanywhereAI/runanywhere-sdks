/**
 * RunAnywhere Web SDK - VLM Types (Backend-Agnostic)
 *
 * Generic type definitions for Vision Language Model inference.
 * Backend-specific model family enums live in the respective backend packages.
 */

import type { HardwareAcceleration } from './enums';

export enum VLMImageFormat {
  FilePath = 0,
  RGBPixels = 1,
  Base64 = 2,
}

export interface VLMImage {
  format: VLMImageFormat;
  /** File path in WASM virtual FS (for FilePath format) */
  filePath?: string;
  /** Raw RGB pixel data (for RGBPixels format) */
  pixelData?: Uint8Array;
  /** Base64-encoded image (for Base64 format) */
  base64Data?: string;
  width?: number;
  height?: number;
}

export interface VLMGenerationOptions {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  systemPrompt?: string;
  /** Backend-specific model family identifier. */
  modelFamily?: number;
  streaming?: boolean;
}

export interface VLMGenerationResult {
  text: string;
  promptTokens: number;
  imageTokens: number;
  completionTokens: number;
  totalTokens: number;
  timeToFirstTokenMs: number;
  imageEncodeTimeMs: number;
  totalTimeMs: number;
  tokensPerSecond: number;
  hardwareUsed: HardwareAcceleration;
}

export interface VLMStreamingResult {
  result: Promise<VLMGenerationResult>;
  tokens: AsyncIterable<string>;
  cancel: () => void;
}
