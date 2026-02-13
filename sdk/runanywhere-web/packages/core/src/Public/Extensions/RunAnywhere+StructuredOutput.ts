/**
 * RunAnywhere Web SDK - Structured Output Extension
 *
 * Adds JSON-structured output capabilities for LLM generation.
 * Uses the RACommons rac_structured_output_* C API for schema-guided
 * generation and JSON extraction/validation.
 *
 * Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/StructuredOutput/
 *
 * Usage:
 *   import { StructuredOutput, TextGeneration } from '@runanywhere/web';
 *
 *   const schema = JSON.stringify({ type: 'object', properties: { name: { type: 'string' } } });
 *   const prompt = await StructuredOutput.preparePrompt('List 3 colors', schema);
 *   const result = await TextGeneration.generate(prompt);
 *   const validated = StructuredOutput.validate(result.text, schema);
 *   console.log(validated.extractedJson); // parsed JSON
 */

import { RunAnywhere } from '../RunAnywhere';
import { WASMBridge } from '../../Foundation/WASMBridge';
import { SDKError } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';

const logger = new SDKLogger('StructuredOutput');

function requireBridge(): WASMBridge {
  if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
  return WASMBridge.shared;
}

// ---------------------------------------------------------------------------
// Structured Output Types
// ---------------------------------------------------------------------------

export interface StructuredOutputConfig {
  /** JSON Schema string */
  jsonSchema: string;
  /** Whether to include the schema in the prompt (default: true) */
  includeSchemaInPrompt?: boolean;
}

export interface StructuredOutputValidation {
  isValid: boolean;
  errorMessage?: string;
  extractedJson?: string;
}

// ---------------------------------------------------------------------------
// Structured Output Extension
// ---------------------------------------------------------------------------

export const StructuredOutput = {
  /**
   * Extract JSON from a text response (finds first complete JSON object/array).
   *
   * @param text - Raw LLM output text
   * @returns Extracted JSON string, or null if none found
   */
  extractJson(text: string): string | null {
    const bridge = requireBridge();
    const m = bridge.module;

    const textPtr = bridge.allocString(text);
    const outJsonPtr = m._malloc(4);  // char** out_json
    const outLenPtr = m._malloc(4);   // size_t* out_length

    try {
      const result = m.ccall(
        'rac_structured_output_extract_json', 'number',
        ['number', 'number', 'number'],
        [textPtr, outJsonPtr, outLenPtr],
      ) as number;

      if (result !== 0) return null;

      const jsonPtr = m.getValue(outJsonPtr, '*');
      if (!jsonPtr) return null;

      const json = bridge.readString(jsonPtr);
      m._free(jsonPtr); // rac_strdup'd, so we free it
      return json;
    } finally {
      bridge.free(textPtr);
      m._free(outJsonPtr);
      m._free(outLenPtr);
    }
  },

  /**
   * Prepare a prompt with schema instructions for structured output.
   *
   * @param originalPrompt - The user's original prompt
   * @param config - Schema configuration
   * @returns Enhanced prompt with schema instructions
   */
  preparePrompt(originalPrompt: string, config: StructuredOutputConfig): string {
    const bridge = requireBridge();
    const m = bridge.module;

    const promptPtr = bridge.allocString(originalPrompt);

    // Build rac_structured_output_config_t: { json_schema, include_schema_in_prompt }
    const configSize = m._rac_wasm_sizeof_structured_output_config();
    const configPtr = m._malloc(configSize);
    const schemaPtr = bridge.allocString(config.jsonSchema);
    m.setValue(configPtr, schemaPtr, '*');
    m.setValue(configPtr + 4, (config.includeSchemaInPrompt !== false) ? 1 : 0, 'i32');

    const outPromptPtr = m._malloc(4);

    try {
      const result = m.ccall(
        'rac_structured_output_prepare_prompt', 'number',
        ['number', 'number', 'number'],
        [promptPtr, configPtr, outPromptPtr],
      ) as number;

      if (result !== 0) {
        logger.warning('Failed to prepare structured prompt, returning original');
        return originalPrompt;
      }

      const preparedPtr = m.getValue(outPromptPtr, '*');
      if (!preparedPtr) return originalPrompt;

      const prepared = bridge.readString(preparedPtr);
      m._free(preparedPtr);
      return prepared;
    } finally {
      bridge.free(promptPtr);
      bridge.free(schemaPtr);
      m._free(configPtr);
      m._free(outPromptPtr);
    }
  },

  /**
   * Get a system prompt that instructs the LLM to produce JSON matching a schema.
   *
   * @param jsonSchema - JSON Schema string
   * @returns System prompt string
   */
  getSystemPrompt(jsonSchema: string): string {
    const bridge = requireBridge();
    const m = bridge.module;

    const schemaPtr = bridge.allocString(jsonSchema);
    const outPtr = m._malloc(4);

    try {
      const result = m.ccall(
        'rac_structured_output_get_system_prompt', 'number',
        ['number', 'number'],
        [schemaPtr, outPtr],
      ) as number;

      if (result !== 0) return '';

      const ptr = m.getValue(outPtr, '*');
      if (!ptr) return '';

      const prompt = bridge.readString(ptr);
      m._free(ptr);
      return prompt;
    } finally {
      bridge.free(schemaPtr);
      m._free(outPtr);
    }
  },

  /**
   * Validate LLM output against a JSON schema.
   *
   * @param text - Raw LLM output
   * @param config - Schema configuration
   * @returns Validation result with extracted JSON if valid
   */
  validate(text: string, config: StructuredOutputConfig): StructuredOutputValidation {
    const bridge = requireBridge();
    const m = bridge.module;

    const textPtr = bridge.allocString(text);

    const configSize = m._rac_wasm_sizeof_structured_output_config();
    const configPtr = m._malloc(configSize);
    const schemaPtr = bridge.allocString(config.jsonSchema);
    m.setValue(configPtr, schemaPtr, '*');
    m.setValue(configPtr + 4, (config.includeSchemaInPrompt !== false) ? 1 : 0, 'i32');

    // rac_structured_output_validation_t: { is_valid, error_message, extracted_json }
    const valSize = 12;
    const valPtr = m._malloc(valSize);

    try {
      const result = m.ccall(
        'rac_structured_output_validate', 'number',
        ['number', 'number', 'number'],
        [textPtr, configPtr, valPtr],
      ) as number;

      if (result !== 0) {
        return { isValid: false, errorMessage: 'Validation call failed' };
      }

      const isValid = m.getValue(valPtr, 'i32') === 1;
      const errorMsgPtr = m.getValue(valPtr + 4, '*');
      const extractedPtr = m.getValue(valPtr + 8, '*');

      const validation: StructuredOutputValidation = {
        isValid,
        errorMessage: errorMsgPtr ? bridge.readString(errorMsgPtr) : undefined,
        extractedJson: extractedPtr ? bridge.readString(extractedPtr) : undefined,
      };

      // Free C validation struct
      m.ccall('rac_structured_output_validation_free', null, ['number'], [valPtr]);

      return validation;
    } finally {
      bridge.free(textPtr);
      bridge.free(schemaPtr);
      m._free(configPtr);
    }
  },

  /**
   * Check if text contains a complete JSON object or array.
   *
   * @param text - Text to check
   * @returns True if a complete JSON block was found
   */
  hasCompleteJson(text: string): boolean {
    const bridge = requireBridge();
    const m = bridge.module;

    const textPtr = bridge.allocString(text);
    const startPtr = m._malloc(4);
    const endPtr = m._malloc(4);

    try {
      const found = m.ccall(
        'rac_structured_output_find_complete_json', 'number',
        ['number', 'number', 'number'],
        [textPtr, startPtr, endPtr],
      ) as number;
      return found === 1;
    } finally {
      bridge.free(textPtr);
      m._free(startPtr);
      m._free(endPtr);
    }
  },
};
