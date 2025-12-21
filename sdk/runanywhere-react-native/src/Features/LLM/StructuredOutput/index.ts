/**
 * Structured Output exports
 */

// Generation Hints
export type { GenerationHints, WithGenerationHints } from './GenerationHints';
export { createGenerationHints } from './GenerationHints';

// Generatable Protocol
export type { Generatable, StructuredOutputConfig } from './Generatable';
export { createStructuredOutputConfig, createGeneratable } from './Generatable';

// Stream Types
export type { StreamToken, StructuredOutputStreamResult } from './StreamToken';
export { createStreamToken, createStructuredOutputStreamResult } from './StreamToken';

// Stream Accumulator
export { StreamAccumulator } from './StreamAccumulator';

// Validation Types
export type { StructuredOutputValidation } from './StructuredOutputValidation';
export { StructuredOutputError, StructuredOutputErrorType, createValidationResult } from './StructuredOutputValidation';

// Generation Service
export { StructuredOutputGenerationService } from './StructuredOutputGenerationService';
export type { LLMGenerationOptions, LLMCapability, StructuredOutputHandler } from './StructuredOutputGenerationService';

// JSON Schema Generator
export type { JSONSchema, SchemaProperty } from './JSONSchemaGenerator';
export {
  createObjectSchema,
  stringProperty,
  numberProperty,
  booleanProperty,
  arrayProperty,
  objectProperty,
  enumProperty,
} from './JSONSchemaGenerator';
