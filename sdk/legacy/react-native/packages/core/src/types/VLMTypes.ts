/**
 * VLMTypes.ts
 * Type definitions for Vision Language Model (VLM) functionality.
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VLM/VLMTypes.swift
 */

/** VLM image format enum - matches rac_vlm_image_format_t */
export enum VLMImageFormat {
  FilePath = 0,
  RGBPixels = 1,
  Base64 = 2,
}

/** VLM image input - discriminated union matching Swift VLMImage.Format */
export type VLMImage =
  | { format: VLMImageFormat.FilePath; filePath: string }
  | { format: VLMImageFormat.RGBPixels; data: Uint8Array; width: number; height: number }
  | { format: VLMImageFormat.Base64; base64: string };

/** VLM generation options */
export interface VLMGenerationOptions {
  maxTokens?: number;       // default 2048
  temperature?: number;     // default 0.7
  topP?: number;           // default 0.9
}

/** VLM generation result - matches Swift VLMResult */
export interface VLMResult {
  text: string;
  promptTokens: number;
  completionTokens: number;
  totalTimeMs: number;
  tokensPerSecond: number;
}

/** VLM streaming result - matches Swift VLMStreamingResult */
export interface VLMStreamingResult {
  stream: AsyncIterable<string>;
  result: Promise<VLMResult>;
  cancel: () => void;
}

/** VLM error codes - matches Swift SDKError.VLMErrorCode */
export enum VLMErrorCode {
  NotInitialized = 1,
  ModelLoadFailed = 2,
  ProcessingFailed = 3,
  InvalidImage = 4,
  Cancelled = 5,
}
