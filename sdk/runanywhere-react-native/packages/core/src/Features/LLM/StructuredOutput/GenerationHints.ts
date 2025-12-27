/**
 * Hints for customizing structured output generation
 */
export interface GenerationHints {
  /**
   * Temperature for generation (controls randomness)
   * Typically between 0.0 (deterministic) and 1.0 (more random)
   */
  temperature?: number;

  /**
   * Maximum number of tokens to generate
   */
  maxTokens?: number;

  /**
   * System role/prompt to guide generation
   */
  systemRole?: string;
}

/**
 * Creates generation hints with default values
 */
export function createGenerationHints(
  temperature?: number,
  maxTokens?: number,
  systemRole?: string
): GenerationHints {
  return {
    temperature,
    maxTokens,
    systemRole,
  };
}

/**
 * Interface for types that support generation hints
 * Extend this interface to provide type-specific generation hints
 */
export interface WithGenerationHints {
  /**
   * Type-specific generation hints
   * Return undefined for default behavior
   */
  generationHints?: GenerationHints;
}
