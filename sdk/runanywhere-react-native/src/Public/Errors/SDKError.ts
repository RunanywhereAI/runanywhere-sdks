/**
 * SDKError.ts
 *
 * SDK-specific errors
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Errors/SDKError.swift
 */

import { LLMFramework } from '../../Core/Models/Framework/LLMFramework';

/**
 * SDK-specific errors
 */
export class SDKError extends Error {
  public readonly code: SDKErrorCode;
  public readonly details?: any;

  constructor(code: SDKErrorCode, message: string, details?: any) {
    super(message);
    this.name = 'SDKError';
    this.code = code;
    this.details = details;
  }

  /**
   * Create not initialized error
   */
  public static notInitialized(): SDKError {
    return new SDKError(
      SDKErrorCode.NotInitialized,
      'SDK not initialized. Call initialize(with:) first.'
    );
  }

  /**
   * Create model not found error
   */
  public static modelNotFound(model: string): SDKError {
    return new SDKError(
      SDKErrorCode.ModelNotFound,
      `Model '${model}' not found.`,
      { model }
    );
  }

  /**
   * Create loading failed error
   */
  public static loadingFailed(reason: string): SDKError {
    return new SDKError(
      SDKErrorCode.LoadingFailed,
      `Failed to load model: ${reason}`,
      { reason }
    );
  }

  /**
   * Create generation failed error
   */
  public static generationFailed(reason: string): SDKError {
    return new SDKError(
      SDKErrorCode.GenerationFailed,
      `Generation failed: ${reason}`,
      { reason }
    );
  }

  /**
   * Create invalid state error
   */
  public static invalidState(reason: string): SDKError {
    return new SDKError(
      SDKErrorCode.InvalidState,
      `Invalid state: ${reason}`,
      { reason }
    );
  }
}

/**
 * SDK error codes
 */
export enum SDKErrorCode {
  NotInitialized = 'notInitialized',
  NotImplemented = 'notImplemented',
  InvalidAPIKey = 'invalidAPIKey',
  ModelNotFound = 'modelNotFound',
  LoadingFailed = 'loadingFailed',
  GenerationFailed = 'generationFailed',
  GenerationTimeout = 'generationTimeout',
  FrameworkNotAvailable = 'frameworkNotAvailable',
  DownloadFailed = 'downloadFailed',
  ValidationFailed = 'validationFailed',
  RoutingFailed = 'routingFailed',
  DatabaseInitializationFailed = 'databaseInitializationFailed',
  UnsupportedModality = 'unsupportedModality',
  InvalidResponse = 'invalidResponse',
  AuthenticationFailed = 'authenticationFailed',
  NetworkError = 'networkError',
  InvalidState = 'invalidState',
  ComponentNotInitialized = 'componentNotInitialized',
  ComponentNotReady = 'componentNotReady',
  Timeout = 'timeout',
  ServerError = 'serverError',
  StorageError = 'storageError',
  InvalidConfiguration = 'invalidConfiguration',
}

