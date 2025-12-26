/**
 * ThinkingTagPattern.ts
 *
 * Pattern for extracting thinking/reasoning content from model output
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/TextGeneration/Models/ThinkingTagPattern.swift
 */

/**
 * Pattern for extracting thinking/reasoning content from model output
 */
export interface ThinkingTagPattern {
  readonly openingTag: string;
  readonly closingTag: string;
}

/**
 * Create a thinking tag pattern
 */
export class ThinkingTagPatternImpl implements ThinkingTagPattern {
  public readonly openingTag: string;
  public readonly closingTag: string;

  constructor(openingTag: string, closingTag: string) {
    this.openingTag = openingTag;
    this.closingTag = closingTag;
  }

  /**
   * Default pattern used by models like DeepSeek and Hermes
   */
  public static readonly defaultPattern = new ThinkingTagPatternImpl(
    '<think>',
    '</think>'
  );

  /**
   * Alternative pattern with full "thinking" word
   */
  public static readonly thinkingPattern = new ThinkingTagPatternImpl(
    '<thinking>',
    '</thinking>'
  );
}
