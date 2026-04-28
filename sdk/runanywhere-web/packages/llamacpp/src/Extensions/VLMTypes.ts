/**
 * RunAnywhere Web SDK - VLM Types (LlamaCpp Backend).
 *
 * Wave 2: The proto VLM result is intentionally minimal (text + 5 token
 * counters). The llama.cpp WASM backend additionally surfaces image-encoding
 * telemetry and hardware acceleration mode that don't fit in the proto wire
 * shape. This module defines those Web-only ergonomic types and re-exports
 * proto canonical types where they suffice.
 */

import type { HardwareAcceleration } from '@runanywhere/web';

/** Web-only ergonomic VLM image format enum. */
export enum VLMImageFormat {
  FilePath = 0,
  RGBPixels = 1,
  Base64 = 2,
}

/** Web-only image input shape (carries TypedArray + base64 in addition to proto bytes/path). */
export interface VLMImage {
  format: VLMImageFormat;
  filePath?: string;
  pixelData?: Uint8Array;
  base64Data?: string;
  width?: number;
  height?: number;
}

/** Web-only generation options — adds streaming + system prompt + family hint. */
export interface VLMGenerationOptions {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  systemPrompt?: string;
  modelFamily?: number;
  streaming?: boolean;
}

/** Web-only generation result — adds image-encode timing + hardware mode. */
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

/** llama.cpp-specific VLM model architecture families. */
export enum VLMModelFamily {
  Auto = 0,
  Qwen2VL = 1,
  SmolVLM = 2,
  LLaVA = 3,
  Custom = 99,
}
