/**
 * helpers/structuredOutput — ergonomic helpers for proto-encoded
 * structured-output types.
 */

import { StructuredOutputOptions } from '@runanywhere/proto-ts/structured_output';

export {
  StructuredOutputOptions,
  type JSONSchema,
  type JSONSchemaProperty,
  JSONSchemaType,
  type StructuredOutputValidation,
  type StructuredOutputResult,
  type ClassificationResult,
  type ClassificationCandidate,
  type SentimentResult,
  type NamedEntity,
  type NERResult,
  type EntityExtractionResult,
  Sentiment,
} from '@runanywhere/proto-ts/structured_output';

/** Default `StructuredOutputOptions`. */
export function defaultStructuredOutputOptions(): StructuredOutputOptions {
  return StructuredOutputOptions.create({
    includeSchemaInPrompt: true,
    strictMode: true,
  });
}
