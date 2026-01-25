/**
 * Site Router
 *
 * Routes tasks to site-specific state machines.
 * Provides a unified interface for the executor to use state machines
 * without knowing their implementation details.
 */

import type { DOMState, NavigatorOutput, AgentContext, AgentStep } from '../../shared/types';
import { AmazonStateMachine, extractSearchQuery, isAmazonTask } from './amazon-state-machine';
import { YouTubeStateMachine } from './state-machines/youtube';

// ============================================================================
// Types
// ============================================================================

export interface StateMachineResult {
  action: NavigatorOutput;
  state: string;
  machineName: string;
}

// ============================================================================
// Site Router
// ============================================================================

export class SiteRouter {
  private amazonMachine: AmazonStateMachine | null = null;
  private youtubeMachine = new YouTubeStateMachine();
  private currentMachine: string | null = null;

  /**
   * Initialize/reset the router for a new task
   */
  initialize(task: string): void {
    this.amazonMachine = null;
    this.currentMachine = null;

    // Initialize Amazon state machine if applicable
    if (isAmazonTask(task)) {
      const query = extractSearchQuery(task);
      if (query) {
        this.amazonMachine = new AmazonStateMachine(query);
        console.log(`[SiteRouter] Initialized Amazon machine with query: "${query}"`);
      }
    }

    // Initialize YouTube state machine if applicable
    const youtubQuery = this.extractYouTubeQuery(task);
    if (youtubQuery) {
      this.youtubeMachine.setQuery(youtubQuery);
      console.log(`[SiteRouter] Initialized YouTube machine with query: "${youtubQuery}"`);
    }
  }

  /**
   * Get the appropriate state machine action for the current context
   */
  getAction(
    task: string,
    dom: DOMState,
    context: AgentContext
  ): StateMachineResult | null {
    const url = dom.url || '';

    // Try YouTube first (simpler, no obstacles)
    if (this.youtubeMachine.canHandle(url, task)) {
      const state = this.youtubeMachine.getState(dom, context.history);
      const query = this.extractYouTubeQuery(task);
      const action = this.youtubeMachine.getAction(state, dom, query || '');

      if (action) {
        this.currentMachine = 'YouTube';
        return {
          action,
          state,
          machineName: 'YouTube',
        };
      }
    }

    // Try Amazon
    if (this.amazonMachine && (url.includes('amazon.') || isAmazonTask(task))) {
      const result = this.amazonMachine.process(dom, context);
      this.currentMachine = 'Amazon';

      return {
        action: result.action,
        state: this.amazonMachine.getState(),
        machineName: 'Amazon',
      };
    }

    // No state machine matched
    return null;
  }

  /**
   * Check if any state machine can handle this task
   */
  canHandle(task: string, url: string): boolean {
    return (
      this.youtubeMachine.canHandle(url, task) ||
      isAmazonTask(task)
    );
  }

  /**
   * Get the current state machine name
   */
  getCurrentMachine(): string | null {
    return this.currentMachine;
  }

  /**
   * Resume the Amazon state machine after user resolves obstacle
   */
  resumeAmazon(): void {
    this.amazonMachine?.resume();
  }

  /**
   * Extract search query for YouTube tasks
   */
  private extractYouTubeQuery(task: string): string | null {
    const patterns = [
      // YouTube specific
      /(?:youtube|video).*?(?:search|find|play|watch)\s+(?:for\s+)?["']?(.+?)["']?(?:\s+on|\s*$)/i,
      /(?:search|find|play|watch)\s+(?:for\s+)?["']?(.+?)["']?\s+(?:on\s+)?youtube/i,
      // Generic patterns
      /(?:play|watch)\s+["']?(.+?)["']?(?:\s+on|\s+video|\s*$)/i,
      /(?:search|find)\s+(?:for\s+)?["']?(.+?)["']?\s+video/i,
    ];

    for (const pattern of patterns) {
      const match = task.match(pattern);
      if (match && match[1]) {
        return match[1].trim();
      }
    }

    // Fallback: extract the object of the action
    const fallbackPattern = /(?:search|find|play|watch|open)\s+(?:for\s+)?["']?(.+?)["']?$/i;
    const fallbackMatch = task.match(fallbackPattern);
    if (fallbackMatch && fallbackMatch[1]) {
      // Filter out site names
      const query = fallbackMatch[1].trim();
      if (!query.toLowerCase().includes('youtube')) {
        return query;
      }
    }

    return null;
  }
}

// Export singleton instance
export const siteRouter = new SiteRouter();
