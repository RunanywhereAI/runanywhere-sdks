/**
 * Amazon State Machine
 *
 * Handles Amazon shopping flows with explicit states and transitions.
 * States:
 * - NAVIGATING: Go to amazon.com
 * - SEARCHING: Find search box, type query, submit
 * - RESULTS: Browse product grid, select best match
 * - PRODUCT_PAGE: View product, find Add to Cart
 * - ADDING_TO_CART: Click add to cart, handle side panel
 * - CART: Verify cart contents
 * - DONE: Task completed
 * - PAUSED: Waiting for user (login, captcha)
 */

import type {
  DOMState,
  NavigatorOutput,
  ObstacleType,
  AgentContext,
} from '../../shared/types';
import {
  AMAZON_SELECTORS,
  AMAZON_URL_PATTERNS,
  AMAZON_OBSTACLE_PATTERNS,
  AMAZON_SUCCESS_PATTERNS,
} from '../../shared/constants';

// ============================================================================
// Types
// ============================================================================

export type AmazonTaskState =
  | 'NAVIGATING'
  | 'SEARCHING'
  | 'RESULTS'
  | 'PRODUCT_PAGE'
  | 'ADDING_TO_CART'
  | 'VERIFYING_CART'
  | 'DONE'
  | 'PAUSED'
  | 'FAILED';

export interface AmazonTaskContext {
  state: AmazonTaskState;
  searchQuery: string;
  previousState?: AmazonTaskState;
  cartCountBefore?: number;
  selectedProduct?: string;
  obstacleType?: ObstacleType;
  retryCount: number;
}

export interface StateTransitionResult {
  action: NavigatorOutput;
  newState?: AmazonTaskState;
  obstacle?: { type: ObstacleType; message: string };
}

// ============================================================================
// Amazon State Machine
// ============================================================================

export class AmazonStateMachine {
  private context: AmazonTaskContext;

  constructor(searchQuery: string) {
    this.context = {
      state: 'NAVIGATING',
      searchQuery,
      retryCount: 0,
    };
  }

  /**
   * Get the current state
   */
  getState(): AmazonTaskState {
    return this.context.state;
  }

  /**
   * Get the search query
   */
  getSearchQuery(): string {
    return this.context.searchQuery;
  }

  /**
   * Process the current DOM state and determine the next action
   */
  process(domState: DOMState, agentContext: AgentContext): StateTransitionResult {
    // First, check for obstacles on any state
    const obstacle = this.detectObstacle(domState);
    if (obstacle) {
      this.context.previousState = this.context.state;
      this.context.state = 'PAUSED';
      this.context.obstacleType = obstacle.type;
      return {
        action: this.createAction('wait', { timeout: '1000' }, `Obstacle detected: ${obstacle.message}`),
        obstacle,
      };
    }

    // Update state based on page state if needed
    this.syncStateWithPage(domState);

    // Process based on current state
    switch (this.context.state) {
      case 'NAVIGATING':
        return this.handleNavigating(domState);
      case 'SEARCHING':
        return this.handleSearching(domState, agentContext);
      case 'RESULTS':
        return this.handleResults(domState);
      case 'PRODUCT_PAGE':
        return this.handleProductPage(domState);
      case 'ADDING_TO_CART':
        return this.handleAddingToCart(domState);
      case 'VERIFYING_CART':
        return this.handleVerifyingCart(domState);
      case 'DONE':
        return {
          action: this.createAction('done', { result: 'Successfully added item to cart' }, 'Task completed'),
        };
      case 'PAUSED':
        return {
          action: this.createAction('wait', { timeout: '2000' }, 'Waiting for user to resolve obstacle'),
        };
      case 'FAILED':
        return {
          action: this.createAction('fail', { reason: 'Unable to complete task' }, 'Task failed'),
        };
      default:
        return this.handleUnknown(domState);
    }
  }

  /**
   * Resume after user resolved an obstacle
   */
  resume(): void {
    if (this.context.state === 'PAUSED' && this.context.previousState) {
      this.context.state = this.context.previousState;
      this.context.previousState = undefined;
      this.context.obstacleType = undefined;
    }
  }

  /**
   * Sync internal state with the detected page state
   */
  private syncStateWithPage(domState: DOMState): void {
    const pageState = domState.pageState;
    if (!pageState) return;

    // If we detect we're on a different page than expected, update state
    switch (pageState) {
      case 'homepage':
        if (this.context.state === 'NAVIGATING') {
          this.context.state = 'SEARCHING';
        }
        break;
      case 'search_results':
        if (this.context.state === 'SEARCHING' || this.context.state === 'NAVIGATING') {
          this.context.state = 'RESULTS';
        }
        break;
      case 'product_page':
        if (this.context.state === 'RESULTS' || this.context.state === 'SEARCHING') {
          this.context.state = 'PRODUCT_PAGE';
        }
        break;
      case 'cart':
        if (this.context.state === 'ADDING_TO_CART') {
          this.context.state = 'VERIFYING_CART';
        }
        break;
    }
  }

  /**
   * Detect obstacles that require user intervention
   */
  private detectObstacle(domState: DOMState): { type: ObstacleType; message: string } | null {
    const pageText = domState.pageText.toLowerCase();
    const url = domState.url;

    // Check for CAPTCHA
    if (domState.pageState === 'captcha' ||
        AMAZON_OBSTACLE_PATTERNS.captcha.some(p => pageText.includes(p))) {
      return { type: 'CAPTCHA', message: 'CAPTCHA detected. Please solve it to continue.' };
    }

    // Check for login required
    if (domState.pageState === 'signin' ||
        (AMAZON_URL_PATTERNS.signin.test(url) &&
         AMAZON_OBSTACLE_PATTERNS.login.some(p => pageText.includes(p)))) {
      return { type: 'LOGIN_REQUIRED', message: 'Login required. Please sign in to continue.' };
    }

    // Check for out of stock (only on product page)
    if (domState.pageState === 'product_page' &&
        AMAZON_OBSTACLE_PATTERNS.outOfStock.some(p => pageText.includes(p))) {
      return { type: 'OUT_OF_STOCK', message: 'Item is currently out of stock.' };
    }

    return null;
  }

  /**
   * Handle NAVIGATING state - go to Amazon
   */
  private handleNavigating(domState: DOMState): StateTransitionResult {
    const url = domState.url;

    // Check if already on Amazon
    if (url.includes('amazon.')) {
      this.context.state = 'SEARCHING';
      return this.handleSearching(domState, {} as AgentContext);
    }

    // Navigate to Amazon
    return {
      action: this.createAction('navigate', { url: 'https://www.amazon.com' }, 'Navigate to Amazon'),
      newState: 'SEARCHING',
    };
  }

  /**
   * Handle SEARCHING state - type query and submit
   */
  private handleSearching(domState: DOMState, agentContext: AgentContext): StateTransitionResult {
    // Check if already searched (on results page)
    if (domState.pageState === 'search_results') {
      this.context.state = 'RESULTS';
      return this.handleResults(domState);
    }

    // Check last action to determine if we already typed
    const lastAction = agentContext.history?.[agentContext.history.length - 1];
    const justTyped = lastAction?.action.action_type === 'type' && lastAction.result.success;
    const justPressedEnter = lastAction?.action.action_type === 'press_enter' && lastAction.result.success;

    if (justPressedEnter) {
      // Wait for results to load
      return {
        action: this.createAction('wait', { timeout: '2000' }, 'Waiting for search results'),
        newState: 'RESULTS',
      };
    }

    if (justTyped) {
      // Press enter to search
      return {
        action: this.createAction('press_enter', { selector: AMAZON_SELECTORS.searchInput }, 'Submit search'),
      };
    }

    // Find search box and type query
    const searchInput = domState.interactiveElements.find(
      el => el.selector === AMAZON_SELECTORS.searchInput ||
            el.selector.includes('twotabsearchtextbox') ||
            el.text.toLowerCase().includes('search')
    );

    if (searchInput) {
      return {
        action: this.createAction('type', {
          selector: searchInput.selector,
          text: this.context.searchQuery,
        }, `Search for "${this.context.searchQuery}"`),
      };
    }

    // Search input not found, might need to wait
    return {
      action: this.createAction('wait', { timeout: '1000' }, 'Waiting for page to load'),
    };
  }

  /**
   * Handle RESULTS state - select a product
   */
  private handleResults(domState: DOMState): StateTransitionResult {
    // Find best matching product
    const product = this.findBestProduct(domState);

    if (product) {
      this.context.selectedProduct = product.text;
      return {
        action: this.createAction('click', { selector: product.selector }, `Select product: ${product.text.slice(0, 50)}`),
        newState: 'PRODUCT_PAGE',
      };
    }

    // No products found, try scrolling
    if (this.context.retryCount < 3) {
      this.context.retryCount++;
      return {
        action: this.createAction('scroll', { direction: 'down', amount: '500' }, 'Scroll to find products'),
      };
    }

    return {
      action: this.createAction('fail', { reason: 'No matching products found' }, 'Failed to find products'),
      newState: 'FAILED',
    };
  }

  /**
   * Handle PRODUCT_PAGE state - add to cart
   */
  private handleProductPage(domState: DOMState): StateTransitionResult {
    // Store cart count before adding
    this.context.cartCountBefore = domState.cartCount;

    // Find Add to Cart button
    const addToCartBtn = domState.interactiveElements.find(
      el => el.selector === AMAZON_SELECTORS.addToCartButton ||
            el.text.toLowerCase().includes('add to cart')
    );

    if (addToCartBtn) {
      return {
        action: this.createAction('click', { selector: addToCartBtn.selector }, 'Add to cart'),
        newState: 'ADDING_TO_CART',
      };
    }

    // Check for "See All Buying Options" (marketplace items)
    const seeOptions = domState.interactiveElements.find(
      el => el.selector === AMAZON_SELECTORS.seeAllBuyingOptions ||
            el.text.toLowerCase().includes('see all buying options')
    );

    if (seeOptions) {
      return {
        action: this.createAction('click', { selector: seeOptions.selector }, 'See buying options'),
      };
    }

    // Add to cart button not found
    return {
      action: this.createAction('scroll', { direction: 'down', amount: '300' }, 'Scroll to find Add to Cart'),
    };
  }

  /**
   * Handle ADDING_TO_CART state - verify item was added
   */
  private handleAddingToCart(domState: DOMState): StateTransitionResult {
    const pageText = domState.pageText.toLowerCase();
    const alerts = domState.alerts || [];

    // Check for success indicators
    const addedToCart = AMAZON_SUCCESS_PATTERNS.addedToCart.some(
      p => pageText.includes(p) || alerts.some(a => a.toLowerCase().includes(p))
    );

    // Check if cart count increased
    const cartIncreased = domState.cartCount !== undefined &&
                          this.context.cartCountBefore !== undefined &&
                          domState.cartCount > this.context.cartCountBefore;

    if (addedToCart || cartIncreased) {
      return {
        action: this.createAction('done', {
          result: `Successfully added "${this.context.selectedProduct?.slice(0, 50) || 'item'}" to cart`,
        }, 'Task completed'),
        newState: 'DONE',
      };
    }

    // Check for side panel "View Cart" button
    const viewCart = domState.interactiveElements.find(
      el => el.selector === AMAZON_SELECTORS.sideCartViewCart ||
            el.text.toLowerCase().includes('view cart') ||
            el.text.toLowerCase().includes('go to cart')
    );

    if (viewCart) {
      // Item was added, task is done
      return {
        action: this.createAction('done', {
          result: `Successfully added "${this.context.selectedProduct?.slice(0, 50) || 'item'}" to cart`,
        }, 'Item added to cart'),
        newState: 'DONE',
      };
    }

    // Wait for confirmation
    if (this.context.retryCount < 5) {
      this.context.retryCount++;
      return {
        action: this.createAction('wait', { timeout: '1000' }, 'Waiting for cart confirmation'),
      };
    }

    // Assume it worked if we've waited enough
    return {
      action: this.createAction('done', {
        result: 'Item may have been added to cart (no confirmation received)',
      }, 'Task completed with uncertainty'),
      newState: 'DONE',
    };
  }

  /**
   * Handle VERIFYING_CART state - confirm cart contents
   */
  private handleVerifyingCart(domState: DOMState): StateTransitionResult {
    // On cart page, check if item is there
    const pageText = domState.pageText.toLowerCase();
    const query = this.context.searchQuery.toLowerCase();
    const words = query.split(/\s+/).filter(w => w.length > 3);

    const itemInCart = words.some(word => pageText.includes(word));

    if (itemInCart || domState.cartCount && domState.cartCount > 0) {
      return {
        action: this.createAction('done', { result: 'Item is in cart' }, 'Cart verified'),
        newState: 'DONE',
      };
    }

    return {
      action: this.createAction('fail', { reason: 'Item not found in cart' }, 'Cart verification failed'),
      newState: 'FAILED',
    };
  }

  /**
   * Handle unknown state - try to recover
   */
  private handleUnknown(domState: DOMState): StateTransitionResult {
    // Try to determine state from page
    if (domState.pageState) {
      switch (domState.pageState) {
        case 'homepage':
          this.context.state = 'SEARCHING';
          return this.handleSearching(domState, {} as AgentContext);
        case 'search_results':
          this.context.state = 'RESULTS';
          return this.handleResults(domState);
        case 'product_page':
          this.context.state = 'PRODUCT_PAGE';
          return this.handleProductPage(domState);
        case 'cart':
          this.context.state = 'VERIFYING_CART';
          return this.handleVerifyingCart(domState);
      }
    }

    // Default: go to Amazon and start over
    this.context.state = 'NAVIGATING';
    return this.handleNavigating(domState);
  }

  /**
   * Find the best matching product from search results
   */
  private findBestProduct(domState: DOMState): { selector: string; text: string } | null {
    const queryWords = this.context.searchQuery.toLowerCase().split(/\s+/).filter(w => w.length > 2);

    // Filter to product links (those with prices or product-like text)
    const products = domState.interactiveElements.filter(el => {
      if (el.tag !== 'a') return false;
      if (el.text.length < 10) return false;
      // Skip navigation/filter links
      if (el.text.toLowerCase().includes('filter') ||
          el.text.toLowerCase().includes('sort by') ||
          el.text.toLowerCase().includes('department')) return false;
      return true;
    });

    // Score products by query match
    const scored = products.map(el => {
      const text = el.text.toLowerCase();
      const matchCount = queryWords.filter(word => text.includes(word)).length;
      return { ...el, score: matchCount };
    });

    // Sort by score descending
    scored.sort((a, b) => b.score - a.score);

    // Return best match if it has any matches
    if (scored.length > 0 && scored[0].score > 0) {
      return { selector: scored[0].selector, text: scored[0].text };
    }

    // Fallback: first product-like link
    if (products.length > 0) {
      return { selector: products[0].selector, text: products[0].text };
    }

    return null;
  }

  /**
   * Create a NavigatorOutput action
   */
  private createAction(
    type: string,
    params: Record<string, string>,
    thought: string
  ): NavigatorOutput {
    return {
      current_state: {
        page_summary: `State: ${this.context.state}`,
        relevant_elements: [],
        progress: thought,
      },
      action: {
        thought,
        action_type: type as any,
        parameters: params,
      },
    };
  }
}

/**
 * Extract search query from task description
 */
export function extractSearchQuery(task: string): string | null {
  // Patterns to extract what to search for
  const patterns = [
    /(?:add|buy|order|search for|find|get)\s+(.+?)\s+(?:to cart|on amazon|from amazon|to my cart)/i,
    /(?:add|buy|order|search for|find|get)\s+(.+?)\s+(?:on|from)\s+amazon/i,
    /(?:add|buy|order)\s+(.+)/i,
    /(?:search for|find|look for)\s+(.+)/i,
  ];

  for (const pattern of patterns) {
    const match = task.match(pattern);
    if (match && match[1]) {
      // Clean up the query
      return match[1]
        .replace(/\s+/g, ' ')
        .replace(/^(a|an|the|some)\s+/i, '')
        .trim();
    }
  }

  return null;
}

/**
 * Check if a task is an Amazon shopping task
 */
export function isAmazonTask(task: string): boolean {
  const taskLower = task.toLowerCase();
  return (
    taskLower.includes('amazon') ||
    (taskLower.includes('add') && taskLower.includes('cart')) ||
    (taskLower.includes('buy') && !taskLower.includes('flight')) ||
    (taskLower.includes('order') && !taskLower.includes('food') && !taskLower.includes('doordash'))
  );
}
