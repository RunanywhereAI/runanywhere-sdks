/**
 * StructuredOutputValidation.ts
 *
 * Validation types and utilities for structured output
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/LLM/StructuredOutput/StructuredOutputHandler.swift
 */

/**
 * Structured output validation result
 * Matches iOS StructuredOutputValidation
 */
export interface StructuredOutputValidation {
  readonly isValid: boolean;
  readonly containsJSON: boolean;
  readonly error: string | null;
}

/**
 * Structured output errors
 * Matches iOS StructuredOutputError enum
 */
export enum StructuredOutputErrorType {
  InvalidJSON = 'invalidJSON',
  ValidationFailed = 'validationFailed',
  ExtractionFailed = 'extractionFailed',
  UnsupportedType = 'unsupportedType',
}

/**
 * Custom error class for structured output errors
 */
export class StructuredOutputError extends Error {
  constructor(
    message: string,
    public readonly type: StructuredOutputErrorType
  ) {
    super(message);
    this.name = 'StructuredOutputError';
  }

  static invalidJSON(detail: string): StructuredOutputError {
    return new StructuredOutputError(
      `Invalid JSON: ${detail}`,
      StructuredOutputErrorType.InvalidJSON
    );
  }

  static validationFailed(detail: string): StructuredOutputError {
    return new StructuredOutputError(
      `Validation failed: ${detail}`,
      StructuredOutputErrorType.ValidationFailed
    );
  }

  static extractionFailed(detail: string): StructuredOutputError {
    return new StructuredOutputError(
      `Failed to extract structured output: ${detail}`,
      StructuredOutputErrorType.ExtractionFailed
    );
  }

  static unsupportedType(type: string): StructuredOutputError {
    return new StructuredOutputError(
      `Unsupported type for structured output: ${type}`,
      StructuredOutputErrorType.UnsupportedType
    );
  }
}

/**
 * Creates a validation result
 */
export function createValidationResult(
  isValid: boolean,
  containsJSON: boolean,
  error: string | null = null
): StructuredOutputValidation {
  return {
    isValid,
    containsJSON,
    error,
  };
}
