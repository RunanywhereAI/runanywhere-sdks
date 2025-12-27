/**
 * ModelFormat.ts
 *
 * Model formats supported
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Models/Framework/ModelFormat.swift
 */

/**
 * Model formats supported
 */
export enum ModelFormat {
  MLModel = 'mlmodel',
  MLPackage = 'mlpackage',
  TFLite = 'tflite',
  ONNX = 'onnx',
  ORT = 'ort',
  SafeTensors = 'safetensors',
  GGUF = 'gguf',
  GGML = 'ggml',
  MLX = 'mlx',
  PTE = 'pte',
  Bin = 'bin',
  Weights = 'weights',
  Checkpoint = 'checkpoint',
  Unknown = 'unknown',
}

/**
 * Detect model format from URL
 */
export function detectFormatFromURL(url: string): ModelFormat | null {
  const path = url.toLowerCase();

  if (path.includes('.gguf')) return ModelFormat.GGUF;
  if (path.includes('.ggml')) return ModelFormat.GGML;
  if (path.includes('.mlmodel')) return ModelFormat.MLModel;
  if (path.includes('.mlpackage')) return ModelFormat.MLPackage;
  if (path.includes('.onnx')) return ModelFormat.ONNX;
  if (path.includes('.tflite')) return ModelFormat.TFLite;
  if (path.includes('.mlx')) return ModelFormat.MLX;
  if (path.includes('.bin')) return ModelFormat.Bin;
  if (path.includes('.safetensors')) return ModelFormat.SafeTensors;
  if (path.includes('.pte')) return ModelFormat.PTE;
  if (path.includes('.weights')) return ModelFormat.Weights;
  if (path.includes('.checkpoint') || path.includes('.ckpt')) return ModelFormat.Checkpoint;

  // Check for common model hosting patterns
  if (url.includes('huggingface.co')) {
    if (path.includes('gguf')) return ModelFormat.GGUF;
    if (path.includes('onnx')) return ModelFormat.ONNX;
  }

  return ModelFormat.Unknown;
}
