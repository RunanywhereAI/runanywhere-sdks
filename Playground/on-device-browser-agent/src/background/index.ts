/**
 * Background Service Worker
 *
 * Main entry point for the extension's background process.
 * Handles:
 * - Communication with popup UI
 * - Task execution orchestration
 * - DOM state retrieval from content scripts
 * - Action execution via content scripts
 */

import { executor } from './agents/executor';
import { visionExecutor } from './agents/vision-executor';
import { visionEngine } from './vision-engine';
import { POPUP_PORT_NAME, POST_NAVIGATION_DELAY, PAGE_LOAD_TIMEOUT } from '../shared/constants';
import type { DOMState, ActionResult, ExecutorEvent, BackgroundMessage } from '../shared/types';

// ============================================================================
// State
// ============================================================================

let activePort: chrome.runtime.Port | null = null;
let currentTabId: number | null = null;

// ============================================================================
// Port Connection Handler
// ============================================================================

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== POPUP_PORT_NAME) return;

  console.log('[Background] Popup connected');
  activePort = port;

  port.onMessage.addListener(async (message: BackgroundMessage & { type: string }) => {
    console.log('[Background] Received message:', message.type);

    if (message.type === 'START_TASK') {
      const { task, modelId, visionMode, vlmModelId } = message.payload;
      await handleStartTask(task, port, modelId, visionMode, vlmModelId);
    } else if (message.type === 'CANCEL_TASK') {
      executor.cancel();
      visionExecutor.cancel();
    } else if (message.type === 'RESUME_TASK') {
      console.log('[Background] Resuming task');
      executor.resume();
    }
  });

  port.onDisconnect.addListener(() => {
    console.log('[Background] Popup disconnected');
    activePort = null;
  });
});

// ============================================================================
// Task Execution
// ============================================================================

async function handleStartTask(
  task: string,
  port: chrome.runtime.Port,
  modelId?: string,
  visionMode?: boolean,
  vlmModelId?: string
): Promise<void> {
  // Get the active tab
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });

  if (!tab?.id) {
    port.postMessage({ type: 'ERROR', error: 'No active tab found. Please open a web page first.' });
    return;
  }

  currentTabId = tab.id;

  // Event handler for forwarding to popup
  const handleEvent = (event: ExecutorEvent) => {
    try {
      port.postMessage({ type: 'EXECUTOR_EVENT', event });
    } catch (e) {
      console.error('[Background] Failed to send event to popup:', e);
    }
  };

  try {
    if (visionMode) {
      // Use vision executor for screenshot-based navigation
      console.log('[Background] Starting vision task with VLM:', vlmModelId || 'small');
      const unsubscribe = visionExecutor.onEvent(handleEvent);

      try {
        const result = await visionExecutor.executeTask(
          task,
          currentTabId!,
          (actionType, params) => executeAction(currentTabId!, actionType, params),
          vlmModelId
        );
        port.postMessage({ type: 'TASK_RESULT', result });
      } finally {
        unsubscribe();
      }
    } else {
      // Use standard executor for DOM-based navigation
      console.log('[Background] Starting task with LLM:', modelId || 'default');
      const unsubscribe = executor.onEvent(handleEvent);

      try {
        const result = await executor.executeTask(
          task,
          () => getDOMStateWithScreenshot(currentTabId!),
          (actionType, params) => executeAction(currentTabId!, actionType, params),
          modelId
        );
        port.postMessage({ type: 'TASK_RESULT', result });
      } finally {
        unsubscribe();
      }
    }
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    console.error('[Background] Task failed:', errorMsg);
    port.postMessage({ type: 'ERROR', error: errorMsg });
  } finally {
    currentTabId = null;
  }
}

// ============================================================================
// DOM State Retrieval
// ============================================================================

async function getDOMState(tabId: number): Promise<DOMState> {
  const maxRetries = 5;
  const retryDelay = 500;

  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      // Check if content script is available
      const isReady = await waitForContentScript(tabId, attempt === 0 ? 2000 : 500);

      if (!isReady) {
        // Get tab info to check if it's a restricted page
        const tab = await chrome.tabs.get(tabId);
        const tabUrl = tab.url || 'unknown';

        const isRestricted = tabUrl.startsWith('chrome://') ||
                            tabUrl.startsWith('chrome-extension://') ||
                            tabUrl.startsWith('about:') ||
                            tabUrl === 'chrome://newtab/';

        if (isRestricted) {
          return {
            url: tabUrl,
            title: tab.title || 'Restricted Page',
            interactiveElements: [],
            pageText: 'RESTRICTED PAGE: Cannot interact with this page. Use "navigate" action to go to a website first (e.g., navigate to https://google.com).',
          };
        }

        // Not restricted but content script not ready - wait and retry
        if (attempt < maxRetries - 1) {
          console.log(`[Background] Content script not ready, retrying (${attempt + 1}/${maxRetries})...`);
          await sleep(retryDelay);
          continue;
        }
      }

      // Try to get DOM state
      const result = await new Promise<DOMState>((resolve, reject) => {
        chrome.tabs.sendMessage(tabId, { type: 'GET_DOM_STATE' }, (response) => {
          if (chrome.runtime.lastError) {
            reject(new Error(chrome.runtime.lastError.message));
            return;
          }

          if (response?.success && response.data) {
            resolve(response.data);
          } else {
            reject(new Error(response?.error || 'Failed to get DOM state'));
          }
        });
      });

      return result;
    } catch (error) {
      console.error(`[Background] getDOMState attempt ${attempt + 1} failed:`, error);

      if (attempt < maxRetries - 1) {
        await sleep(retryDelay);
      }
    }
  }

  // All retries failed - return error state with actual tab info
  try {
    const tab = await chrome.tabs.get(tabId);
    return {
      url: tab.url || 'unknown',
      title: tab.title || 'Error loading page',
      interactiveElements: [],
      pageText: 'ERROR: Could not communicate with page. The page may still be loading or may have blocked the extension.',
    };
  } catch {
    return {
      url: 'unknown',
      title: 'Error loading page state',
      interactiveElements: [],
      pageText: '',
    };
  }
}

// ============================================================================
// Action Execution
// ============================================================================

async function executeAction(
  tabId: number,
  actionType: string,
  params: Record<string, string>
): Promise<ActionResult> {
  console.log('[Background] Executing action:', actionType, params);

  // Handle navigation specially - it changes the page
  if (actionType === 'navigate') {
    return executeNavigation(tabId, params.url);
  }

  // Ensure content script is loaded
  await ensureContentScriptLoaded(tabId);

  // Execute other actions via message passing
  return new Promise((resolve) => {
    chrome.tabs.sendMessage(
      tabId,
      { type: 'EXECUTE_ACTION', payload: { actionType, params } },
      (response) => {
        if (chrome.runtime.lastError) {
          resolve({
            success: false,
            error: chrome.runtime.lastError.message || 'Failed to execute action',
          });
          return;
        }

        resolve(response || { success: false, error: 'No response from content script' });
      }
    );
  });
}

async function executeNavigation(tabId: number, url: string): Promise<ActionResult> {
  try {
    // Ensure URL has protocol
    let targetUrl = url;
    if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
      targetUrl = 'https://' + targetUrl;
    }

    console.log('[Background] Navigating to:', targetUrl);
    await chrome.tabs.update(tabId, { url: targetUrl });
    await waitForTabLoad(tabId);

    // Wait for content script to become available after navigation
    console.log('[Background] Waiting for content script after navigation...');
    const isReady = await waitForContentScript(tabId, 3000);

    if (isReady) {
      console.log('[Background] Content script ready after navigation');
      return { success: true, data: `Navigated to ${targetUrl}` };
    } else {
      console.warn('[Background] Content script not ready after navigation, but page loaded');
      return { success: true, data: `Navigated to ${targetUrl} (content script may still be loading)` };
    }
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Wait for content script to become available with timeout
 * Returns true if content script is ready, false otherwise
 */
async function waitForContentScript(tabId: number, timeout: number = 2000): Promise<boolean> {
  const startTime = Date.now();
  const pollInterval = 100;

  while (Date.now() - startTime < timeout) {
    try {
      const isReady = await new Promise<boolean>((resolve) => {
        const timeoutId = setTimeout(() => resolve(false), pollInterval);

        chrome.tabs.sendMessage(tabId, { type: 'PING' }, (response) => {
          clearTimeout(timeoutId);
          if (chrome.runtime.lastError) {
            resolve(false);
          } else {
            resolve(response?.ok === true);
          }
        });
      });

      if (isReady) {
        return true;
      }

      await sleep(pollInterval);
    } catch {
      await sleep(pollInterval);
    }
  }

  return false;
}

async function ensureContentScriptLoaded(tabId: number): Promise<boolean> {
  const isReady = await waitForContentScript(tabId, 1000);

  if (!isReady) {
    console.warn('[Background] Content script not available in tab', tabId);
  }

  return isReady;
}

function waitForTabLoad(tabId: number): Promise<void> {
  return new Promise((resolve) => {
    let resolved = false;

    const listener = (
      updatedTabId: number,
      changeInfo: chrome.tabs.TabChangeInfo
    ) => {
      if (updatedTabId === tabId && changeInfo.status === 'complete' && !resolved) {
        resolved = true;
        chrome.tabs.onUpdated.removeListener(listener);
        // Give page time to render
        setTimeout(resolve, POST_NAVIGATION_DELAY);
      }
    };

    chrome.tabs.onUpdated.addListener(listener);

    // Timeout after max wait time
    setTimeout(() => {
      if (!resolved) {
        resolved = true;
        chrome.tabs.onUpdated.removeListener(listener);
        resolve();
      }
    }, PAGE_LOAD_TIMEOUT);
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Capture screenshot of the visible tab
 * Returns base64 jpeg data URL or undefined if capture fails
 */
async function captureScreenshot(tabId: number): Promise<string | undefined> {
  try {
    // Get the window ID for this tab
    const tab = await chrome.tabs.get(tabId);
    if (!tab.windowId) {
      console.warn('[Background] No window ID for tab');
      return undefined;
    }

    // Capture the visible tab as jpeg (smaller than png)
    const dataUrl = await chrome.tabs.captureVisibleTab(tab.windowId, {
      format: 'jpeg',
      quality: 60, // Lower quality for smaller size
    });

    console.log('[Background] Screenshot captured, size:', Math.round(dataUrl.length / 1024), 'KB');
    return dataUrl;
  } catch (error) {
    console.warn('[Background] Failed to capture screenshot:', error);
    return undefined;
  }
}

/**
 * Get DOM state with optional screenshot for VLM analysis
 */
export async function getDOMStateWithScreenshot(tabId: number): Promise<DOMState> {
  // Get base DOM state
  const domState = await getDOMState(tabId);

  // Capture screenshot
  const screenshot = await captureScreenshot(tabId);
  if (screenshot) {
    domState.screenshot = screenshot;
  }

  return domState;
}

// ============================================================================
// Content Script Ready Handler
// ============================================================================

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'CONTENT_SCRIPT_READY') {
    console.log('[Background] Content script ready in tab:', sender.tab?.id);
    sendResponse({ ok: true });
  } else if (message.type === 'PING') {
    sendResponse({ ok: true });
  } else if (message.type === 'VLM_PROGRESS') {
    // Forward VLM progress to vision engine
    visionEngine.handleProgressUpdate(message.progress);
    sendResponse({ ok: true });
  }
  return true;
});

// ============================================================================
// Extension Install Handler
// ============================================================================

chrome.runtime.onInstalled.addListener((details) => {
  console.log('[Background] Extension installed/updated:', details.reason);
});

console.log('[Background] Service worker started');
