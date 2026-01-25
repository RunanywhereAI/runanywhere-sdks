/**
 * WebLLM Engine Manager
 *
 * Manages the lifecycle of the WebLLM engine via an offscreen document.
 * The offscreen document has full web API access for model downloads.
 */

import type { ChatCompletionMessageParam } from '@mlc-ai/web-llm';
import { DEFAULT_MODEL, FALLBACK_MODELS } from '../shared/constants';

// ============================================================================
// Types
// ============================================================================

interface LLMEngineState {
  isLoading: boolean;
  loadProgress: number;
  currentModel: string | null;
  error: string | null;
  ready: boolean;
}

interface ChatOptions {
  temperature?: number;
  maxTokens?: number;
}

type ProgressCallback = (progress: number) => void;

// ============================================================================
// Offscreen Document Management
// ============================================================================

let creatingOffscreen: Promise<void> | null = null;

async function ensureOffscreenDocument(): Promise<void> {
  const offscreenUrl = chrome.runtime.getURL('src/offscreen/offscreen.html');

  // Check if already exists
  // @ts-expect-error - getContexts is available in Chrome 116+
  const existingContexts = await chrome.runtime.getContexts({
    contextTypes: ['OFFSCREEN_DOCUMENT'],
    documentUrls: [offscreenUrl],
  });

  if (existingContexts.length > 0) {
    return;
  }

  // Create if not exists
  if (creatingOffscreen) {
    await creatingOffscreen;
    return;
  }

  creatingOffscreen = chrome.offscreen.createDocument({
    url: offscreenUrl,
    reasons: [chrome.offscreen.Reason.WORKERS],
    justification: 'WebLLM requires web APIs for model loading and inference',
  });

  await creatingOffscreen;
  creatingOffscreen = null;
  console.log('[LLM Engine] Offscreen document created');
}

// ============================================================================
// LLM Engine Manager (Singleton)
// ============================================================================

class LLMEngineManager {
  private state: LLMEngineState = {
    isLoading: false,
    loadProgress: 0,
    currentModel: null,
    error: null,
    ready: false,
  };

  private progressCallbacks: Set<ProgressCallback> = new Set();
  private initializationPromise: Promise<void> | null = null;

  private initResolvers: Map<string, { resolve: () => void; reject: (e: Error) => void }> = new Map();

  constructor() {
    // Listen for progress and completion from offscreen document
    chrome.runtime.onMessage.addListener((message) => {
      if (message.type === 'LLM_PROGRESS') {
        this.state.loadProgress = message.progress;
        this.notifyProgress(message.progress);
      }

      if (message.type === 'LLM_INIT_COMPLETE') {
        const resolver = this.initResolvers.get(this.state.currentModel || '');
        if (resolver) {
          if (message.success) {
            resolver.resolve();
          } else {
            resolver.reject(new Error(message.error || 'Init failed'));
          }
          this.initResolvers.delete(this.state.currentModel || '');
        }
      }
    });
  }

  /**
   * Initialize the WebLLM engine with the specified model
   */
  async initialize(modelId?: string): Promise<void> {
    const targetModel = modelId || DEFAULT_MODEL;
    console.log(`[LLM Engine] initialize called with: ${targetModel}, current: ${this.state.currentModel}, ready: ${this.state.ready}`);

    // If already initialized with the same model, skip
    if (this.state.ready && this.state.currentModel === targetModel) {
      console.log(`[LLM Engine] Already initialized with ${targetModel}`);
      return;
    }

    // If currently initializing, wait for it
    if (this.initializationPromise) {
      console.log(`[LLM Engine] Waiting for current initialization...`);
      try {
        await this.initializationPromise;
      } catch {
        // Previous init failed, continue to reinitialize
      }
      // Check again after waiting
      if (this.state.ready && this.state.currentModel === targetModel) {
        return;
      }
    }

    // Reset state for new initialization
    console.log(`[LLM Engine] Starting fresh initialization for ${targetModel}`);
    this.state = {
      isLoading: true,
      loadProgress: 0,
      currentModel: targetModel,
      error: null,
      ready: false,
    };

    this.initializationPromise = this.doInitialize(targetModel);
    return this.initializationPromise;
  }

  private async doInitialize(modelId: string): Promise<void> {
    console.log(`[LLM Engine] doInitialize starting for ${modelId}`);

    const modelsToTry = [modelId, ...FALLBACK_MODELS.filter((m) => m !== modelId)];

    for (const model of modelsToTry) {
      try {
        console.log(`[LLM Engine] Initializing model: ${model}`);
        this.state.currentModel = model;

        // Ensure offscreen document exists
        await ensureOffscreenDocument();
        console.log('[LLM Engine] Offscreen document ready');

        // Create promise that resolves when init completes
        const initPromise = new Promise<void>((resolve, reject) => {
          this.initResolvers.set(model, { resolve, reject });

          // Timeout after 5 minutes for large models
          setTimeout(() => {
            if (this.initResolvers.has(model)) {
              this.initResolvers.delete(model);
              reject(new Error('Model initialization timeout'));
            }
          }, 300000);
        });

        // Send init request (returns immediately)
        await chrome.runtime.sendMessage({
          type: 'INIT_LLM',
          modelId: model,
        });

        // Wait for completion
        await initPromise;

        this.state.isLoading = false;
        this.state.loadProgress = 1;
        this.state.ready = true;
        this.notifyProgress(1);

        console.log(`[LLM Engine] Successfully loaded: ${model}`);
        return;
      } catch (error) {
        console.error(`[LLM Engine] Failed to load ${model}:`, error);
        this.initResolvers.delete(model);

        if (model === modelsToTry[modelsToTry.length - 1]) {
          this.state.error = error instanceof Error ? error.message : String(error);
          this.state.isLoading = false;
          throw error;
        }
        console.log(`[LLM Engine] Trying fallback model...`);
      }
    }
  }

  /**
   * Send a chat completion request to the LLM
   */
  async chat(
    messages: ChatCompletionMessageParam[],
    options: ChatOptions = {}
  ): Promise<string> {
    if (!this.state.ready) {
      throw new Error('LLM engine not initialized. Call initialize() first.');
    }

    const response = await chrome.runtime.sendMessage({
      type: 'LLM_CHAT',
      messages,
      options,
    });

    if (!response.success) {
      throw new Error(response.error || 'Chat failed');
    }

    return response.content;
  }

  /**
   * Send a streaming chat completion request (falls back to non-streaming)
   */
  async chatStream(
    messages: ChatCompletionMessageParam[],
    onChunk: (chunk: string) => void,
    options: ChatOptions = {}
  ): Promise<string> {
    // For now, use non-streaming and return all at once
    const content = await this.chat(messages, options);
    onChunk(content);
    return content;
  }

  /**
   * Get the current state of the engine
   */
  getState(): Readonly<LLMEngineState> {
    return { ...this.state };
  }

  /**
   * Check if the engine is ready for inference
   */
  isReady(): boolean {
    return this.state.ready && !this.state.isLoading;
  }

  /**
   * Subscribe to progress updates during model loading
   */
  onProgress(callback: ProgressCallback): () => void {
    this.progressCallbacks.add(callback);
    return () => this.progressCallbacks.delete(callback);
  }

  private notifyProgress(progress: number): void {
    this.progressCallbacks.forEach((cb) => {
      try {
        cb(progress);
      } catch (e) {
        console.error('[LLM Engine] Progress callback error:', e);
      }
    });
  }

  /**
   * Reset the engine state
   */
  async reset(): Promise<void> {
    console.log('[LLM Engine] Resetting engine');

    // Tell offscreen document to unload model
    try {
      await chrome.runtime.sendMessage({ type: 'RESET_LLM' });
    } catch (e) {
      console.warn('[LLM Engine] Failed to send RESET_LLM message:', e);
    }

    this.state = {
      isLoading: false,
      loadProgress: 0,
      currentModel: null,
      error: null,
      ready: false,
    };
    this.initializationPromise = null;
  }
}

// Export singleton instance
export const llmEngine = new LLMEngineManager();
