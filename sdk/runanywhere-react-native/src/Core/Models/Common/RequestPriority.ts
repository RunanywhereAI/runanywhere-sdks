/**
 * RequestPriority.ts
 *
 * Request priority
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Models/Common/RequestPriority.swift
 */

/**
 * Request priority (internal)
 */
export enum RequestPriority {
  Low = 0,
  Normal = 1,
  High = 2,
  Critical = 3,
}

/**
 * Compare two request priorities
 */
export function compareRequestPriority(
  lhs: RequestPriority,
  rhs: RequestPriority
): number {
  return lhs - rhs;
}

