/**
 * QuantizationLevel.ts
 *
 * Quantization level
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Models/Common/QuantizationLevel.swift
 */

/**
 * Quantization level
 */
export enum QuantizationLevel {
  Full = 'fp32',
  F32 = 'f32',
  Half = 'fp16',
  F16 = 'f16',
  Int8 = 'int8',
  Q8V0 = 'q8_0',
  Int4 = 'int4',
  Q4V0 = 'q4_0',
  Q4KS = 'q4_K_S',
  Q4KM = 'q4_K_M',
  Q5V0 = 'q5_0',
  Q5KS = 'q5_K_S',
  Q5KM = 'q5_K_M',
  Q6K = 'q6_K',
  Q3KS = 'q3_K_S',
  Q3KM = 'q3_K_M',
  Q3KL = 'q3_K_L',
  Q2K = 'q2_K',
  Int2 = 'int2',
  Mixed = 'mixed',
}
