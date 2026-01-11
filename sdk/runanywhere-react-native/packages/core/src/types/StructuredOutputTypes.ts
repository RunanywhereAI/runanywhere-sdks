/**
 * StructuredOutputTypes.ts
 *
 * Type definitions for Structured Output functionality.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/StructuredOutput/
 */

/**
 * JSON Schema type
 */
export type JSONSchemaType =
  | 'string'
  | 'number'
  | 'integer'
  | 'boolean'
  | 'object'
  | 'array'
  | 'null';

/**
 * JSON Schema property
 */
export interface JSONSchemaProperty {
  type?: JSONSchemaType | JSONSchemaType[];
  description?: string;
  enum?: (string | number | boolean)[];
  const?: string | number | boolean;
  default?: unknown;

  // String validations
  minLength?: number;
  maxLength?: number;
  pattern?: string;
  format?: string;

  // Number validations
  minimum?: number;
  maximum?: number;
  exclusiveMinimum?: number;
  exclusiveMaximum?: number;
  multipleOf?: number;

  // Array validations
  items?: JSONSchema;
  minItems?: number;
  maxItems?: number;
  uniqueItems?: boolean;

  // Object validations
  properties?: Record<string, JSONSchemaProperty>;
  required?: string[];
  additionalProperties?: boolean | JSONSchema;
}

/**
 * JSON Schema definition
 */
export interface JSONSchema extends JSONSchemaProperty {
  $schema?: string;
  $id?: string;
  title?: string;
  definitions?: Record<string, JSONSchema>;
  $ref?: string;

  // Composition
  allOf?: JSONSchema[];
  anyOf?: JSONSchema[];
  oneOf?: JSONSchema[];
  not?: JSONSchema;
}

/**
 * Structured output options
 */
export interface StructuredOutputOptions {
  /** Maximum tokens to generate */
  maxTokens?: number;

  /** Temperature for generation (0.0 - 2.0) */
  temperature?: number;

  /** Strict schema adherence */
  strict?: boolean;

  /** Number of retries on parse failure */
  retries?: number;
}

/**
 * Structured output result
 */
export interface StructuredOutputResult<T = unknown> {
  /** Parsed data */
  data: T;

  /** Raw JSON string */
  raw: string;

  /** Whether generation was successful */
  success: boolean;

  /** Error message if failed */
  error?: string;
}

/**
 * Entity extraction result
 */
export interface EntityExtractionResult<T = unknown> {
  entities: T;
  confidence: number;
}

/**
 * Classification result
 */
export interface ClassificationResult {
  category: string;
  confidence: number;
  alternatives?: Array<{
    category: string;
    confidence: number;
  }>;
}

/**
 * Sentiment analysis result
 */
export interface SentimentResult {
  sentiment: 'positive' | 'negative' | 'neutral';
  score: number;
  aspects?: Array<{
    aspect: string;
    sentiment: 'positive' | 'negative' | 'neutral';
    score: number;
  }>;
}

/**
 * Named entity result
 */
export interface NamedEntity {
  text: string;
  type: string;
  startOffset: number;
  endOffset: number;
  confidence: number;
}

/**
 * Named entity recognition result
 */
export interface NERResult {
  entities: NamedEntity[];
}
