/**
 * Vision Engine
 *
 * Manages VLM (Vision Language Model) for screenshot-based page understanding.
 * Uses Transformers.js with SmolVLM running in the offscreen document.
 */

type VLMModelSize = 'tiny' | 'small' | 'base';
type ProgressCallback = (progress: number) => void;

class VisionEngine {
  private isReady = false;
  private isInitializing = false;
  private progressListeners: Set<ProgressCallback> = new Set();

  /**
   * Initialize the VLM model
   */
  async initialize(modelSize: VLMModelSize = 'tiny'): Promise<void> {
    if (this.isReady) {
      console.log('[VisionEngine] Already initialized');
      return;
    }

    if (this.isInitializing) {
      console.log('[VisionEngine] Already initializing');
      return;
    }

    this.isInitializing = true;

    try {
      // Ensure offscreen document exists
      await this.ensureOffscreenDocument();

      console.log(`[VisionEngine] Initializing VLM (size: ${modelSize})...`);

      const response = await chrome.runtime.sendMessage({
        type: 'INIT_VLM',
        modelSize,
      });

      if (!response?.success) {
        throw new Error(response?.error || 'VLM initialization failed');
      }

      this.isReady = true;
      console.log('[VisionEngine] VLM initialized successfully');
    } finally {
      this.isInitializing = false;
    }
  }

  /**
   * Capture a screenshot of the current tab
   */
  async captureScreenshot(tabId?: number): Promise<string> {
    const targetTabId = tabId ?? (await this.getActiveTabId());

    if (!targetTabId) {
      throw new Error('No active tab to capture');
    }

    const tab = await chrome.tabs.get(targetTabId);

    // Can't capture chrome:// or extension pages
    if (tab.url?.startsWith('chrome://') || tab.url?.startsWith('chrome-extension://')) {
      throw new Error('Cannot capture browser internal pages');
    }

    // Capture the visible area of the tab
    const dataUrl = await chrome.tabs.captureVisibleTab(tab.windowId, {
      format: 'png',
      quality: 90,
    });

    return dataUrl;
  }

  /**
   * Describe what's visible in a screenshot
   */
  async describeScreenshot(imageData: string, prompt?: string): Promise<string> {
    if (!this.isReady) {
      throw new Error('VLM not initialized. Call initialize() first.');
    }

    const response = await chrome.runtime.sendMessage({
      type: 'VLM_DESCRIBE',
      imageData,
      prompt,
    });

    if (!response?.success) {
      throw new Error(response?.error || 'VLM describe failed');
    }

    return response.description;
  }

  /**
   * Analyze a page screenshot for navigation actions
   */
  async analyzeForAction(
    imageData: string,
    task: string,
    currentStep: string
  ): Promise<string> {
    if (!this.isReady) {
      throw new Error('VLM not initialized. Call initialize() first.');
    }

    const response = await chrome.runtime.sendMessage({
      type: 'VLM_ANALYZE',
      imageData,
      task,
      currentStep,
    });

    if (!response?.success) {
      throw new Error(response?.error || 'VLM analyze failed');
    }

    return response.analysis;
  }

  /**
   * Capture and analyze current tab in one call
   */
  async captureAndAnalyze(
    task: string,
    currentStep: string,
    tabId?: number
  ): Promise<{ screenshot: string; analysis: string }> {
    const screenshot = await this.captureScreenshot(tabId);
    const analysis = await this.analyzeForAction(screenshot, task, currentStep);
    return { screenshot, analysis };
  }

  /**
   * Get VLM status
   */
  async getStatus(): Promise<{ ready: boolean; initializing: boolean }> {
    try {
      const response = await chrome.runtime.sendMessage({ type: 'VLM_STATUS' });
      return {
        ready: response?.ready ?? false,
        initializing: response?.initializing ?? false,
      };
    } catch {
      return { ready: false, initializing: false };
    }
  }

  /**
   * Subscribe to VLM loading progress
   */
  onProgress(callback: ProgressCallback): () => void {
    this.progressListeners.add(callback);
    return () => this.progressListeners.delete(callback);
  }

  /**
   * Handle progress updates from offscreen document
   */
  handleProgressUpdate(progress: number): void {
    this.progressListeners.forEach((listener) => {
      try {
        listener(progress);
      } catch (e) {
        console.error('[VisionEngine] Progress listener error:', e);
      }
    });
  }

  private async getActiveTabId(): Promise<number | undefined> {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    return tab?.id;
  }

  private async ensureOffscreenDocument(): Promise<void> {
    const offscreenUrl = chrome.runtime.getURL('src/offscreen/offscreen.html');

    const existingContexts = await chrome.runtime.getContexts({
      contextTypes: ['OFFSCREEN_DOCUMENT' as chrome.runtime.ContextType],
      documentUrls: [offscreenUrl],
    });

    if (existingContexts.length > 0) {
      return;
    }

    await chrome.offscreen.createDocument({
      url: offscreenUrl,
      reasons: [chrome.offscreen.Reason.WORKERS],
      justification: 'VLM requires web APIs for model loading and inference',
    });
  }
}

// Export singleton instance
export const visionEngine = new VisionEngine();
