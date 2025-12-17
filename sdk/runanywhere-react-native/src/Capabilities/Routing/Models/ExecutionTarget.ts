/**
 * ExecutionTarget.ts
 *
 * Execution target for model inference
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Routing/Models/ExecutionTarget.swift
 */

/**
 * Execution target for model inference
 */
export enum ExecutionTarget {
  /** Execute on device */
  OnDevice = 'onDevice',

  /** Execute in the cloud */
  Cloud = 'cloud',

  /** Hybrid execution (partial on-device, partial cloud) */
  Hybrid = 'hybrid',
}
