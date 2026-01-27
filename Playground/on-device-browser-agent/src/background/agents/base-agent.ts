/**
 * Base Agent Class
 *
 * Abstract base class for all agents. Provides:
 * - LLM invocation via WebLLM
 * - JSON extraction from responses
 * - Conversation history management
 */

import { ChatCompletionMessageParam } from '@mlc-ai/web-llm';
import { llmEngine } from '../llm-engine';
import { AGENT_TEMPERATURE, AGENT_MAX_TOKENS } from '../../shared/constants';

// ============================================================================
// Base Agent
// ============================================================================

export abstract class BaseAgent<TOutput> {
  /** System prompt defining the agent's role and behavior */
  protected abstract systemPrompt: string;

  /** JSON schema as a string to include in the prompt */
  protected abstract outputSchema: string;

  /** Conversation history for multi-turn reasoning */
  protected conversationHistory: ChatCompletionMessageParam[] = [];

  constructor(protected agentName: string) {}

  /**
   * Invoke the agent with a user message
   * Returns parsed JSON output matching TOutput schema
   */
  async invoke(userMessage: string): Promise<TOutput> {
    // Build messages array with system prompt, history, and new message
    const messages: ChatCompletionMessageParam[] = [
      { role: 'system', content: this.buildSystemPrompt() },
      ...this.conversationHistory,
      { role: 'user', content: userMessage },
    ];

    console.log(`[${this.agentName}] Invoking with message:`, userMessage.slice(0, 100) + '...');

    // Get LLM response
    const response = await llmEngine.chat(messages, {
      temperature: AGENT_TEMPERATURE,
      maxTokens: AGENT_MAX_TOKENS,
    });

    console.log(`[${this.agentName}] Response:`, response.slice(0, 200) + '...');

    // Extract and parse JSON from response
    const parsed = this.extractJSON<TOutput>(response);

    // Update conversation history for context in future turns
    this.conversationHistory.push(
      { role: 'user', content: userMessage },
      { role: 'assistant', content: response }
    );

    // Keep history manageable (last 10 turns = 20 messages)
    if (this.conversationHistory.length > 20) {
      this.conversationHistory = this.conversationHistory.slice(-20);
    }

    return parsed;
  }

  /**
   * Build the complete system prompt with schema instructions
   */
  protected buildSystemPrompt(): string {
    return `${this.systemPrompt}

You MUST respond with valid JSON matching this schema:
\`\`\`json
${this.outputSchema}
\`\`\`

IMPORTANT:
- Respond ONLY with the JSON object, no additional text before or after
- Do not include markdown code fences in your response
- Ensure all JSON strings are properly escaped
- Do not add comments in the JSON`;
  }

  /**
   * Extract JSON from LLM response with multiple fallback strategies
   */
  protected extractJSON<T>(response: string): T {
    const cleanResponse = response.trim();

    // Strategy 1: Direct parsing
    try {
      return JSON.parse(cleanResponse) as T;
    } catch {
      // Continue to fallback strategies
    }

    // Strategy 2: Extract from markdown code blocks
    const codeBlockMatch = cleanResponse.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (codeBlockMatch) {
      try {
        return JSON.parse(codeBlockMatch[1].trim()) as T;
      } catch {
        // Continue to next strategy
      }
    }

    // Strategy 3: Find JSON object in response
    const jsonMatch = cleanResponse.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      try {
        return JSON.parse(jsonMatch[0]) as T;
      } catch {
        // Continue to next strategy
      }
    }

    // Strategy 4: Try to fix common issues
    const fixed = this.attemptJSONFix(cleanResponse);
    if (fixed) {
      try {
        return JSON.parse(fixed) as T;
      } catch {
        // Give up
      }
    }

    // All strategies failed
    throw new Error(
      `[${this.agentName}] Failed to extract valid JSON from response:\n${response.slice(0, 500)}...`
    );
  }

  /**
   * Attempt to fix common JSON issues
   */
  private attemptJSONFix(response: string): string | null {
    // Try to extract just the object part
    const match = response.match(/\{[\s\S]*\}/);
    if (!match) return null;

    let json = match[0];

    // Fix trailing commas
    json = json.replace(/,\s*}/g, '}');
    json = json.replace(/,\s*]/g, ']');

    // Fix unescaped newlines in strings
    json = json.replace(/([^\\])\\n/g, '$1\\\\n');

    return json;
  }

  /**
   * Reset conversation history
   * Call this when starting a new task or after replanning
   */
  reset(): void {
    this.conversationHistory = [];
    console.log(`[${this.agentName}] Conversation history reset`);
  }
}
