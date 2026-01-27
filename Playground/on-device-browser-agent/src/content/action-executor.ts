/**
 * Action Executor
 *
 * Executes browser actions in the page context.
 * Supports: click, type, extract, scroll, wait
 * (Navigate is handled by the service worker)
 *
 * Enhanced features:
 * - Wait for elements with retries
 * - Overlay/modal dismissal
 * - Click verification
 * - Amazon-specific handling
 */

import type { ActionResult, ActionType } from '../shared/types';
import { TYPING_DELAY, DEFAULT_WAIT_TIMEOUT } from '../shared/constants';

// ============================================================================
// Configuration
// ============================================================================

const MAX_CLICK_RETRIES = 3;
const CLICK_RETRY_DELAY = 500;
const OVERLAY_DISMISS_SELECTORS = [
  // Cookie banners
  '[id*="cookie"] button[id*="accept"]',
  '[class*="cookie"] button[class*="accept"]',
  '[id*="consent"] button',
  // Generic modals
  '[class*="modal"] button[class*="close"]',
  '[class*="dialog"] button[class*="close"]',
  '[role="dialog"] button[aria-label*="close"]',
  '[role="dialog"] button[aria-label*="Close"]',
  // Amazon-specific
  '#sp-cc-accept', // Amazon cookie consent
  '[data-action="sp-cc-accept"]',
  '.a-modal-close',
  '#nav-main .nav-a[data-nav-ref="nav_ya_signin"]', // Sign in prompt
];

// ============================================================================
// Main Executor
// ============================================================================

/**
 * Execute a browser action and return the result
 */
export async function executeAction(
  actionType: ActionType,
  params: Record<string, string>
): Promise<ActionResult> {
  console.log(`[Content] Executing action: ${actionType}`, params);

  try {
    switch (actionType) {
      case 'click':
        return await executeClick(params.selector);

      case 'type':
        return await executeType(params.selector, params.text);

      case 'press_enter':
        return await executePressEnter(params.selector);

      case 'extract':
        return await executeExtract(params.selector);

      case 'scroll':
        return await executeScroll(
          params.direction as 'up' | 'down',
          parseInt(params.amount || '500', 10)
        );

      case 'wait':
        return await executeWait(params.selector, parseInt(params.timeout || String(DEFAULT_WAIT_TIMEOUT), 10));

      case 'navigate':
        // Navigation is handled by service worker, but we might receive it here
        return { success: true, data: 'Navigation handled by service worker' };

      default:
        return { success: false, error: `Unknown action type: ${actionType}` };
    }
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    console.error(`[Content] Action failed:`, errorMsg);
    return { success: false, error: errorMsg };
  }
}

// ============================================================================
// Enhanced Helper Functions
// ============================================================================

/**
 * Wait for an element to appear in the DOM
 */
async function waitForElement(selector: string, timeout: number = 5000): Promise<Element | null> {
  const startTime = Date.now();
  const pollInterval = 100;

  while (Date.now() - startTime < timeout) {
    const element = resolveSelector(selector);
    if (element && isElementReady(element as HTMLElement)) {
      return element;
    }
    await sleep(pollInterval);
  }

  return null;
}

/**
 * Check if an element is ready for interaction (visible, not covered)
 */
function isElementReady(element: HTMLElement): boolean {
  if (!element) return false;

  const style = window.getComputedStyle(element);
  if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') {
    return false;
  }

  const rect = element.getBoundingClientRect();
  if (rect.width === 0 || rect.height === 0) {
    return false;
  }

  return true;
}

/**
 * Check if an element is covered by another element (e.g., overlay)
 */
function isElementCovered(element: HTMLElement): boolean {
  const rect = element.getBoundingClientRect();
  const centerX = rect.left + rect.width / 2;
  const centerY = rect.top + rect.height / 2;

  const topElement = document.elementFromPoint(centerX, centerY);

  if (!topElement) return true;
  if (topElement === element) return false;
  if (element.contains(topElement)) return false;

  return true;
}

/**
 * Attempt to dismiss overlays/modals that might block interaction
 */
async function dismissOverlays(): Promise<boolean> {
  let dismissed = false;

  for (const selector of OVERLAY_DISMISS_SELECTORS) {
    try {
      const element = document.querySelector(selector);
      if (element && element instanceof HTMLElement && isElementReady(element)) {
        element.click();
        dismissed = true;
        await sleep(300);
      }
    } catch {
      // Ignore errors from specific selectors
    }
  }

  // Also try to find and close any visible modal by looking for close buttons
  const closeButtons = document.querySelectorAll(
    'button[aria-label*="close"], button[aria-label*="Close"], ' +
    'button.close, .modal-close, [data-dismiss="modal"]'
  );

  for (const btn of closeButtons) {
    if (btn instanceof HTMLElement && isElementReady(btn)) {
      const modal = btn.closest('[role="dialog"], .modal, [class*="modal"]');
      if (modal) {
        btn.click();
        dismissed = true;
        await sleep(300);
        break;
      }
    }
  }

  return dismissed;
}

// ============================================================================
// Action Implementations
// ============================================================================

/**
 * Click an element by selector with retry logic
 */
async function executeClick(selector: string): Promise<ActionResult> {
  let lastError: string = '';

  for (let attempt = 0; attempt < MAX_CLICK_RETRIES; attempt++) {
    // First, try to dismiss any overlays
    if (attempt > 0) {
      await dismissOverlays();
      await sleep(CLICK_RETRY_DELAY);
    }

    const element = resolveSelector(selector);

    if (!element) {
      // Wait for element to appear
      const waited = await waitForElement(selector, 2000);
      if (!waited) {
        lastError = `Element not found: ${selector}`;
        continue;
      }
    }

    const el = (element || await waitForElement(selector, 1000)) as HTMLElement;
    if (!el) {
      lastError = `Element not found after waiting: ${selector}`;
      continue;
    }

    if (!(el instanceof HTMLElement)) {
      lastError = `Element is not interactive: ${selector}`;
      continue;
    }

    // Check if element is covered
    if (isElementCovered(el)) {
      console.log(`[Content] Element covered, attempting to dismiss overlays (attempt ${attempt + 1})`);
      await dismissOverlays();
      await sleep(300);

      if (isElementCovered(el)) {
        lastError = `Element is covered by another element: ${selector}`;
        continue;
      }
    }

    // Scroll element into view
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    await sleep(300);

    // Focus the element
    el.focus();

    // Dispatch click events
    const clickEvent = new MouseEvent('click', {
      bubbles: true,
      cancelable: true,
      view: window,
    });
    el.dispatchEvent(clickEvent);

    // Also try native click for buttons/links
    if (typeof el.click === 'function') {
      el.click();
    }

    // Check if it was a link that should navigate
    if (el instanceof HTMLAnchorElement && el.href && !el.href.startsWith('javascript:')) {
      const targetHref = el.href;

      // Give click a moment to work (some sites use JS navigation)
      await sleep(300);

      // If still on same page and no target, force navigation
      if (window.location.href !== targetHref && !el.target) {
        console.log(`[Content] Click didn't navigate, forcing navigation to: ${targetHref}`);
        window.location.href = targetHref;
      }

      return { success: true, data: `Navigating to: ${targetHref}` };
    }

    // Check if it was a submit button
    if (el instanceof HTMLButtonElement && el.type === 'submit') {
      const form = el.closest('form');
      if (form) {
        return { success: true, data: 'Clicked submit button' };
      }
    }

    return { success: true, data: `Clicked element: ${selector}` };
  }

  return { success: false, error: lastError || `Failed to click: ${selector}` };
}

/**
 * Type text into an input element
 */
async function executeType(selector: string, text: string): Promise<ActionResult> {
  const element = resolveSelector(selector);

  if (!element) {
    return { success: false, error: `Element not found: ${selector}` };
  }

  if (!(element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement)) {
    // Try to find an input within the element
    const input = element.querySelector('input, textarea');
    if (input && (input instanceof HTMLInputElement || input instanceof HTMLTextAreaElement)) {
      return executeType(generateSelectorForElement(input), text);
    }
    return { success: false, error: `Element is not an input: ${selector}` };
  }

  // Scroll into view
  element.scrollIntoView({ behavior: 'smooth', block: 'center' });
  await sleep(200);

  // Focus and clear
  element.focus();
  element.value = '';

  // Dispatch focus event
  element.dispatchEvent(new FocusEvent('focus', { bubbles: true }));

  // Type character by character for better compatibility
  for (const char of text) {
    element.value += char;

    // Dispatch input event
    element.dispatchEvent(
      new InputEvent('input', {
        bubbles: true,
        cancelable: true,
        data: char,
        inputType: 'insertText',
      })
    );

    await sleep(TYPING_DELAY);
  }

  // Dispatch change event
  element.dispatchEvent(new Event('change', { bubbles: true }));

  // Check if we should submit (e.g., search box)
  const form = element.closest('form');
  if (form && element.type === 'search') {
    // Some search boxes auto-submit, give them a moment
    await sleep(100);
  }

  return { success: true, data: `Typed "${text}" into ${selector}` };
}

/**
 * Press Enter key on an element (for submitting forms/search)
 */
async function executePressEnter(selector: string): Promise<ActionResult> {
  const element = resolveSelector(selector);

  if (!element) {
    // If no selector, try to find focused input
    const activeEl = document.activeElement;
    if (activeEl && (activeEl instanceof HTMLInputElement || activeEl instanceof HTMLTextAreaElement)) {
      return pressEnterOn(activeEl);
    }
    return { success: false, error: `Element not found: ${selector}` };
  }

  if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
    return pressEnterOn(element);
  }

  // Try to find input within element
  const input = element.querySelector('input, textarea');
  if (input && (input instanceof HTMLInputElement || input instanceof HTMLTextAreaElement)) {
    return pressEnterOn(input);
  }

  return { success: false, error: `Element is not an input: ${selector}` };
}

async function pressEnterOn(element: HTMLInputElement | HTMLTextAreaElement): Promise<ActionResult> {
  element.focus();
  await sleep(100);

  // Dispatch keydown event for Enter
  const keydownEvent = new KeyboardEvent('keydown', {
    key: 'Enter',
    code: 'Enter',
    keyCode: 13,
    which: 13,
    bubbles: true,
    cancelable: true,
  });
  element.dispatchEvent(keydownEvent);

  // Dispatch keypress event
  const keypressEvent = new KeyboardEvent('keypress', {
    key: 'Enter',
    code: 'Enter',
    keyCode: 13,
    which: 13,
    bubbles: true,
    cancelable: true,
  });
  element.dispatchEvent(keypressEvent);

  // Dispatch keyup event
  const keyupEvent = new KeyboardEvent('keyup', {
    key: 'Enter',
    code: 'Enter',
    keyCode: 13,
    which: 13,
    bubbles: true,
    cancelable: true,
  });
  element.dispatchEvent(keyupEvent);

  // If element is in a form, try to submit the form
  const form = element.closest('form');
  if (form) {
    // Try to find and click submit button
    const submitBtn = form.querySelector('button[type="submit"], input[type="submit"]');
    if (submitBtn && submitBtn instanceof HTMLElement) {
      await sleep(100);
      submitBtn.click();
      return { success: true, data: 'Pressed Enter and submitted form' };
    }

    // Otherwise submit form directly
    try {
      form.requestSubmit();
      return { success: true, data: 'Pressed Enter and submitted form' };
    } catch {
      form.submit();
      return { success: true, data: 'Pressed Enter and submitted form' };
    }
  }

  return { success: true, data: 'Pressed Enter key' };
}

/**
 * Extract text content from an element
 */
async function executeExtract(selector: string): Promise<ActionResult> {
  // Handle empty/body selector for full page extraction
  if (!selector || selector === 'body' || selector === 'page') {
    const mainSelectors = ['main', 'article', '[role="main"]', '.content', '#content'];
    let target: Element | null = null;

    for (const sel of mainSelectors) {
      target = document.querySelector(sel);
      if (target) break;
    }

    if (!target) {
      target = document.body;
    }

    const text = (target as HTMLElement).innerText || '';
    return { success: true, data: text.trim().slice(0, 5000) };
  }

  const element = resolveSelector(selector);

  if (!element) {
    return { success: false, error: `Element not found: ${selector}` };
  }

  const text = (element as HTMLElement).innerText || element.textContent || '';
  return { success: true, data: text.trim() };
}

/**
 * Scroll the page
 */
async function executeScroll(
  direction: 'up' | 'down',
  amount: number
): Promise<ActionResult> {
  const scrollAmount = direction === 'down' ? amount : -amount;

  window.scrollBy({
    top: scrollAmount,
    behavior: 'smooth',
  });

  await sleep(500); // Wait for scroll to complete

  return {
    success: true,
    data: `Scrolled ${direction} by ${amount}px. New scroll position: ${window.scrollY}`,
  };
}

/**
 * Wait for an element to appear or a fixed time
 */
async function executeWait(
  selector?: string,
  timeout: number = DEFAULT_WAIT_TIMEOUT
): Promise<ActionResult> {
  if (!selector) {
    await sleep(timeout);
    return { success: true, data: `Waited ${timeout}ms` };
  }

  const startTime = Date.now();

  while (Date.now() - startTime < timeout) {
    const element = resolveSelector(selector);
    if (element) {
      return { success: true, data: `Found element: ${selector}` };
    }
    await sleep(100);
  }

  return { success: false, error: `Timeout waiting for element: ${selector}` };
}

// ============================================================================
// Helpers
// ============================================================================

/**
 * Sleep for a specified number of milliseconds
 */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Generate a selector for an element (simple version)
 */
function generateSelectorForElement(element: HTMLElement): string {
  if (element.id) {
    return `#${element.id}`;
  }

  const name = element.getAttribute('name');
  if (name) {
    return `${element.tagName.toLowerCase()}[name="${name}"]`;
  }

  // Fall back to tag and classes
  const classes = Array.from(element.classList).slice(0, 2).join('.');
  if (classes) {
    return `${element.tagName.toLowerCase()}.${classes}`;
  }

  return element.tagName.toLowerCase();
}

/**
 * Resolve a selector to an element
 * Supports semantic selectors for vision-based navigation:
 * - text:Label - Find element by visible text
 * - input:placeholder - Find input by placeholder/label
 * - link:text - Find link by text content
 * - button:text - Find button by text content
 * - Regular CSS selectors
 */
function resolveSelector(selector: string): Element | null {
  if (!selector) return null;

  // Handle semantic selectors
  if (selector.startsWith('text:')) {
    const searchText = selector.slice(5).toLowerCase().trim();
    return findElementByText(searchText);
  }

  if (selector.startsWith('input:')) {
    const searchText = selector.slice(6).toLowerCase().trim();
    return findInputByLabel(searchText);
  }

  if (selector.startsWith('link:')) {
    const searchText = selector.slice(5).toLowerCase().trim();
    return findLinkByText(searchText);
  }

  if (selector.startsWith('button:')) {
    const searchText = selector.slice(7).toLowerCase().trim();
    return findButtonByText(searchText);
  }

  // Regular CSS selector
  try {
    return document.querySelector(selector);
  } catch {
    // Invalid selector, try as text search
    return findElementByText(selector.toLowerCase());
  }
}

/**
 * Find clickable element by visible text
 */
function findElementByText(searchText: string): Element | null {
  const clickableSelectors = [
    'button',
    'a',
    '[role="button"]',
    '[role="link"]',
    'input[type="submit"]',
    'input[type="button"]',
    '[onclick]',
    '[tabindex]:not([tabindex="-1"])',
  ];

  for (const sel of clickableSelectors) {
    const elements = document.querySelectorAll(sel);
    for (const el of elements) {
      const text = (el as HTMLElement).innerText?.toLowerCase() || '';
      const ariaLabel = el.getAttribute('aria-label')?.toLowerCase() || '';
      const title = el.getAttribute('title')?.toLowerCase() || '';
      const value = (el as HTMLInputElement).value?.toLowerCase() || '';

      if (
        text.includes(searchText) ||
        ariaLabel.includes(searchText) ||
        title.includes(searchText) ||
        value.includes(searchText)
      ) {
        return el;
      }
    }
  }

  // Fallback: any element with matching text
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
  let node: Node | null;
  while ((node = walker.nextNode())) {
    const el = node as HTMLElement;
    if (el.innerText?.toLowerCase().includes(searchText)) {
      // Return the most specific clickable parent or the element itself
      const clickable = el.closest('button, a, [role="button"], [onclick]');
      return clickable || el;
    }
  }

  return null;
}

/**
 * Find input element by placeholder, label, or aria-label
 */
function findInputByLabel(searchText: string): Element | null {
  const inputs = document.querySelectorAll('input, textarea, select');

  for (const input of inputs) {
    const placeholder = input.getAttribute('placeholder')?.toLowerCase() || '';
    const ariaLabel = input.getAttribute('aria-label')?.toLowerCase() || '';
    const name = input.getAttribute('name')?.toLowerCase() || '';
    const id = input.id?.toLowerCase() || '';

    if (
      placeholder.includes(searchText) ||
      ariaLabel.includes(searchText) ||
      name.includes(searchText) ||
      id.includes(searchText)
    ) {
      return input;
    }

    // Check for associated label
    if (input.id) {
      const label = document.querySelector(`label[for="${input.id}"]`);
      if (label?.textContent?.toLowerCase().includes(searchText)) {
        return input;
      }
    }
  }

  // Check for inputs inside label elements
  const labels = document.querySelectorAll('label');
  for (const label of labels) {
    if (label.textContent?.toLowerCase().includes(searchText)) {
      const input = label.querySelector('input, textarea, select');
      if (input) return input;
    }
  }

  return null;
}

/**
 * Find link by text content
 */
function findLinkByText(searchText: string): Element | null {
  const links = document.querySelectorAll('a');

  for (const link of links) {
    const text = link.innerText?.toLowerCase() || '';
    const ariaLabel = link.getAttribute('aria-label')?.toLowerCase() || '';
    const title = link.getAttribute('title')?.toLowerCase() || '';

    if (text.includes(searchText) || ariaLabel.includes(searchText) || title.includes(searchText)) {
      return link;
    }
  }

  return null;
}

/**
 * Find button by text content
 */
function findButtonByText(searchText: string): Element | null {
  const buttons = document.querySelectorAll('button, [role="button"], input[type="submit"], input[type="button"]');

  for (const button of buttons) {
    const text = (button as HTMLElement).innerText?.toLowerCase() || '';
    const ariaLabel = button.getAttribute('aria-label')?.toLowerCase() || '';
    const title = button.getAttribute('title')?.toLowerCase() || '';
    const value = (button as HTMLInputElement).value?.toLowerCase() || '';

    if (
      text.includes(searchText) ||
      ariaLabel.includes(searchText) ||
      title.includes(searchText) ||
      value.includes(searchText)
    ) {
      return button;
    }
  }

  return null;
}
