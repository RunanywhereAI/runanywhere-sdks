/**
 * Change Observer
 *
 * Detects if browser actions actually worked by comparing DOM state
 * before and after action execution. Provides deterministic verification
 * without needing LLM inference.
 */

import type { DOMState } from '../../shared/types';

// ============================================================================
// Types
// ============================================================================

export interface DOMSnapshot {
  url: string;
  title: string;
  textHash: number;
  elementCount: number;
  cartCount: number;
  timestamp: number;
}

export interface ChangeResult {
  urlChanged: boolean;
  titleChanged: boolean;
  pageChanged: boolean;
  elementsChanged: boolean;
  cartIncremented: boolean;
  successPattern: string | null;
  errorPattern: string | null;
  timeSinceSnapshot: number;
}

// ============================================================================
// Success/Error Patterns
// ============================================================================

const SUCCESS_PATTERNS: Record<string, string[]> = {
  addToCart: ['added to cart', 'added to your cart', '1 item added', 'view cart', 'go to cart'],
  search: ['results for', 'showing', 'found', 'search results'],
  video: ['subscribe', 'share', 'save to playlist'],
  form: ['thank you', 'success', 'confirmed', 'submitted'],
  navigation: [], // URL change is enough
};

const ERROR_PATTERNS: Record<string, string[]> = {
  outOfStock: ['out of stock', 'currently unavailable', 'sold out', 'not available'],
  error: ['error', 'failed', 'try again', 'something went wrong'],
  loginRequired: ['sign in', 'log in', 'create account', 'register'],
  captcha: ['verify you are human', 'captcha', 'robot'],
};

// ============================================================================
// Change Observer Class
// ============================================================================

export class ChangeObserver {
  private snapshot: DOMSnapshot | null = null;

  /**
   * Take a snapshot of the current DOM state before an action
   */
  takeSnapshot(dom: DOMState): void {
    this.snapshot = {
      url: dom.url || '',
      title: dom.title || '',
      textHash: this.hashText(dom.pageText || ''),
      elementCount: dom.interactiveElements?.length || 0,
      cartCount: dom.cartCount || 0,
      timestamp: Date.now(),
    };
  }

  /**
   * Detect what changed after an action
   */
  detectChanges(dom: DOMState): ChangeResult {
    const defaultResult: ChangeResult = {
      urlChanged: false,
      titleChanged: false,
      pageChanged: false,
      elementsChanged: false,
      cartIncremented: false,
      successPattern: null,
      errorPattern: null,
      timeSinceSnapshot: 0,
    };

    if (!this.snapshot) {
      return defaultResult;
    }

    const currentTextHash = this.hashText(dom.pageText || '');
    const pageText = (dom.pageText || '').toLowerCase();

    const result: ChangeResult = {
      urlChanged: dom.url !== this.snapshot.url,
      titleChanged: dom.title !== this.snapshot.title,
      pageChanged: currentTextHash !== this.snapshot.textHash,
      elementsChanged: (dom.interactiveElements?.length || 0) !== this.snapshot.elementCount,
      cartIncremented: (dom.cartCount || 0) > this.snapshot.cartCount,
      successPattern: this.findPattern(pageText, SUCCESS_PATTERNS),
      errorPattern: this.findPattern(pageText, ERROR_PATTERNS),
      timeSinceSnapshot: Date.now() - this.snapshot.timestamp,
    };

    // Clear snapshot after use
    this.snapshot = null;

    return result;
  }

  /**
   * Check if a specific type of change occurred
   */
  hasSignificantChange(changes: ChangeResult): boolean {
    return (
      changes.urlChanged ||
      changes.pageChanged ||
      changes.cartIncremented ||
      changes.successPattern !== null
    );
  }

  /**
   * Check if the action likely succeeded based on changes
   */
  actionLikelySucceeded(
    actionType: string,
    changes: ChangeResult
  ): boolean {
    switch (actionType) {
      case 'navigate':
        return changes.urlChanged;

      case 'type':
        // Typing usually doesn't change URL but might change page content
        return true; // Hard to verify, assume success if no error

      case 'press_enter':
        // Should cause URL or page change (form submit, search)
        return changes.urlChanged || changes.pageChanged;

      case 'click':
        // Should cause some observable change
        return changes.urlChanged || changes.pageChanged || changes.elementsChanged;

      case 'scroll':
        // Scroll might reveal new elements
        return true; // Hard to verify

      default:
        return true;
    }
  }

  /**
   * Get a human-readable description of what changed
   */
  describeChanges(changes: ChangeResult): string {
    const parts: string[] = [];

    if (changes.urlChanged) parts.push('URL changed');
    if (changes.titleChanged) parts.push('title changed');
    if (changes.cartIncremented) parts.push('cart updated');
    if (changes.successPattern) parts.push(`success: "${changes.successPattern}"`);
    if (changes.errorPattern) parts.push(`error: "${changes.errorPattern}"`);

    if (parts.length === 0) {
      if (changes.pageChanged) return 'page content changed';
      if (changes.elementsChanged) return 'elements changed';
      return 'no observable changes';
    }

    return parts.join(', ');
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  /**
   * Simple hash function for text comparison
   */
  private hashText(text: string): number {
    let hash = 0;
    const sample = text.slice(0, 1000); // Only hash first 1000 chars for speed

    for (let i = 0; i < sample.length; i++) {
      const char = sample.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32-bit integer
    }

    return hash;
  }

  /**
   * Find a matching pattern in the page text
   */
  private findPattern(
    pageText: string,
    patternGroups: Record<string, string[]>
  ): string | null {
    for (const [, patterns] of Object.entries(patternGroups)) {
      for (const pattern of patterns) {
        if (pageText.includes(pattern)) {
          return pattern;
        }
      }
    }
    return null;
  }
}

// Export singleton instance
export const changeObserver = new ChangeObserver();
