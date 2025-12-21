/**
 * StructuredOutputHandler.ts
 *
 * Handles structured output generation and validation
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/LLM/StructuredOutput/Generatable.swift
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/LLM/StructuredOutput/StructuredOutputHandler.swift
 */

/**
 * Protocol for types that can be generated as structured output from LLMs
 * Matches iOS Generatable protocol
 */
export interface GeneratableType {
  /**
   * The JSON schema for this type
   */
  readonly jsonSchema: string;
}

/**
 * Structured output configuration
 * Matches iOS StructuredOutputConfig
 */
export interface StructuredOutputConfig {
  /** The type to generate */
  readonly type: GeneratableType;
  /** Whether to include schema in prompt */
  readonly includeSchemaInPrompt: boolean;
}

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
export enum StructuredOutputError {
  InvalidJSON = 'invalidJSON',
  ValidationFailed = 'validationFailed',
  ExtractionFailed = 'extractionFailed',
  UnsupportedType = 'unsupportedType',
}

/**
 * Handles structured output generation and validation
 */
export class StructuredOutputHandler {
  /**
   * Get system prompt for structured output generation
   */
  public getSystemPrompt<T extends { jsonSchema: string }>(type: T): string {
    const schema = type.jsonSchema;

    return `You are a JSON generator that outputs ONLY valid JSON without any additional text.

CRITICAL RULES:
1. Your entire response must be valid JSON that can be parsed
2. Start with { and end with }
3. No text before the opening {
4. No text after the closing }
5. Follow the provided schema exactly
6. Include all required fields
7. Use proper JSON syntax (quotes, commas, etc.)

Expected JSON Schema:
${schema}

Remember: Output ONLY the JSON object, nothing else.`;
  }

  /**
   * Build user prompt for structured output (simplified without instructions)
   */
  public buildUserPrompt<T extends { jsonSchema: string }>(
    type: T,
    content: string
  ): string {
    // Return clean user prompt without JSON instructions
    // The instructions are now in the system prompt
    return content;
  }

  /**
   * Prepare prompt with structured output instructions
   */
  public preparePrompt(
    originalPrompt: string,
    config: StructuredOutputConfig
  ): string {
    if (!config.includeSchemaInPrompt) {
      return originalPrompt;
    }

    const schema = config.type.jsonSchema;

    // Build structured output instructions with stronger emphasis
    const instructions = `CRITICAL INSTRUCTION: You MUST respond with ONLY a valid JSON object. No other text is allowed.

JSON Schema:
${schema}

RULES:
1. Start your response with { and end with }
2. Include NO text before the opening {
3. Include NO text after the closing }
4. Follow the schema exactly
5. All required fields must be present
6. Use exact field names from the schema
7. Ensure proper JSON syntax (quotes, commas, etc.)

IMPORTANT: Your entire response must be valid JSON that can be parsed. Do not include any explanations, comments, or additional text.`;

    // Combine with system-like instruction at the beginning
    return `System: You are a JSON generator. You must output only valid JSON.

${originalPrompt}

${instructions}

Remember: Output ONLY the JSON object, nothing else.`;
  }

  /**
   * Extract JSON from potentially mixed text
   */
  private extractJSON(text: string): string {
    const trimmed = text.trim();

    // First, try to find a complete JSON object
    const jsonRange = this.findCompleteJSON(trimmed);
    if (jsonRange) {
      return trimmed.substring(jsonRange.start, jsonRange.end);
    }

    // Fallback: Try to find JSON object boundaries
    const startIndex = trimmed.indexOf('{');
    if (startIndex !== -1) {
      const endIndex = this.findMatchingBrace(trimmed, startIndex);
      if (endIndex !== null) {
        return trimmed.substring(startIndex, endIndex + 1);
      }
    }

    // Try to find JSON array boundaries
    const arrayStartIndex = trimmed.indexOf('[');
    if (arrayStartIndex !== -1) {
      const arrayEndIndex = this.findMatchingBracket(trimmed, arrayStartIndex);
      if (arrayEndIndex !== null) {
        return trimmed.substring(arrayStartIndex, arrayEndIndex + 1);
      }
    }

    // If no clear JSON boundaries, check if the entire text might be JSON
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return trimmed;
    }

    throw new Error('No valid JSON found in the response');
  }

  /**
   * Find a complete JSON object or array in the text
   */
  private findCompleteJSON(
    text: string
  ): { start: number; end: number } | null {
    // Try to parse different segments of the text to find valid JSON
    for (const startChar of ['{', '[']) {
      const startIndex = text.indexOf(startChar);
      if (startIndex === -1) continue;

      const endChar = startChar === '{' ? '}' : ']';
      let depth = 0;
      let inString = false;
      let escaped = false;

      for (let i = startIndex; i < text.length; i++) {
        const char = text[i];

        if (escaped) {
          escaped = false;
          continue;
        }

        if (char === '\\') {
          escaped = true;
          continue;
        }

        if (char === '"') {
          inString = !inString;
          continue;
        }

        if (inString) continue;

        if (char === startChar) {
          depth++;
        } else if (char === endChar) {
          depth--;
          if (depth === 0) {
            // Found complete JSON
            return { start: startIndex, end: i + 1 };
          }
        }
      }
    }

    return null;
  }

  /**
   * Find matching closing brace
   */
  private findMatchingBrace(text: string, startIndex: number): number | null {
    let depth = 0;
    let inString = false;
    let escaped = false;

    for (let i = startIndex; i < text.length; i++) {
      const char = text[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char === '\\') {
        escaped = true;
        continue;
      }

      if (char === '"') {
        inString = !inString;
        continue;
      }

      if (inString) continue;

      if (char === '{') {
        depth++;
      } else if (char === '}') {
        depth--;
        if (depth === 0) {
          return i;
        }
      }
    }

    return null;
  }

  /**
   * Find matching closing bracket
   */
  private findMatchingBracket(text: string, startIndex: number): number | null {
    let depth = 0;
    let inString = false;
    let escaped = false;

    for (let i = startIndex; i < text.length; i++) {
      const char = text[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char === '\\') {
        escaped = true;
        continue;
      }

      if (char === '"') {
        inString = !inString;
        continue;
      }

      if (inString) continue;

      if (char === '[') {
        depth++;
      } else if (char === ']') {
        depth--;
        if (depth === 0) {
          return i;
        }
      }
    }

    return null;
  }

  /**
   * Parse and validate structured output from generated text
   * Matches iOS: parseStructuredOutput(from:type:)
   *
   * @param text - The generated text containing JSON
   * @param schema - The schema type to validate against
   * @returns The parsed and validated object
   * @throws Error if extraction or parsing fails
   */
  public parseStructuredOutput<T>(text: string, schema: GeneratableType): T {
    // Extract JSON from the response
    const jsonString = this.extractJSON(text);

    // Parse the JSON
    try {
      const parsed = JSON.parse(jsonString) as T;
      return parsed;
    } catch (error) {
      const message =
        error instanceof Error ? error.message : String(error);
      throw new Error(
        `${StructuredOutputError.InvalidJSON}: Failed to parse JSON - ${message}`
      );
    }
  }

  /**
   * Validate that generated text contains valid structured output
   * Matches iOS: validateStructuredOutput(text:config:)
   */
  public validateStructuredOutput(
    text: string,
    _config: StructuredOutputConfig
  ): StructuredOutputValidation {
    try {
      this.extractJSON(text);
      return {
        isValid: true,
        containsJSON: true,
        error: null,
      };
    } catch (error) {
      return {
        isValid: false,
        containsJSON: false,
        error: error instanceof Error ? error.message : String(error),
      };
    }
  }
}
