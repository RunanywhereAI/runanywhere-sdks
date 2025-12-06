/**
 * ThinkingParser.ts
 *
 * Parser for extracting thinking/reasoning content from model output
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/TextGeneration/Services/ThinkingParser.swift
 */

import type { ThinkingTagPattern } from '../Models/ThinkingTagPattern';

/**
 * Result of parsing thinking content
 */
export interface ParseResult {
  readonly content: string; // Content without thinking tags
  readonly thinkingContent: string | null; // Extracted thinking content
}

/**
 * Token type for streaming parsing
 */
export enum TokenType {
  Content = 'content',
  Thinking = 'thinking',
}

/**
 * Streaming parsing state
 */
export interface StreamingParseState {
  buffer: string;
  inThinkingSection: boolean;
}

/**
 * Parser for extracting thinking/reasoning content from model output
 */
export class ThinkingParser {
  /**
   * Parse and extract thinking content from text
   */
  public static parse(text: string, pattern: ThinkingTagPattern): ParseResult {
    // Find the first occurrence of the opening tag
    const openIndex = text.indexOf(pattern.openingTag);
    if (openIndex === -1) {
      // No thinking tags found
      return { content: text, thinkingContent: null };
    }

    // Find the corresponding closing tag
    const searchStart = openIndex + pattern.openingTag.length;
    const closeIndex = text.indexOf(pattern.closingTag, searchStart);
    if (closeIndex === -1) {
      // Opening tag found but no closing tag
      return { content: text, thinkingContent: null };
    }

    // Extract thinking content
    const thinkingContent = text.substring(
      openIndex + pattern.openingTag.length,
      closeIndex
    );

    // Remove thinking section from content
    const beforeThinking = text.substring(0, openIndex);
    const afterThinking = text.substring(closeIndex + pattern.closingTag.length);
    const content = (beforeThinking + afterThinking).trim();

    return {
      content,
      thinkingContent: thinkingContent.trim() || null,
    };
  }

  /**
   * Parse streaming tokens and detect thinking sections
   */
  public static parseStreamingToken(
    token: string,
    pattern: ThinkingTagPattern,
    state: StreamingParseState
  ): { tokenType: TokenType; cleanToken: string | null } {
    // Add token to buffer
    state.buffer += token;

    // Check if we're entering a thinking section
    if (!state.inThinkingSection && state.buffer.includes(pattern.openingTag)) {
      // Found opening tag
      const openIndex = state.buffer.indexOf(pattern.openingTag);
      if (openIndex !== -1) {
        // Extract any content before the thinking tag
        const beforeThinking = state.buffer.substring(0, openIndex);

        // Update buffer to start after opening tag
        state.buffer = state.buffer.substring(openIndex + pattern.openingTag.length);
        state.inThinkingSection = true;

        // Return any content before thinking as regular content
        if (beforeThinking.length > 0) {
          return { tokenType: TokenType.Content, cleanToken: beforeThinking };
        }
      }
    }

    // Check if we're exiting a thinking section
    if (state.inThinkingSection && state.buffer.includes(pattern.closingTag)) {
      // Found closing tag
      const closeIndex = state.buffer.indexOf(pattern.closingTag);
      if (closeIndex !== -1) {
        // Extract thinking content
        const thinkingContent = state.buffer.substring(0, closeIndex);

        // Update buffer to start after closing tag
        state.buffer = state.buffer.substring(closeIndex + pattern.closingTag.length);
        state.inThinkingSection = false;

        // Return the thinking content
        if (thinkingContent.length > 0) {
          return { tokenType: TokenType.Thinking, cleanToken: thinkingContent };
        }

        // Check if there's content after the closing tag
        if (state.buffer.length > 0) {
          const content = state.buffer;
          state.buffer = '';
          return { tokenType: TokenType.Content, cleanToken: content };
        }
      }
    }

    // If we're in a thinking section, accumulate tokens
    if (state.inThinkingSection) {
      // Don't emit anything yet, just accumulate
      return { tokenType: TokenType.Thinking, cleanToken: null };
    }

    // Regular content token
    const content = state.buffer;
    state.buffer = '';
    return { tokenType: TokenType.Content, cleanToken: content.length > 0 ? content : null };
  }
}

