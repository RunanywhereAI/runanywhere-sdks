/**
 * Content Script Entry Point
 *
 * This script is injected into all web pages.
 * It exposes DOM observation and action execution functions
 * that can be called by the service worker via chrome.scripting.
 */

import { serializeDOMState } from './dom-observer';
import { executeAction } from './action-executor';
import type { ActionType } from '../shared/types';

// ============================================================================
// Global API Exposure
// ============================================================================

/**
 * Expose functions to the window object for service worker access
 * The service worker uses chrome.scripting.executeScript to call these
 */
interface LocalBrowserAPI {
  serializeDOMState: typeof serializeDOMState;
  executeAction: typeof executeAction;
}

declare global {
  interface Window {
    __localBrowser?: LocalBrowserAPI;
  }
}

// Expose the API
window.__localBrowser = {
  serializeDOMState,
  executeAction: (actionType: string, params: Record<string, string>) =>
    executeAction(actionType as ActionType, params),
};

// ============================================================================
// Initialization
// ============================================================================

/**
 * Notify the background script that the content script is ready
 */
function notifyReady(): void {
  try {
    chrome.runtime.sendMessage({ type: 'CONTENT_SCRIPT_READY' }, (response) => {
      if (chrome.runtime.lastError) {
        // This is normal when the extension context is invalidated
        console.log('[Local Browser] Could not notify background (this is OK on reload)');
      } else {
        console.log('[Local Browser] Content script ready, background acknowledged');
      }
    });
  } catch {
    // Extension context may be invalid
  }
}

// Notify on load
notifyReady();

console.log('[Local Browser] Content script loaded on:', window.location.href);

// ============================================================================
// Message Handling (alternative to executeScript)
// ============================================================================

/**
 * Handle messages from the service worker
 * This provides an alternative to executeScript for some scenarios
 */
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  // Handle PING from background script to check if content script is loaded
  if (message.type === 'PING') {
    sendResponse({ ok: true });
    return true;
  }

  if (message.type === 'GET_DOM_STATE') {
    try {
      const state = serializeDOMState();
      sendResponse({ success: true, data: state });
    } catch (error) {
      sendResponse({
        success: false,
        error: error instanceof Error ? error.message : String(error),
      });
    }
    return true;
  }

  if (message.type === 'EXECUTE_ACTION') {
    const { actionType, params } = message.payload;

    executeAction(actionType as ActionType, params)
      .then((result) => sendResponse(result))
      .catch((error) =>
        sendResponse({
          success: false,
          error: error instanceof Error ? error.message : String(error),
        })
      );

    return true; // Keep channel open for async response
  }
});
