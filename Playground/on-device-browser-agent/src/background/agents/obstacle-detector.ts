/**
 * Obstacle Detector
 *
 * Detects obstacles that require user intervention:
 * - Login required
 * - CAPTCHA
 * - Out of stock
 * - Price changes
 * - Errors
 */

import type { DOMState, ObstacleType } from '../../shared/types';
import {
  AMAZON_URL_PATTERNS,
  AMAZON_OBSTACLE_PATTERNS,
} from '../../shared/constants';

// ============================================================================
// Types
// ============================================================================

export interface DetectedObstacle {
  type: ObstacleType;
  message: string;
  recoverable: boolean;
  userActionRequired: 'LOGIN' | 'SOLVE_CAPTCHA' | 'CONFIRM' | 'NONE';
}

// ============================================================================
// Obstacle Detection
// ============================================================================

/**
 * Detect any obstacles in the current page state
 */
export function detectObstacle(domState: DOMState): DetectedObstacle | null {
  const url = domState.url || '';
  const pageText = domState.pageText?.toLowerCase() || '';
  const pageState = domState.pageState;
  const alerts = domState.alerts || [];

  // Check for CAPTCHA (highest priority)
  const captcha = detectCaptcha(url, pageText, pageState);
  if (captcha) return captcha;

  // Check for login required
  const login = detectLoginRequired(url, pageText, pageState);
  if (login) return login;

  // Check for out of stock
  const outOfStock = detectOutOfStock(pageText, pageState);
  if (outOfStock) return outOfStock;

  // Check for errors
  const error = detectError(pageText, alerts);
  if (error) return error;

  return null;
}

/**
 * Detect CAPTCHA pages
 */
function detectCaptcha(url: string, pageText: string, pageState?: string): DetectedObstacle | null {
  // Check page state
  if (pageState === 'captcha') {
    return {
      type: 'CAPTCHA',
      message: 'CAPTCHA detected. Please solve it to continue.',
      recoverable: true,
      userActionRequired: 'SOLVE_CAPTCHA',
    };
  }

  // Check URL patterns
  if (url.includes('/captcha') || url.includes('/validateCaptcha')) {
    return {
      type: 'CAPTCHA',
      message: 'CAPTCHA verification required.',
      recoverable: true,
      userActionRequired: 'SOLVE_CAPTCHA',
    };
  }

  // Check page text
  const captchaPatterns = AMAZON_OBSTACLE_PATTERNS.captcha;
  if (captchaPatterns.some(p => pageText.includes(p))) {
    return {
      type: 'CAPTCHA',
      message: 'CAPTCHA detected on page. Please solve it to continue.',
      recoverable: true,
      userActionRequired: 'SOLVE_CAPTCHA',
    };
  }

  return null;
}

/**
 * Detect login required
 */
function detectLoginRequired(url: string, pageText: string, pageState?: string): DetectedObstacle | null {
  // Check page state
  if (pageState === 'signin') {
    return {
      type: 'LOGIN_REQUIRED',
      message: 'Please sign in to your Amazon account to continue.',
      recoverable: true,
      userActionRequired: 'LOGIN',
    };
  }

  // Check URL patterns
  if (AMAZON_URL_PATTERNS.signin.test(url)) {
    return {
      type: 'LOGIN_REQUIRED',
      message: 'Sign-in required. Please log in to continue.',
      recoverable: true,
      userActionRequired: 'LOGIN',
    };
  }

  // Check for sign-in prompts in page
  const loginPatterns = ['sign in to continue', 'please sign in', 'login to continue'];
  if (loginPatterns.some(p => pageText.includes(p))) {
    return {
      type: 'LOGIN_REQUIRED',
      message: 'This action requires you to be signed in.',
      recoverable: true,
      userActionRequired: 'LOGIN',
    };
  }

  return null;
}

/**
 * Detect out of stock items
 */
function detectOutOfStock(pageText: string, pageState?: string): DetectedObstacle | null {
  // Only check on product pages
  if (pageState !== 'product_page') return null;

  const outOfStockPatterns = AMAZON_OBSTACLE_PATTERNS.outOfStock;
  if (outOfStockPatterns.some(p => pageText.includes(p))) {
    return {
      type: 'OUT_OF_STOCK',
      message: 'This item is currently unavailable.',
      recoverable: false,
      userActionRequired: 'NONE',
    };
  }

  return null;
}

/**
 * Detect error messages
 */
function detectError(pageText: string, alerts: string[]): DetectedObstacle | null {
  const errorPatterns = [
    'something went wrong',
    'error occurred',
    'unable to process',
    'please try again',
    'service unavailable',
  ];

  const allText = pageText + ' ' + alerts.join(' ').toLowerCase();

  if (errorPatterns.some(p => allText.includes(p))) {
    return {
      type: 'ERROR',
      message: 'An error occurred. The page may need to be refreshed.',
      recoverable: true,
      userActionRequired: 'NONE',
    };
  }

  return null;
}

/**
 * Check if an obstacle has been resolved
 * (useful for checking after user action)
 */
export function isObstacleResolved(
  previousObstacle: DetectedObstacle,
  currentDomState: DOMState
): boolean {
  const currentObstacle = detectObstacle(currentDomState);

  // No obstacle detected now
  if (!currentObstacle) return true;

  // Different type of obstacle (previous one resolved, new one appeared)
  if (currentObstacle.type !== previousObstacle.type) return true;

  return false;
}

/**
 * Get user-friendly message for an obstacle
 */
export function getObstacleMessage(obstacle: DetectedObstacle): string {
  switch (obstacle.type) {
    case 'LOGIN_REQUIRED':
      return '🔐 Please sign in to your Amazon account, then click Resume.';
    case 'CAPTCHA':
      return '🤖 Please solve the CAPTCHA, then click Resume.';
    case 'OUT_OF_STOCK':
      return '📦 This item is out of stock. Try a different product.';
    case 'PRICE_CHANGED':
      return '💰 The price has changed. Please confirm to continue.';
    case 'ERROR':
      return '⚠️ An error occurred. Try refreshing the page.';
    default:
      return obstacle.message;
  }
}
