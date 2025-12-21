/**
 * LLM Capability exports
 */
export { LLMCapability, LLMServiceWrapper } from './LLMCapability';
export type { GenerationMetrics } from './LLMCapability';

export type { LLMConfiguration } from './LLMConfiguration';
export { LLMConfigurationImpl, LLMQuantizationLevel } from './LLMConfiguration';

export {
  type LLMInput,
  type LLMOutput,
  type Message,
  type Context,
  type TokenUsage,
  type GenerationMetadata,
  type RunAnywhereGenerationOptions,
  type LLMStreamToken,
  type LLMStreamMetrics,
  type LLMStreamResult,
  MessageRole,
  FinishReason,
} from './LLMModels';

// Structured Output
export type {
  GenerationHints,
  WithGenerationHints,
  Generatable,
  StructuredOutputConfig,
  StreamToken,
  StructuredOutputStreamResult,
  StructuredOutputValidation,
  LLMGenerationOptions as StructuredOutputLLMGenerationOptions,
  LLMCapability as StructuredOutputLLMCapability,
  StructuredOutputHandler,
  JSONSchema,
  SchemaProperty,
} from './StructuredOutput';
export {
  createGenerationHints,
  createStructuredOutputConfig,
  createGeneratable,
  createStreamToken,
  createStructuredOutputStreamResult,
  StreamAccumulator,
  StructuredOutputError,
  StructuredOutputErrorType,
  createValidationResult,
  StructuredOutputGenerationService,
  createObjectSchema,
  stringProperty,
  numberProperty,
  booleanProperty,
  arrayProperty,
  objectProperty,
  enumProperty,
} from './StructuredOutput';

// Errors
export {
  type LLMError,
  type NotInitializedError,
  type NoProviderFoundError,
  type ModelNotFoundError,
  type InitializationFailedError,
  type GenerationFailedError,
  type GenerationTimeoutError,
  type ContextLengthExceededError,
  type InvalidOptionsError,
  type StreamingNotSupportedError,
  type StreamCancelledError,
  type InsufficientMemoryError,
  type ServiceBusyError,
  LLMErrorType,
  LLMErrorFactory,
  LLMErrorGuards,
  isLLMError,
} from './Errors/LLMError';
