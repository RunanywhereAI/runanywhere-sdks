/**
 * DOM Observer
 *
 * Serializes the current page state for the Navigator agent.
 * Extracts:
 * - Interactive elements (links, buttons, inputs, etc.)
 * - Page text content
 * - URL and title
 * - Amazon-specific page state and indicators
 */

import type { DOMState, InteractiveElement, AmazonPageState } from '../shared/types';
import {
  INTERACTIVE_SELECTORS,
  MAX_INTERACTIVE_ELEMENTS,
  MAX_PAGE_TEXT_LENGTH,
  AMAZON_URL_PATTERNS,
  AMAZON_SELECTORS,
} from '../shared/constants';

// ============================================================================
// DOM Serialization
// ============================================================================

/**
 * Serialize the current DOM state for agent consumption
 */
export function serializeDOMState(): DOMState {
  const url = window.location.href;
  const isAmazon = url.includes('amazon.');
  const isYouTube = url.includes('youtube.com');

  // Site-specific element extraction
  let interactiveElements: InteractiveElement[];
  if (isYouTube) {
    interactiveElements = extractYouTubeElements();
  } else if (isAmazon) {
    interactiveElements = extractAmazonElements();
  } else {
    interactiveElements = extractInteractiveElements();
  }
  const pageText = extractVisibleText();

  const state: DOMState = {
    url,
    title: document.title,
    interactiveElements,
    pageText,
  };

  // Add Amazon-specific information
  if (isAmazon) {
    state.pageState = detectAmazonPageState(url);
    state.cartCount = getCartCount();
    state.alerts = extractAlerts();
  }

  return state;
}

/**
 * Detect the current Amazon page state from URL and page content
 */
function detectAmazonPageState(url: string): AmazonPageState {
  // Check for CAPTCHA first (form-based detection, no URL pattern)
  if (document.querySelector(AMAZON_SELECTORS.captchaForm)) {
    return 'captcha';
  }
  if (AMAZON_URL_PATTERNS.signin.test(url) || document.querySelector(AMAZON_SELECTORS.signinForm)) {
    return 'signin';
  }
  if (AMAZON_URL_PATTERNS.checkout.test(url)) {
    return 'checkout';
  }
  if (AMAZON_URL_PATTERNS.cart.test(url)) {
    return 'cart';
  }
  if (AMAZON_URL_PATTERNS.product.test(url)) {
    return 'product_page';
  }
  if (AMAZON_URL_PATTERNS.search.test(url)) {
    return 'search_results';
  }
  if (AMAZON_URL_PATTERNS.homepage.test(url)) {
    return 'homepage';
  }
  return 'unknown';
}

/**
 * Get the current cart count from Amazon nav
 */
function getCartCount(): number {
  const cartEl = document.querySelector(AMAZON_SELECTORS.cartCount);
  if (cartEl) {
    const count = parseInt(cartEl.textContent || '0', 10);
    return isNaN(count) ? 0 : count;
  }
  return 0;
}

/**
 * Extract alert/notification messages from the page
 */
function extractAlerts(): string[] {
  const alerts: string[] = [];

  // Check for common alert selectors
  const alertSelectors = [
    '.a-alert-content',
    '[role="alert"]',
    '.message-error',
    '.message-success',
    '#NATC_SMART_WAGON_CONF_MSG_SUCCESS',
    '.a-box-inner.a-alert-container',
  ];

  for (const selector of alertSelectors) {
    const elements = document.querySelectorAll(selector);
    elements.forEach((el) => {
      const text = (el as HTMLElement).innerText?.trim();
      if (text && text.length < 200) {
        alerts.push(text);
      }
    });
  }

  return alerts.slice(0, 5); // Limit to 5 alerts
}

/**
 * Extract Amazon-specific interactive elements with priority
 */
function extractAmazonElements(): InteractiveElement[] {
  const elements: InteractiveElement[] = [];
  let index = 0;

  // Priority 1: Key action elements (search, add to cart, etc.)
  const prioritySelectors = [
    AMAZON_SELECTORS.searchInput,
    AMAZON_SELECTORS.searchButton,
    AMAZON_SELECTORS.addToCartButton,
    AMAZON_SELECTORS.buyNowButton,
    AMAZON_SELECTORS.sideCartViewCart,
    AMAZON_SELECTORS.seeAllBuyingOptions,
  ];

  for (const selector of prioritySelectors) {
    const node = document.querySelector(selector);
    if (node && node instanceof HTMLElement && isVisible(node)) {
      elements.push({
        index: index++,
        tag: node.tagName.toLowerCase(),
        type: getInputType(node),
        text: getElementText(node),
        selector: selector, // Use the known selector
        attributes: extractRelevantAttributes(node),
      });
    }
  }

  // Priority 2: Product cards on search results (first 10 non-sponsored)
  const productCards = document.querySelectorAll(AMAZON_SELECTORS.productCard);
  let productCount = 0;

  productCards.forEach((card) => {
    if (productCount >= 10) return;
    if (!(card instanceof HTMLElement)) return;

    // Skip sponsored products
    const sponsored = card.querySelector(AMAZON_SELECTORS.sponsoredLabel);
    if (sponsored) return;

    // Find the main product link
    const link = card.querySelector(AMAZON_SELECTORS.productTitle);
    if (link && link instanceof HTMLElement && isVisible(link)) {
      const priceEl = card.querySelector(AMAZON_SELECTORS.productPrice);
      const price = priceEl?.textContent?.trim() || '';

      elements.push({
        index: index++,
        tag: 'a',
        text: `${getElementText(link)}${price ? ` - ${price}` : ''}`,
        selector: generateSelector(link),
        attributes: extractRelevantAttributes(link),
      });
      productCount++;
    }
  });

  // Priority 3: Other interactive elements (standard extraction)
  const standardElements = extractInteractiveElements();

  // Add remaining elements that aren't already in the list
  const existingSelectors = new Set(elements.map((e) => e.selector));
  for (const el of standardElements) {
    if (!existingSelectors.has(el.selector) && elements.length < MAX_INTERACTIVE_ELEMENTS) {
      elements.push({ ...el, index: index++ });
    }
  }

  return elements;
}

// ============================================================================
// YouTube-Specific Extraction
// ============================================================================

/**
 * Extract YouTube-specific interactive elements with priority
 * YouTube uses web components that standard querySelectorAll may miss
 */
function extractYouTubeElements(): InteractiveElement[] {
  const elements: InteractiveElement[] = [];
  let index = 0;

  // Priority 1: Search box
  const searchInput = document.querySelector('input#search') as HTMLInputElement | null;
  if (searchInput && isVisible(searchInput)) {
    elements.push({
      index: index++,
      tag: 'input',
      type: 'search',
      text: searchInput.placeholder || 'Search',
      selector: 'input#search',
      attributes: { placeholder: searchInput.placeholder || 'Search' },
    });
  }

  // Priority 2: Video title links on search results / homepage
  // YouTube renders these directly (not in shadow DOM), just nested deep
  const videoRenderers = document.querySelectorAll('ytd-video-renderer, ytd-rich-item-renderer, ytd-compact-video-renderer');

  videoRenderers.forEach((renderer) => {
    if (elements.length >= MAX_INTERACTIVE_ELEMENTS) return;

    // Find the video title link
    const titleLink = renderer.querySelector('a#video-title') as HTMLAnchorElement | null ||
                      renderer.querySelector('a#video-title-link') as HTMLAnchorElement | null ||
                      renderer.querySelector('a[href*="/watch"]') as HTMLAnchorElement | null;

    if (titleLink && isVisible(titleLink)) {
      const text = titleLink.textContent?.trim() || 'Video';
      const href = titleLink.getAttribute('href') || '';

      // Generate a unique selector
      const selector = generateYouTubeVideoSelector(renderer, index);

      elements.push({
        index: index++,
        tag: 'a',
        type: 'video-link',
        text: text.slice(0, 100),
        selector,
        attributes: { href },
      });
    }
  });

  // Priority 3: Search button
  const searchButton = document.querySelector('#search-icon-legacy, button#search-icon-legacy') as HTMLElement | null;
  if (searchButton && isVisible(searchButton)) {
    elements.push({
      index: index++,
      tag: 'button',
      text: 'Search',
      selector: '#search-icon-legacy',
      attributes: {},
    });
  }

  // Priority 4: Other interactive elements (standard extraction)
  const standardElements = extractInteractiveElements();

  // Add remaining elements that aren't duplicates
  const existingSelectors = new Set(elements.map((e) => e.selector));
  for (const el of standardElements) {
    if (!existingSelectors.has(el.selector) && elements.length < MAX_INTERACTIVE_ELEMENTS) {
      elements.push({ ...el, index: index++ });
    }
  }

  return elements.slice(0, MAX_INTERACTIVE_ELEMENTS).map((el, i) => ({ ...el, index: i }));
}

/**
 * Generate a reliable selector for YouTube video elements
 */
function generateYouTubeVideoSelector(renderer: Element, index: number): string {
  // Try to use video-title ID which is consistent
  const titleLink = renderer.querySelector('a#video-title') ||
                    renderer.querySelector('a#video-title-link');

  if (titleLink) {
    // Get the href to make a unique selector
    const href = titleLink.getAttribute('href');
    if (href) {
      return `a[href="${CSS.escape(href)}"]`;
    }
  }

  // Fallback: Use nth-of-type on the renderer
  const tagName = renderer.tagName.toLowerCase();
  const parent = renderer.parentElement;
  if (parent) {
    const siblings = Array.from(parent.children).filter(
      (el) => el.tagName.toLowerCase() === tagName
    );
    const position = siblings.indexOf(renderer) + 1;
    return `${tagName}:nth-of-type(${position}) a#video-title`;
  }

  return `a[href*="/watch"]:nth-of-type(${index + 1})`;
}

// ============================================================================
// Interactive Elements Extraction
// ============================================================================

/**
 * Extract all interactive elements from the page
 */
function extractInteractiveElements(): InteractiveElement[] {
  const elements: InteractiveElement[] = [];
  const selector = INTERACTIVE_SELECTORS.join(', ');
  const nodes = document.querySelectorAll(selector);

  let index = 0;

  nodes.forEach((node) => {
    if (!(node instanceof HTMLElement)) return;

    // Skip hidden elements
    if (!isVisible(node)) return;

    // Skip very small elements (likely icons or hidden)
    const rect = node.getBoundingClientRect();
    if (rect.width < 10 || rect.height < 10) return;

    // Skip elements far outside viewport (with margin for scrollable content)
    const viewportHeight = window.innerHeight;
    if (rect.bottom < -500 || rect.top > viewportHeight + 500) return;

    // Skip if max elements reached
    if (index >= MAX_INTERACTIVE_ELEMENTS * 2) return; // Collect more than needed, will filter later

    const element: InteractiveElement = {
      index: index++,
      tag: node.tagName.toLowerCase(),
      type: getInputType(node),
      text: getElementText(node),
      selector: generateSelector(node),
      attributes: extractRelevantAttributes(node),
    };

    elements.push(element);
  });

  // Prioritize elements in viewport
  const inViewport: InteractiveElement[] = [];
  const outsideViewport: InteractiveElement[] = [];

  elements.forEach((el) => {
    const node = document.querySelector(el.selector);
    if (node) {
      const rect = node.getBoundingClientRect();
      if (rect.top >= 0 && rect.bottom <= window.innerHeight) {
        inViewport.push(el);
      } else {
        outsideViewport.push(el);
      }
    }
  });

  // Return viewport elements first, then outside
  const result = [...inViewport, ...outsideViewport].slice(0, MAX_INTERACTIVE_ELEMENTS);

  // Re-index for agent clarity
  return result.map((el, i) => ({ ...el, index: i }));
}

/**
 * Check if an element is visible
 */
function isVisible(element: HTMLElement): boolean {
  const style = window.getComputedStyle(element);

  if (style.display === 'none') return false;
  if (style.visibility === 'hidden') return false;
  if (style.opacity === '0') return false;

  // Check if element or ancestor has hidden attribute
  if (element.hidden) return false;
  if (element.closest('[hidden]')) return false;

  return true;
}

/**
 * Get input type for form elements
 */
function getInputType(element: HTMLElement): string | undefined {
  if (element instanceof HTMLInputElement) {
    return element.type || 'text';
  }
  if (element instanceof HTMLTextAreaElement) {
    return 'textarea';
  }
  if (element instanceof HTMLSelectElement) {
    return 'select';
  }
  return undefined;
}

/**
 * Get meaningful text from an element
 */
function getElementText(element: HTMLElement): string {
  // For inputs, get placeholder, value, or label
  if (element instanceof HTMLInputElement) {
    if (element.placeholder) return element.placeholder;
    if (element.value && element.type !== 'password') return element.value;

    // Try to find associated label
    const label = findLabel(element);
    if (label) return label;

    return element.name || element.id || '';
  }

  if (element instanceof HTMLTextAreaElement) {
    if (element.placeholder) return element.placeholder;

    const label = findLabel(element);
    if (label) return label;

    return element.name || '';
  }

  if (element instanceof HTMLSelectElement) {
    const selected = element.options[element.selectedIndex];
    if (selected) return selected.text;

    const label = findLabel(element);
    if (label) return label;

    return element.name || '';
  }

  // For other elements, get inner text
  const text = element.innerText || element.textContent || '';
  return text.trim().replace(/\s+/g, ' ').slice(0, 100);
}

/**
 * Find label text for a form element
 */
function findLabel(element: HTMLElement): string {
  // Check for aria-label
  const ariaLabel = element.getAttribute('aria-label');
  if (ariaLabel) return ariaLabel;

  // Check for associated label element
  const id = element.id;
  if (id) {
    const label = document.querySelector(`label[for="${id}"]`);
    if (label) return label.textContent?.trim() || '';
  }

  // Check for parent label
  const parentLabel = element.closest('label');
  if (parentLabel) {
    return parentLabel.textContent?.trim() || '';
  }

  return '';
}

/**
 * Generate a unique CSS selector for an element
 */
function generateSelector(element: HTMLElement): string {
  // Strategy 1: ID (most reliable)
  if (element.id) {
    // Validate the ID is usable
    if (/^[a-zA-Z][\w-]*$/.test(element.id)) {
      return `#${element.id}`;
    }
    // Use attribute selector for complex IDs
    return `[id="${CSS.escape(element.id)}"]`;
  }

  // Strategy 2: Unique name attribute for form elements
  const name = element.getAttribute('name');
  if (name) {
    const selector = `${element.tagName.toLowerCase()}[name="${CSS.escape(name)}"]`;
    const matches = document.querySelectorAll(selector);
    if (matches.length === 1) {
      return selector;
    }
  }

  // Strategy 3: Unique class combination
  if (element.className && typeof element.className === 'string') {
    const classes = element.className
      .split(/\s+/)
      .filter((c) => c && !c.includes(':') && /^[a-zA-Z]/.test(c))
      .slice(0, 3);

    if (classes.length > 0) {
      const classSelector = classes.map((c) => `.${CSS.escape(c)}`).join('');
      const selector = `${element.tagName.toLowerCase()}${classSelector}`;
      const matches = document.querySelectorAll(selector);
      if (matches.length === 1) {
        return selector;
      }
    }
  }

  // Strategy 4: Data attributes
  const dataTestId = element.getAttribute('data-testid') || element.getAttribute('data-test-id');
  if (dataTestId) {
    return `[data-testid="${CSS.escape(dataTestId)}"]`;
  }

  // Strategy 5: Aria attributes
  const ariaLabel = element.getAttribute('aria-label');
  if (ariaLabel) {
    const selector = `${element.tagName.toLowerCase()}[aria-label="${CSS.escape(ariaLabel)}"]`;
    const matches = document.querySelectorAll(selector);
    if (matches.length === 1) {
      return selector;
    }
  }

  // Strategy 6: nth-child path (fallback)
  return generateNthChildPath(element);
}

/**
 * Generate an nth-child path selector
 */
function generateNthChildPath(element: HTMLElement): string {
  const path: string[] = [];
  let current: HTMLElement | null = element;

  while (current && current !== document.body && path.length < 5) {
    const parent = current.parentElement;
    if (!parent) break;

    const siblings = Array.from(parent.children).filter(
      (el) => el.tagName === current!.tagName
    );
    const index = siblings.indexOf(current) + 1;

    if (siblings.length === 1) {
      path.unshift(current.tagName.toLowerCase());
    } else {
      path.unshift(`${current.tagName.toLowerCase()}:nth-of-type(${index})`);
    }

    current = parent;
  }

  if (current === document.body) {
    path.unshift('body');
  }

  return path.join(' > ');
}

/**
 * Extract relevant attributes for agent context
 */
function extractRelevantAttributes(element: HTMLElement): Record<string, string> {
  const relevant: Record<string, string> = {};
  const attrs = ['href', 'name', 'placeholder', 'aria-label', 'title', 'role', 'type', 'value'];

  attrs.forEach((attr) => {
    const value = element.getAttribute(attr);
    if (value && attr !== 'value') {
      // Don't expose form values for privacy
      relevant[attr] = value.slice(0, 100);
    }
  });

  return relevant;
}

// ============================================================================
// Text Extraction
// ============================================================================

/**
 * Extract visible text content from the page
 */
function extractVisibleText(): string {
  // Try to find main content area
  const mainSelectors = [
    'main',
    'article',
    '[role="main"]',
    '.content',
    '#content',
    '.main-content',
    '#main-content',
  ];

  let target: Element | null = null;
  for (const selector of mainSelectors) {
    target = document.querySelector(selector);
    if (target) break;
  }

  // Fall back to body
  if (!target) {
    target = document.body;
  }

  // Clone and clean
  const clone = target.cloneNode(true) as HTMLElement;

  // Remove non-content elements
  const removeSelectors = [
    'script',
    'style',
    'noscript',
    'nav',
    'header',
    'footer',
    'aside',
    '.sidebar',
    '.navigation',
    '.menu',
    '.advertisement',
    '.ad',
    '[role="navigation"]',
    '[role="banner"]',
    '[role="complementary"]',
  ];

  removeSelectors.forEach((selector) => {
    clone.querySelectorAll(selector).forEach((el) => el.remove());
  });

  // Extract and clean text
  const text = clone.innerText || clone.textContent || '';

  return text
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, MAX_PAGE_TEXT_LENGTH);
}
