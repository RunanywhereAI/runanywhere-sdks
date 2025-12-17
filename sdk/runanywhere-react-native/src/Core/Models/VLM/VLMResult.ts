/**
 * VLMResult.ts
 *
 * Result from VLM processing
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/VLM/VLMComponent.swift
 */

export interface VLMResult {
  text: string;
  confidence?: number | null;
  detections?: VLMDetection[] | null;
  regions?: VLMRegion[] | null;
}

export interface VLMDetection {
  label: string;
  confidence: number;
  bbox: VLMBoundingBox;
}

export interface VLMRegion {
  id: string;
  description: string;
  bbox: VLMBoundingBox;
  importance: number;
}

export interface VLMBoundingBox {
  x: number;
  y: number;
  width: number;
  height: number;
}
