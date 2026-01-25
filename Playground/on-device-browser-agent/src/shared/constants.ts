// ============================================================================
// Model Configuration
// ============================================================================

/**
 * LLM Engine type: 'transformers' for Transformers.js, 'webllm' for MLC-AI WebLLM
 */
export const LLM_ENGINE_TYPE: 'transformers' | 'webllm' = 'webllm';

/**
 * Default model for agent inference
 * Qwen 2.5 3B - better reasoning, recommended for browser automation
 */
export const DEFAULT_MODEL = 'Qwen2.5-3B-Instruct-q4f16_1-MLC';

/**
 * Available LLM models for user selection
 */
export const AVAILABLE_LLM_MODELS = [
  // WebLLM models - fast download, good caching
  { id: 'Qwen2.5-3B-Instruct-q4f16_1-MLC', name: 'Qwen 2.5 3B (Recommended)', size: '2.0 GB', context: '4K', engine: 'webllm' },
  { id: 'Qwen2.5-1.5B-Instruct-q4f16_1-MLC', name: 'Qwen 2.5 1.5B (Fast)', size: '1.0 GB', context: '4K', engine: 'webllm' },
  { id: 'Llama-3.2-1B-Instruct-q4f16_1-MLC', name: 'Llama 3.2 1B (Fastest)', size: '0.6 GB', context: '4K', engine: 'webllm' },
  { id: 'Phi-3.5-mini-instruct-q4f16_1-MLC', name: 'Phi 3.5 Mini 3.8B', size: '2.2 GB', context: '4K', engine: 'webllm' },
  // LFM2 via Transformers.js - slower download but 32K context
  { id: 'LiquidAI/LFM2.5-1.2B-Instruct-ONNX', name: 'LFM2.5 1.2B (32K context)', size: '~600 MB', context: '32K', engine: 'transformers' },
];

/**
 * Available VLM models for vision mode
 * Ordered by size (smaller to larger)
 */
export const AVAILABLE_VLM_MODELS = [
  { id: 'tiny', name: 'SmolVLM 256M (Fastest)', size: '~500 MB' },
  { id: 'small', name: 'SmolVLM 500M (Balanced)', size: '~1 GB' },
  { id: 'base', name: 'SmolVLM 2B (Best)', size: '~2 GB' },
];

/**
 * Fallback models if the default fails to load
 */
export const FALLBACK_MODELS = [
  'Qwen2.5-3B-Instruct-q4f16_1-MLC',      // Primary - best reasoning
  'Qwen2.5-1.5B-Instruct-q4f16_1-MLC',    // Fallback - faster
  'Llama-3.2-1B-Instruct-q4f16_1-MLC',    // Last resort - fastest
];

// ============================================================================
// Agent Configuration
// ============================================================================

/**
 * Maximum steps before giving up on a task
 * Amazon shopping needs ~8-10 steps, with retries could be more
 */
export const MAX_STEPS = 25;

/**
 * Maximum replanning attempts when stuck
 */
export const MAX_REPLANS = 2;

/**
 * LLM temperature for agent inference (lower = more deterministic)
 */
export const AGENT_TEMPERATURE = 0.3;

/**
 * Maximum tokens for agent responses
 * IMPORTANT: Keep small! Models have 4K context TOTAL.
 * Output should be small JSON (~50-100 tokens max).
 */
export const AGENT_MAX_TOKENS = 512;

/**
 * Maximum LLM calls per task (to limit reliance on inference)
 */
export const MAX_LLM_CALLS_PER_TASK = 3;

// ============================================================================
// DOM Observation Configuration
// ============================================================================

/**
 * CSS selectors for interactive elements
 */
export const INTERACTIVE_SELECTORS = [
  'a[href]',
  'button',
  'input',
  'textarea',
  'select',
  "[role='button']",
  "[role='link']",
  '[onclick]',
  '[tabindex]:not([tabindex="-1"])',
];

/**
 * Maximum interactive elements to include in DOM state
 * With Qwen 2.5 3B we can use more context - each element ~50 tokens
 */
export const MAX_INTERACTIVE_ELEMENTS = 30;

/**
 * Maximum page text length in DOM state
 * ~1 token per 4 chars, 1500 chars ~ 375 tokens
 */
export const MAX_PAGE_TEXT_LENGTH = 1500;

// ============================================================================
// Amazon-Specific Configuration
// ============================================================================

/**
 * Amazon URL patterns for state detection
 */
export const AMAZON_URL_PATTERNS = {
  homepage: /^https?:\/\/(www\.)?amazon\.(com|co\.[a-z]{2}|[a-z]{2})\/?$/,
  search: /\/s\?/,
  product: /\/(dp|gp\/product)\//,
  cart: /\/gp\/cart/,
  signin: /\/ap\/signin/,
  checkout: /\/gp\/buy/,
};

/**
 * Amazon selectors for key elements
 */
export const AMAZON_SELECTORS = {
  // Search
  searchInput: '#twotabsearchtextbox',
  searchButton: '#nav-search-submit-button',

  // Results page
  productCard: '[data-component-type="s-search-result"]',
  sponsoredLabel: '.s-label-popover-default',
  productTitle: 'h2 a.a-link-normal',
  productPrice: '.a-price .a-offscreen',

  // Product page
  addToCartButton: '#add-to-cart-button',
  buyNowButton: '#buy-now-button',
  productTitleMain: '#productTitle',
  outOfStock: '#outOfStock',
  seeAllBuyingOptions: '#buybox-see-all-buying-choices',

  // Cart
  cartCount: '#nav-cart-count',
  sideCartViewCart: '#attach-sidesheet-view-cart-button',
  addedToCartConfirm: '#NATC_SMART_WAGON_CONF_MSG_SUCCESS',

  // Obstacles
  captchaForm: 'form[action*="captcha"]',
  signinForm: 'form[name="signIn"]',
};

/**
 * Amazon success indicators (text patterns)
 */
export const AMAZON_SUCCESS_PATTERNS = {
  addedToCart: ['added to cart', 'added to your cart', '1 item added to cart'],
  searchResults: ['results for', 'over', 'of results'],
  productPage: ['add to cart', 'buy now'],
};

/**
 * Amazon obstacle indicators (text patterns)
 */
export const AMAZON_OBSTACLE_PATTERNS = {
  login: ['sign in', 'sign-in', 'create account'],
  captcha: ['enter the characters', 'type the characters', 'robot'],
  outOfStock: ['currently unavailable', 'out of stock', 'not available'],
  priceChange: ['price changed', 'price has changed'],
};

// ============================================================================
// Timing Configuration
// ============================================================================

/**
 * Delay after navigation for page to settle
 */
export const POST_NAVIGATION_DELAY = 1000;

/**
 * Delay between simulated keystrokes
 */
export const TYPING_DELAY = 30;

/**
 * Default wait timeout for elements
 */
export const DEFAULT_WAIT_TIMEOUT = 3000;

/**
 * Maximum wait time for page load
 */
export const PAGE_LOAD_TIMEOUT = 30000;

// ============================================================================
// Message Port Names
// ============================================================================

export const POPUP_PORT_NAME = 'popup-connection';
