/**
 * LoRATypes.ts
 *
 * Type definitions for LoRA adapter management.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/LLMTypes.swift
 * (LoRAAdapterConfig / LoRAAdapterInfo / LoraAdapterCatalogEntry / LoraCompatibilityResult)
 */

/**
 * Configuration for loading a LoRA adapter.
 *
 * Matches Swift: `LoRAAdapterConfig`
 */
export interface LoRAAdapterConfig {
  /** Path to the LoRA adapter GGUF file */
  path: string;

  /** Scale factor (0.0 to 1.0+, default 1.0). Higher = stronger adapter effect. */
  scale?: number;
}

/**
 * Info about a loaded LoRA adapter (read-only).
 *
 * Matches Swift: `LoRAAdapterInfo`
 */
export interface LoRAAdapterInfo {
  /** Path used when loading the adapter */
  path: string;

  /** Active scale factor */
  scale: number;

  /** Whether the adapter is currently applied to the context */
  applied: boolean;
}

/**
 * Catalog entry for a LoRA adapter registered with the SDK.
 * Register adapters at app startup via RunAnywhere.registerLoraAdapter().
 *
 * Matches Swift: `LoraAdapterCatalogEntry`
 */
export interface LoraAdapterCatalogEntry {
  /** Unique adapter identifier */
  id: string;

  /** Human-readable display name */
  name: string;

  /** Short description of what this adapter does */
  description: string;

  /** Direct download URL for the GGUF file */
  downloadURL: string;

  /** Filename to save as on disk */
  filename: string;

  /** Model IDs this adapter is compatible with */
  compatibleModelIds: string[];

  /** File size in bytes (0 if unknown) */
  fileSize?: number;

  /** Recommended LoRA scale (e.g. 0.3 for F16 adapters on quantized bases) */
  defaultScale?: number;
}

/**
 * Result of a LoRA compatibility pre-check.
 *
 * Matches Swift: `LoraCompatibilityResult`
 */
export interface LoraCompatibilityResult {
  /** Whether the adapter is compatible with the currently loaded model */
  isCompatible: boolean;

  /** Error message if not compatible */
  error?: string;
}
