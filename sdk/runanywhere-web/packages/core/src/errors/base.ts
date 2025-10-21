export abstract class BaseError extends Error {
  public readonly timestamp: Date;
  public readonly context?: Record<string, unknown>;

  constructor(
    message: string,
    public readonly code: string,
    context?: Record<string, unknown>
  ) {
    super(message);
    this.name = this.constructor.name;
    this.timestamp = new Date();
    this.context = context;
    Error.captureStackTrace(this, this.constructor);
  }

  toJSON() {
    return {
      name: this.name,
      code: this.code,
      message: this.message,
      timestamp: this.timestamp,
      context: this.context,
      stack: this.stack
    };
  }
}

export class SDKError extends BaseError {
  constructor(message: string, code: string, context?: Record<string, unknown>) {
    super(message, `SDK_${code}`, context);
  }
}

export class ConfigurationError extends SDKError {
  constructor(message: string, context?: Record<string, unknown>) {
    super(message, 'CONFIGURATION_ERROR', context);
  }
}

export class InitializationError extends SDKError {
  constructor(message: string, context?: Record<string, unknown>) {
    super(message, 'INITIALIZATION_ERROR', context);
  }
}

export class ValidationError extends SDKError {
  constructor(message: string, context?: Record<string, unknown>) {
    super(message, 'VALIDATION_ERROR', context);
  }
}

export class NetworkError extends SDKError {
  constructor(message: string, context?: Record<string, unknown>) {
    super(message, 'NETWORK_ERROR', context);
  }
}

export class AudioError extends SDKError {
  constructor(message: string, context?: Record<string, unknown>) {
    super(message, 'AUDIO_ERROR', context);
  }
}

export class ModelError extends SDKError {
  constructor(message: string, context?: Record<string, unknown>) {
    super(message, 'MODEL_ERROR', context);
  }
}
