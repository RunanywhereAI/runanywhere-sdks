/**
 * Navigator Agent
 *
 * Tactical execution agent with rule-based fallback for small LLMs.
 * Enhanced with Amazon-specific rules and better product selection.
 */

import { BaseAgent } from './base-agent';
import type { NavigatorOutput, DOMState, AgentContext, InteractiveElement } from '../../shared/types';
import {
  AMAZON_SELECTORS,
  AMAZON_SUCCESS_PATTERNS,
} from '../../shared/constants';

// Site patterns
const SITES: Record<string, string> = {
  'amazon': 'https://www.amazon.com',
  'youtube': 'https://www.youtube.com',
  'doordash': 'https://www.doordash.com',
  'google flights': 'https://www.google.com/travel/flights',
  'google': 'https://www.google.com',
  'ebay': 'https://www.ebay.com',
  'walmart': 'https://www.walmart.com',
  'netflix': 'https://www.netflix.com',
  'twitter': 'https://twitter.com',
  'x.com': 'https://x.com',
  'reddit': 'https://www.reddit.com',
  'facebook': 'https://www.facebook.com',
  'instagram': 'https://www.instagram.com',
  'linkedin': 'https://www.linkedin.com',
  'github': 'https://www.github.com',
};

export class NavigatorAgent extends BaseAgent<NavigatorOutput> {
  protected systemPrompt = `Browser automation agent. Pick ONE action based on the page.

Actions: navigate, type, press_enter, click, scroll, wait, done, fail

Rules:
- Not on target site? Use navigate
- Need to search? Use type then press_enter
- See "Added to Cart"? Use done
- See the button you need? Use click`;

  protected outputSchema = `{"action":"<action_type>","params":{"<key>":"<value>"},"reason":"<why>"}`;

  private static VALID_ACTIONS = ['navigate', 'click', 'type', 'press_enter', 'scroll', 'wait', 'done', 'fail'];
  private static BAD_PATTERNS = ['div.s-result-item', 'Found product, clicking', 'Click first product'];

  constructor() {
    super('Navigator');
  }

  async getNextAction(context: AgentContext, domState: DOMState): Promise<NavigatorOutput> {
    // Try rules first - this is called by executor as fallback after state machines
    const ruleAction = this.applyRules(context, domState);
    if (ruleAction) {
      console.log('[Navigator] Rule-based:', ruleAction.action.action_type);
      return ruleAction;
    }

    // VLM removed from hot path - only used for error recovery via getRecoveryHint()

    // Build execution history summary (last 5 actions)
    const historyLines = context.history.slice(-5).map((h, i) => {
      const params = Object.values(h.action.parameters || {}).join(', ').slice(0, 30);
      return `${i + 1}. ${h.action.action_type}(${params}) → ${h.result.success ? 'OK' : 'FAILED'}`;
    }).join('\n');

    // Include more elements (up to 30) since we have more context budget now
    const els = domState.interactiveElements.slice(0, 30)
      .map((el, i) => `[${i}] ${el.tag} "${el.text.slice(0, 40)}" ${el.selector}`)
      .join('\n');

    // Enhanced prompt with history and better context
    const prompt = `Task: ${context.task}
URL: ${domState.url}
Page: ${domState.title}

RECENT ACTIONS:
${historyLines || 'None yet'}

ELEMENTS (${domState.interactiveElements.length} total):
${els}

Pick ONE action. Consider what was already tried. JSON only:
{"action":"navigate|click|type|press_enter|scroll|done|fail","params":{...},"reason":"..."}`;

    try {
      const rawResult = await this.invoke(prompt) as { action: string; params: Record<string, string>; reason: string };

      // Convert simplified format to NavigatorOutput
      const result: NavigatorOutput = {
        current_state: {
          page_summary: domState.title || 'Current page',
          relevant_elements: [],
          progress: rawResult.reason || 'Processing',
        },
        action: {
          thought: rawResult.reason || '',
          action_type: rawResult.action as any,
          parameters: rawResult.params || {},
        },
      };

      return this.validate(result, context, domState);
    } catch (e) {
      console.error('[Navigator] LLM error, fallback:', e);
      return this.fallback(context, domState);
    }
  }

  // Helper: Check if we're on the target site
  private isOnSite(url: string, targetSite: string): boolean {
    if (!url || !targetSite) return false;
    try {
      const current = new URL(url).hostname.replace(/^www\./, '');
      const target = new URL(targetSite).hostname.replace(/^www\./, '');
      return current === target || current.endsWith('.' + target);
    } catch {
      return false;
    }
  }

  // Helper: Check if we typed but haven't submitted yet
  private needsSubmit(history: AgentContext['history']): boolean {
    if (history.length === 0) return false;
    const last = history[history.length - 1];
    return last.action.action_type === 'type' && last.result.success;
  }

  // Helper: Check if search was submitted (typed AND pressed enter)
  private hasSubmittedSearch(history: AgentContext['history']): boolean {
    let typed = false;
    let submitted = false;
    for (const h of history) {
      if (h.action.action_type === 'type' && h.result.success) typed = true;
      if (h.action.action_type === 'press_enter' && h.result.success && typed) submitted = true;
    }
    return submitted;
  }

  /**
   * Apply rule-based action selection. Public so executor can call directly.
   */
  applyRules(ctx: AgentContext, dom: DOMState): NavigatorOutput | null {
    const task = ctx.task.toLowerCase();
    const url = dom.url || '';
    const page = dom.pageText?.toLowerCase() || '';

    // Rule: Restricted page -> navigate
    if (!url || url.startsWith('chrome://') || url.startsWith('about:') || url === 'chrome://newtab/') {
      const target = this.findSite(task);
      if (target) return this.act('navigate', { url: target }, 'Go to site');
    }

    // Rule: Task done
    if (this.isDone(task, page, ctx.history)) {
      return this.act('done', { result: 'Task completed' }, 'Done');
    }

    // Rule: Not on target site (FIXED: proper hostname comparison)
    const site = this.findSite(task);
    if (site && !this.isOnSite(url, site)) {
      return this.act('navigate', { url: site }, 'Navigate to site');
    }

    // Rule: Just typed -> press enter to submit
    if (this.needsSubmit(ctx.history)) {
      const box = this.findSearch(dom);
      if (box) {
        return this.act('press_enter', { selector: box.selector }, 'Submit search');
      }
    }

    // Rule: Need to search (haven't typed yet)
    const query = this.getQuery(task);
    if (query && !this.hasSubmittedSearch(ctx.history)) {
      const box = this.findSearch(dom);
      if (box) {
        // Check if we already typed
        const alreadyTyped = ctx.history.some(h =>
          h.action.action_type === 'type' && h.result.success
        );
        if (!alreadyTyped) {
          return this.act('type', { selector: box.selector, text: query }, 'Type search');
        }
      }
    }

    // ========== YouTube Rules ==========
    if (url.includes('youtube.com')) {
      // On YouTube search results - click first video
      if (url.includes('/results') || url.includes('search_query')) {
        const video = dom.interactiveElements.find(e =>
          e.tag === 'a' && e.selector.includes('video-title') ||
          (e.tag === 'a' && e.text.length > 10 && !e.text.toLowerCase().includes('filter'))
        );
        if (video) return this.act('click', { selector: video.selector }, 'Click video');
      }

      // On video page - task complete for "play/watch" tasks
      if (url.includes('/watch') && (task.includes('play') || task.includes('watch') || task.includes('video'))) {
        return this.act('done', { result: 'Video playing' }, 'Done');
      }
    }

    // ========== Amazon Rules ==========
    // On results, click product
    if ((url.includes('/s?') || url.includes('search')) && task.includes('cart')) {
      const link = this.findProduct(dom, task);
      if (link) return this.act('click', { selector: link.selector }, 'Click product');
    }

    // On product page, add to cart
    if (url.includes('/dp/') || page.includes('add to cart')) {
      const btn = this.findCartBtn(dom);
      if (btn) return this.act('click', { selector: btn.selector }, 'Add to cart');
    }

    // ========== Google Rules ==========
    if (url.includes('google.com')) {
      // On search results - click first result
      if (url.includes('/search')) {
        const result = dom.interactiveElements.find(e =>
          e.tag === 'a' && e.text.length > 10 &&
          !e.text.toLowerCase().includes('sponsored') &&
          !e.selector.includes('related')
        );
        if (result && task.includes('click')) {
          return this.act('click', { selector: result.selector }, 'Click result');
        }
        // Search done
        if (!task.includes('click')) {
          return this.act('done', { result: 'Search results shown' }, 'Done');
        }
      }
    }

    // ========== Generic click rules ==========
    // If task mentions clicking something specific
    const clickMatch = task.match(/click\s+(?:on\s+)?(?:the\s+)?["']?([^"']+)["']?/i);
    if (clickMatch) {
      const target = clickMatch[1].toLowerCase();
      const el = dom.interactiveElements.find(e =>
        e.text.toLowerCase().includes(target) ||
        e.selector.toLowerCase().includes(target)
      );
      if (el) return this.act('click', { selector: el.selector }, `Click ${target}`);
    }

    return null;
  }

  private validate(out: NavigatorOutput, ctx: AgentContext, dom: DOMState): NavigatorOutput {
    // Check for example copying
    const str = JSON.stringify(out);
    if (NavigatorAgent.BAD_PATTERNS.some(p => str.includes(p))) {
      console.warn('[Navigator] Detected example copy');
      return this.fallback(ctx, dom);
    }

    // Check valid action
    if (!out?.action?.action_type || !NavigatorAgent.VALID_ACTIONS.includes(out.action.action_type)) {
      console.warn('[Navigator] Invalid action');
      return this.fallback(ctx, dom);
    }

    // Validate required parameters for each action type
    const params = out.action.parameters || {};
    const actionType = out.action.action_type;

    if (actionType === 'navigate' && !params.url) {
      console.warn('[Navigator] Navigate action missing URL, using fallback');
      return this.fallback(ctx, dom);
    }

    if (actionType === 'click' && !params.selector) {
      console.warn('[Navigator] Click action missing selector, using fallback');
      return this.fallback(ctx, dom);
    }

    if (actionType === 'type' && (!params.selector || !params.text)) {
      console.warn('[Navigator] Type action missing selector or text, using fallback');
      return this.fallback(ctx, dom);
    }

    // Check task done
    if (this.isDone(ctx.task.toLowerCase(), dom.pageText?.toLowerCase() || '', ctx.history)) {
      return this.act('done', { result: 'Task completed' }, 'Done');
    }

    return out;
  }

  private fallback(ctx: AgentContext, dom: DOMState): NavigatorOutput {
    const rule = this.applyRules(ctx, dom);
    if (rule) return rule;

    // Try clicking something relevant
    const words = ctx.task.toLowerCase().split(/\s+/).filter(w => w.length > 3);
    for (const el of dom.interactiveElements) {
      if (words.some(w => el.text.toLowerCase().includes(w))) {
        return this.act('click', { selector: el.selector }, 'Click relevant element');
      }
    }

    if (dom.interactiveElements.length > 0) {
      return this.act('scroll', { direction: 'down', amount: '500' }, 'Scroll for more');
    }

    return this.act('fail', { reason: 'No actionable elements' }, 'Cannot proceed');
  }

  // Helpers
  private findSite(task: string): string | null {
    for (const [k, v] of Object.entries(SITES)) {
      if (task.includes(k)) return v;
    }
    const m = task.match(/(?:go to|visit)\s+([\w.-]+\.[a-z]{2,})/i);
    return m ? `https://${m[1]}` : null;
  }

  private getQuery(task: string): string | null {
    const m = task.match(/(?:search|find|order|buy|add)\s+(.+?)(?:\s+(?:on|from|to cart)|\s*$)/i);
    return m ? m[1].trim() : null;
  }

  private searched(hist: AgentContext['history'], q: string): boolean {
    return hist.some(h => h.action.action_type === 'type' && h.action.parameters.text?.includes(q.slice(0, 8)) && h.result.success);
  }

  private findSearch(dom: DOMState): InteractiveElement | null {
    // Priority 1: Amazon's specific search input
    const amazonSearch = dom.interactiveElements.find(
      e => e.selector === AMAZON_SELECTORS.searchInput ||
           e.selector.includes('twotabsearchtextbox')
    );
    if (amazonSearch) return amazonSearch;

    // Priority 2: Common search selectors
    const sels = ['search', 'field-keywords', 'nav-search', 'searchbox'];
    for (const s of sels) {
      const el = dom.interactiveElements.find(e => e.selector.toLowerCase().includes(s));
      if (el) return el;
    }

    // Priority 3: Any input with search-like attributes
    return dom.interactiveElements.find(
      e => e.tag === 'input' &&
           (e.text.toLowerCase().includes('search') ||
            e.selector.toLowerCase().includes('search') ||
            e.attributes?.placeholder?.toLowerCase().includes('search'))
    ) || null;
  }

  private findProduct(dom: DOMState, task: string): InteractiveElement | null {
    const q = this.getQuery(task)?.toLowerCase().split(/\s+/).filter(w => w.length > 2) || [];

    // Filter to product links
    const links = dom.interactiveElements.filter(e => {
      if (e.tag !== 'a') return false;
      if (e.text.length < 10) return false;

      // Skip sponsored products
      const textLower = e.text.toLowerCase();
      if (textLower.includes('sponsored')) return false;

      // Skip navigation/filter links
      if (textLower.includes('filter') ||
          textLower.includes('sort by') ||
          textLower.includes('department') ||
          textLower.includes('see more') ||
          textLower.includes('see all')) return false;

      return true;
    });

    if (q.length && links.length) {
      // Score products by query match
      const scored = links.map(e => {
        const text = e.text.toLowerCase();
        const matchCount = q.filter(word => text.includes(word)).length;
        // Bonus for exact phrase match
        const queryPhrase = q.join(' ');
        const phraseBonus = text.includes(queryPhrase) ? 2 : 0;
        return { e, score: matchCount + phraseBonus };
      });

      scored.sort((a, b) => b.score - a.score);

      // Return best match if it has any matches
      if (scored[0]?.score > 0) return scored[0].e;
    }

    // Fallback: first product-like link
    return links[0] || null;
  }

  private findCartBtn(dom: DOMState): InteractiveElement | null {
    // Priority 1: Amazon's specific Add to Cart button
    const amazonCart = dom.interactiveElements.find(
      e => e.selector === AMAZON_SELECTORS.addToCartButton ||
           e.selector.includes('add-to-cart')
    );
    if (amazonCart) return amazonCart;

    // Priority 2: Common patterns
    const pats = ['add-to-cart', 'addtocart', 'add to cart', 'add_to_cart'];
    for (const p of pats) {
      const el = dom.interactiveElements.find(
        e => e.selector.toLowerCase().includes(p) ||
             e.text.toLowerCase().includes(p)
      );
      if (el) return el;
    }

    // Priority 3: Buy Now as fallback
    const buyNow = dom.interactiveElements.find(
      e => e.selector === AMAZON_SELECTORS.buyNowButton ||
           e.text.toLowerCase().includes('buy now')
    );
    if (buyNow) return buyNow;

    return null;
  }

  private isDone(task: string, page: string, hist: AgentContext['history']): boolean {
    const url = hist[hist.length - 1]?.action.parameters?.url || '';

    // Cart tasks
    const isCartTask = (task.includes('add') && task.includes('cart')) || task.includes('order');
    if (isCartTask) {
      for (const pattern of AMAZON_SUCCESS_PATTERNS.addedToCart) {
        if (page.includes(pattern)) return true;
      }
      if (page.includes('proceed to checkout') ||
          page.includes('go to cart') ||
          page.includes('view cart') ||
          page.includes('1 item added')) {
        return true;
      }
    }

    // YouTube video tasks
    if (task.includes('youtube') && (task.includes('play') || task.includes('watch') || task.includes('video'))) {
      if (page.includes('subscribe') && page.includes('share')) return true; // On video page
    }

    // Search tasks (just need to show results)
    if (task.includes('search') && !task.includes('click')) {
      if (page.includes('results') || page.includes('showing')) return true;
    }

    return false;
  }

  /**
   * Get VLM hint for error recovery (only called when stuck)
   */
  async getRecoveryHint(dom: DOMState, failureCount: number): Promise<string | null> {
    // Only use VLM after multiple failures and if screenshot available
    if (failureCount < 2 || !dom.screenshot) return null;

    try {
      const response = await chrome.runtime.sendMessage({
        type: 'VLM_DESCRIBE',
        imageData: dom.screenshot,
        prompt: 'List the main interactive elements visible on this page (buttons, links, inputs). Be brief.',
      });
      return response?.description || null;
    } catch {
      return null;
    }
  }

  private act(type: string, params: Record<string, string>, thought: string): NavigatorOutput {
    return {
      current_state: {
        page_summary: 'Current page',
        relevant_elements: [],
        progress: thought,
      },
      action: { thought, action_type: type as any, parameters: params },
    };
  }
}
