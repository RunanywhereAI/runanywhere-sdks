/**
 * ErrorCategory.ts
 *
 * Logical grouping for error filtering and analytics.
 * Matches iOS SDK: Foundation/ErrorTypes/ErrorCategory.swift
 */

import { ErrorCode } from './ErrorCodes';

export enum ErrorCategory {
  /** SDK initialization errors */
  Initialization = 'initialization',
  /** Model loading and validation errors */
  Model = 'model',
  /** LLM/text generation errors */
  Generation = 'generation',
  /** Network and API errors */
  Network = 'network',
  /** File system and disk space errors */
  Storage = 'storage',
  /** Out-of-memory conditions */
  Memory = 'memory',
  /** Device compatibility issues */
  Hardware = 'hardware',
  /** Input validation failures */
  Validation = 'validation',
  /** Auth/API key errors */
  Authentication = 'authentication',
  /** Individual component failures */
  Component = 'component',
  /** Core framework errors */
  Framework = 'framework',
  /** Unclassified errors */
  Unknown = 'unknown',
}

/**
 * All error categories for iteration.
 */
export const allErrorCategories: ErrorCategory[] = Object.values(ErrorCategory);

/**
 * Infer error category from an error code.
 */
export function getCategoryFromCode(code: ErrorCode): ErrorCategory {
  // General errors (1000-1099)
  if (code >= 1000 && code < 1100) {
    if (code === ErrorCode.NotInitialized || code === ErrorCode.AlreadyInitialized) {
      return ErrorCategory.Initialization;
    }
    if (code === ErrorCode.InvalidInput) {
      return ErrorCategory.Validation;
    }
    return ErrorCategory.Framework;
  }

  // Model errors (1100-1199)
  if (code >= 1100 && code < 1200) {
    return ErrorCategory.Model;
  }

  // Network errors (1200-1299)
  if (code >= 1200 && code < 1300) {
    return ErrorCategory.Network;
  }

  // Storage errors (1300-1399)
  if (code >= 1300 && code < 1400) {
    return ErrorCategory.Storage;
  }

  // Hardware errors (1500-1599)
  if (code >= 1500 && code < 1600) {
    return ErrorCategory.Hardware;
  }

  // Authentication errors (1600-1699)
  if (code >= 1600 && code < 1700) {
    return ErrorCategory.Authentication;
  }

  // Generation errors (1700-1799)
  if (code >= 1700 && code < 1800) {
    return ErrorCategory.Generation;
  }

  return ErrorCategory.Unknown;
}

/**
 * Infer error category from an error object by inspecting its properties.
 * Used for automatic categorization of unknown error types.
 */
export function inferCategoryFromError(error: Error): ErrorCategory {
  const message = error.message.toLowerCase();
  const name = error.name.toLowerCase();

  // Check for network-related errors
  if (
    name.includes('network') ||
    name.includes('fetch') ||
    message.includes('network') ||
    message.includes('connection') ||
    message.includes('timeout') ||
    message.includes('offline')
  ) {
    return ErrorCategory.Network;
  }

  // Check for authentication errors
  if (
    message.includes('unauthorized') ||
    message.includes('authentication') ||
    message.includes('api key') ||
    message.includes('token') ||
    message.includes('401') ||
    message.includes('403')
  ) {
    return ErrorCategory.Authentication;
  }

  // Check for storage/file errors
  if (
    message.includes('storage') ||
    message.includes('disk') ||
    message.includes('file') ||
    message.includes('enoent') ||
    message.includes('eacces') ||
    message.includes('permission denied')
  ) {
    return ErrorCategory.Storage;
  }

  // Check for memory errors
  if (
    message.includes('memory') ||
    message.includes('out of memory') ||
    message.includes('heap')
  ) {
    return ErrorCategory.Memory;
  }

  // Check for model errors
  if (
    message.includes('model') ||
    message.includes('inference') ||
    message.includes('onnx') ||
    message.includes('llama')
  ) {
    return ErrorCategory.Model;
  }

  // Check for generation errors
  if (
    message.includes('generation') ||
    message.includes('token') ||
    message.includes('context length')
  ) {
    return ErrorCategory.Generation;
  }

  // Check for validation errors
  if (
    message.includes('invalid') ||
    message.includes('validation') ||
    message.includes('required')
  ) {
    return ErrorCategory.Validation;
  }

  // Check for initialization errors
  if (
    message.includes('not initialized') ||
    message.includes('already initialized') ||
    message.includes('initialization')
  ) {
    return ErrorCategory.Initialization;
  }

  return ErrorCategory.Unknown;
}
