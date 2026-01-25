/**
 * YouTube State Machine
 *
 * Deterministic state machine for YouTube tasks.
 * NO LLM calls needed - all actions are derived from URL and DOM state.
 */

import type { DOMState, NavigatorOutput, AgentStep } from '../../../shared/types';

// ============================================================================
// Types
// ============================================================================

export type YouTubeState =
  | 'NAVIGATING'
  | 'ON_HOMEPAGE'
  | 'TYPED_QUERY'
  | 'ON_RESULTS'
  | 'ON_VIDEO'
  | 'DONE';

// ============================================================================
// YouTube State Machine
// ============================================================================

export class YouTubeStateMachine {
  private searchQuery: string = '';

  /**
   * Check if this state machine can handle the task
   */
  canHandle(url: string, task: string): boolean {
    const taskLower = task.toLowerCase();
    return (
      taskLower.includes('youtube') ||
      url.includes('youtube.com') ||
      (taskLower.includes('video') && (taskLower.includes('watch') || taskLower.includes('play')))
    );
  }

  /**
   * Set the search query for this task
   */
  setQuery(query: string): void {
    this.searchQuery = query;
  }

  /**
   * Determine current state from DOM
   */
  getState(dom: DOMState, history: AgentStep[]): YouTubeState {
    const url = dom.url || '';

    // Not on YouTube yet
    if (!url.includes('youtube.com')) {
      return 'NAVIGATING';
    }

    // On video page
    if (url.includes('/watch')) {
      return 'ON_VIDEO';
    }

    // On search results
    if (url.includes('/results') || url.includes('search_query=')) {
      return 'ON_RESULTS';
    }

    // Check if we just typed (need to submit)
    const lastAction = history[history.length - 1];
    if (lastAction?.action.action_type === 'type' && lastAction.result.success) {
      return 'TYPED_QUERY';
    }

    // On homepage or other YouTube page
    return 'ON_HOMEPAGE';
  }

  /**
   * Get the next action based on current state
   */
  getAction(state: YouTubeState, dom: DOMState, query?: string): NavigatorOutput | null {
    const searchQuery = query || this.searchQuery;

    switch (state) {
      case 'NAVIGATING':
        return this.createAction('navigate', { url: 'https://www.youtube.com' }, 'Navigate to YouTube');

      case 'ON_HOMEPAGE': {
        // Find search box
        const searchBox = this.findSearchBox(dom);
        if (searchBox && searchQuery) {
          return this.createAction('type', { selector: searchBox, text: searchQuery }, 'Type search query');
        }
        // No search box found or no query
        if (!searchQuery) {
          return this.createAction('done', { result: 'On YouTube homepage' }, 'No search query provided');
        }
        return null; // Can't find search box, let rule engine try
      }

      case 'TYPED_QUERY':
        return this.createAction('press_enter', {}, 'Submit search');

      case 'ON_RESULTS': {
        // Find first video to click
        const video = this.findFirstVideo(dom);
        if (video) {
          return this.createAction('click', { selector: video }, 'Click first video result');
        }
        // No video found, maybe need to scroll
        return this.createAction('scroll', { direction: 'down', amount: '500' }, 'Scroll to find videos');
      }

      case 'ON_VIDEO':
        return this.createAction('done', { result: 'Video page loaded' }, 'Task complete - on video page');

      case 'DONE':
        return this.createAction('done', { result: 'Task completed' }, 'Already done');

      default:
        return null;
    }
  }

  // ============================================================================
  // Element Finders
  // ============================================================================

  private findSearchBox(dom: DOMState): string | null {
    // YouTube search selectors in priority order
    const selectors = [
      'input#search',
      'input[name="search_query"]',
      'input[placeholder*="Search"]',
      'ytd-searchbox input',
    ];

    for (const selector of selectors) {
      const el = dom.interactiveElements.find(e =>
        e.selector.includes(selector.replace(/[#\[\]="*]/g, '')) ||
        (e.tag === 'input' && e.selector.toLowerCase().includes('search'))
      );
      if (el) return el.selector;
    }

    // Fallback: find any input that looks like search
    const searchInput = dom.interactiveElements.find(e =>
      e.tag === 'input' &&
      (e.text.toLowerCase().includes('search') ||
       e.attributes?.placeholder?.toLowerCase().includes('search') ||
       e.selector.toLowerCase().includes('search'))
    );

    return searchInput?.selector || null;
  }

  private findFirstVideo(dom: DOMState): string | null {
    // Priority 1: Elements with video-link type from our YouTube extraction
    for (const el of dom.interactiveElements) {
      if (el.type === 'video-link') {
        return el.selector;
      }
    }

    // Priority 2: Links with video-title in selector (from YouTube DOM extraction)
    for (const el of dom.interactiveElements) {
      if (el.tag !== 'a') continue;

      const selectorLower = el.selector.toLowerCase();
      if (selectorLower.includes('video-title') ||
          selectorLower.includes('video-title-link')) {
        return el.selector;
      }
    }

    // Priority 3: Links with /watch href
    for (const el of dom.interactiveElements) {
      if (el.tag !== 'a') continue;
      if (el.attributes?.href?.includes('/watch')) {
        // Skip short text (likely thumbnails/icons)
        if (el.text.length < 5) continue;
        return el.selector;
      }
    }

    // Priority 4: Substantial links that look like video titles
    for (const el of dom.interactiveElements) {
      if (el.tag !== 'a') continue;
      if (el.text.length < 15) continue;

      // Skip UI elements
      const textLower = el.text.toLowerCase();
      if (textLower.includes('filter') ||
          textLower.includes('sort') ||
          textLower.includes('subscribe') ||
          textLower.includes('sign in')) {
        continue;
      }

      return el.selector;
    }

    return null;
  }

  // ============================================================================
  // Action Builder
  // ============================================================================

  private createAction(
    actionType: string,
    parameters: Record<string, string>,
    thought: string
  ): NavigatorOutput {
    return {
      current_state: {
        page_summary: 'YouTube',
        relevant_elements: [],
        progress: thought,
      },
      action: {
        thought,
        action_type: actionType as any,
        parameters,
      },
    };
  }
}

// Export singleton
export const youtubeStateMachine = new YouTubeStateMachine();
