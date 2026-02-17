/**
 * RunAnywhere Web SDK - VLM Types
 *
 * Type definitions for the Vision Language Model extension.
 * Extracted from RunAnywhere+VLM.ts for clean separation of concerns.
 */

import { HardwareAcceleration } from '@runanywhere/web';

// ---------------------------------------------------------------------------
// VLM Types
// ---------------------------------------------------------------------------

export enum VLMImageFormat {
  FilePath = 0,
  RGBPixels = 1,
  Base64 = 2,
}

export enum VLMModelFamily {
  Auto = 0,
  Qwen2VL = 1,
  SmolVLM = 2,
  LLaVA = 3,
  Custom = 99,
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
  modelFamily?: VLMModelFamily;
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
