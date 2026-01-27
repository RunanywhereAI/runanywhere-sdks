/**
 * Offscreen Document for LLM Inference
 *
 * Runs in an offscreen document context which has full web API access.
 * Supports both Transformers.js (for LFM2) and WebLLM (for fallback models).
 */

import {
  pipeline,
  TextGenerationPipeline,
  env,
} from '@huggingface/transformers';
import {
  CreateMLCEngine,
  MLCEngineInterface,
  ChatCompletionMessageParam,
  prebuiltAppConfig,
} from '@mlc-ai/web-llm';
import {
  initializeVLM,
  describeImage,
  analyzePageForAction,
  isVLMReady,
  isVLMInitializing,
} from './vision';
import { LLM_ENGINE_TYPE } from '../shared/constants';

// ============================================================================
// State
// ============================================================================

// Transformers.js state
let transformersPipeline: TextGenerationPipeline | null = null;
let transformersModelId: string | null = null;

// WebLLM state (fallback)
let webllmEngine: MLCEngineInterface | null = null;
let webllmModelId: string | null = null;

let isInitializing = false;
let currentEngineType: 'transformers' | 'webllm' | null = null;

// Configure transformers.js
env.allowLocalModels = false;
env.useBrowserCache = true;

// ============================================================================
// Message Handling
// ============================================================================

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  console.log('[Offscreen] Received message:', message.type);

  if (message.type === 'INIT_LLM') {
    // Respond immediately, load async
    sendResponse({ success: true, loading: true });
    handleInit(message.modelId)
      .then((result) => {
        // Notify completion via separate message
        chrome.runtime.sendMessage({ type: 'LLM_INIT_COMPLETE', ...result }).catch(() => {});
      })
      .catch((error) => {
        chrome.runtime.sendMessage({ type: 'LLM_INIT_COMPLETE', success: false, error: error.message }).catch(() => {});
      });
    return false; // Don't keep channel open
  }

  if (message.type === 'LLM_CHAT') {
    handleChat(message.messages, message.options)
      .then((result) => sendResponse(result))
      .catch((error) => sendResponse({ success: false, error: error.message }));
    return true;
  }

  if (message.type === 'LLM_STATUS') {
    const ready = currentEngineType === 'transformers'
      ? transformersPipeline !== null
      : webllmEngine !== null;
    sendResponse({
      success: true,
      ready: ready && !isInitializing,
      initializing: isInitializing,
      currentModel: transformersModelId || webllmModelId,
      engineType: currentEngineType,
    });
    return true;
  }

  if (message.type === 'RESET_LLM') {
    handleReset()
      .then((result) => sendResponse(result))
      .catch((error) => sendResponse({ success: false, error: error.message }));
    return true;
  }

  // VLM (Vision) message handlers
  if (message.type === 'INIT_VLM') {
    handleInitVLM(message.modelSize)
      .then((result) => sendResponse(result))
      .catch((error) => sendResponse({ success: false, error: error.message }));
    return true;
  }

  if (message.type === 'VLM_DESCRIBE') {
    handleVLMDescribe(message.imageData, message.prompt)
      .then((result) => sendResponse(result))
      .catch((error) => sendResponse({ success: false, error: error.message }));
    return true;
  }

  if (message.type === 'VLM_ANALYZE') {
    handleVLMAnalyze(message.imageData, message.task, message.currentStep)
      .then((result) => sendResponse(result))
      .catch((error) => sendResponse({ success: false, error: error.message }));
    return true;
  }

  if (message.type === 'VLM_STATUS') {
    sendResponse({
      success: true,
      ready: isVLMReady(),
      initializing: isVLMInitializing(),
    });
    return true;
  }
});

// ============================================================================
// LLM Functions
// ============================================================================

/**
 * Determine if a model ID is a Transformers.js model (LFM2) or WebLLM model
 */
function isTransformersModel(modelId: string): boolean {
  return modelId.includes('LiquidAI') || modelId.includes('ONNX') || modelId.startsWith('onnx-community/');
}

async function handleInit(modelId: string): Promise<{ success: boolean; error?: string }> {
  console.log(`[Offscreen] handleInit called with model: ${modelId}`);

  const useTransformers = isTransformersModel(modelId);
  console.log(`[Offscreen] Using engine: ${useTransformers ? 'transformers' : 'webllm'}`);

  if (useTransformers) {
    return handleInitTransformers(modelId);
  } else {
    return handleInitWebLLM(modelId);
  }
}

/**
 * Initialize Transformers.js pipeline for LFM2
 * Tries WebGPU first, falls back to WASM if unavailable
 */
async function handleInitTransformers(modelId: string): Promise<{ success: boolean; error?: string }> {
  // If same model already loaded
  if (transformersPipeline && transformersModelId === modelId && !isInitializing) {
    console.log('[Offscreen] Transformers pipeline already initialized with same model');
    return { success: true };
  }

  if (isInitializing) {
    console.log('[Offscreen] Already initializing, waiting...');
    let waited = 0;
    while (isInitializing && waited < 120000) {
      await new Promise(r => setTimeout(r, 500));
      waited += 500;
    }
    if (transformersPipeline && transformersModelId === modelId) {
      return { success: true };
    }
    if (isInitializing) {
      return { success: false, error: 'Initialization timeout' };
    }
  }

  isInitializing = true;
  transformersPipeline = null;
  transformersModelId = null;
  currentEngineType = 'transformers';

  const progressCallback = (progress: { status: string; progress?: number; file?: string }) => {
    if (progress.progress !== undefined) {
      const progressValue = Math.min(0.9, progress.progress / 100);
      console.log(`[Offscreen] Loading: ${Math.round(progressValue * 100)}% - ${progress.status || ''}`);
      chrome.runtime.sendMessage({
        type: 'LLM_PROGRESS',
        progress: progressValue,
        text: progress.file || progress.status,
      }).catch(() => {});
    }
  };

  // Check WebGPU availability
  const hasWebGPU = typeof navigator !== 'undefined' && 'gpu' in navigator;
  console.log(`[Offscreen] WebGPU available: ${hasWebGPU}`);

  // Try WebGPU first if available
  if (hasWebGPU) {
    try {
      console.log(`[Offscreen] Trying WebGPU for: ${modelId}`);
      chrome.runtime.sendMessage({
        type: 'LLM_PROGRESS',
        progress: 0.1,
        text: 'Loading model (WebGPU)...',
      }).catch(() => {});

      const pipe = await pipeline('text-generation', modelId, {
        device: 'webgpu',
        dtype: 'q4',
        progress_callback: progressCallback,
      }) as TextGenerationPipeline;

      transformersPipeline = pipe;
      transformersModelId = modelId;
      isInitializing = false;
      currentEngineType = 'transformers';
      webllmEngine = null;
      webllmModelId = null;

      console.log(`[Offscreen] Transformers pipeline initialized (WebGPU) for ${modelId}`);
      chrome.runtime.sendMessage({ type: 'LLM_PROGRESS', progress: 1.0, text: 'Model loaded (WebGPU)' }).catch(() => {});
      return { success: true };
    } catch (webgpuError) {
      console.warn('[Offscreen] WebGPU failed, trying WASM fallback:', webgpuError);
    }
  }

  // Fallback to WASM
  try {
    console.log(`[Offscreen] Trying WASM for: ${modelId}`);
    chrome.runtime.sendMessage({
      type: 'LLM_PROGRESS',
      progress: 0.1,
      text: 'Loading model (CPU)...',
    }).catch(() => {});

    const pipe = await pipeline('text-generation', modelId, {
      device: 'wasm',
      progress_callback: progressCallback,
    }) as TextGenerationPipeline;

    transformersPipeline = pipe;
    transformersModelId = modelId;
    isInitializing = false;
    currentEngineType = 'transformers';
    webllmEngine = null;
    webllmModelId = null;

    console.log(`[Offscreen] Transformers pipeline initialized (WASM) for ${modelId}`);
    chrome.runtime.sendMessage({ type: 'LLM_PROGRESS', progress: 1.0, text: 'Model loaded (CPU)' }).catch(() => {});
    return { success: true };
  } catch (wasmError) {
    isInitializing = false;
    transformersPipeline = null;
    transformersModelId = null;
    currentEngineType = null;
    console.error('[Offscreen] Both WebGPU and WASM failed:', wasmError);
    return { success: false, error: wasmError instanceof Error ? wasmError.message : String(wasmError) };
  }
}

/**
 * Initialize WebLLM engine (fallback)
 */
async function handleInitWebLLM(modelId: string): Promise<{ success: boolean; error?: string }> {
  if (webllmEngine && webllmModelId === modelId && !isInitializing) {
    console.log('[Offscreen] WebLLM engine already initialized with same model');
    return { success: true };
  }

  if (webllmEngine && webllmModelId && webllmModelId !== modelId) {
    console.log(`[Offscreen] Switching WebLLM model from ${webllmModelId} to ${modelId}`);
    webllmEngine = null;
    webllmModelId = null;
  }

  if (isInitializing) {
    console.log('[Offscreen] Already initializing, waiting...');
    let waited = 0;
    while (isInitializing && waited < 60000) {
      await new Promise(r => setTimeout(r, 500));
      waited += 500;
    }
    if (webllmEngine && webllmModelId === modelId) {
      return { success: true };
    }
    if (isInitializing) {
      return { success: false, error: 'Initialization timeout' };
    }
  }

  isInitializing = true;
  webllmEngine = null;
  webllmModelId = null;
  currentEngineType = 'webllm';

  try {
    console.log(`[Offscreen] Initializing WebLLM engine: ${modelId}`);

    const newEngine = await CreateMLCEngine(modelId, {
      initProgressCallback: (report) => {
        console.log(`[Offscreen] Loading: ${Math.round(report.progress * 100)}% - ${report.text || ''}`);
        chrome.runtime.sendMessage({
          type: 'LLM_PROGRESS',
          progress: report.progress,
          text: report.text,
        }).catch(() => {});
      },
      logLevel: 'INFO',
      appConfig: {
        ...prebuiltAppConfig,
        useIndexedDBCache: true,
      },
    });

    console.log(`[Offscreen] WebLLM engine created`);
    webllmEngine = newEngine;
    webllmModelId = modelId;
    isInitializing = false;
    currentEngineType = 'webllm';

    // Clear Transformers if it was loaded
    transformersPipeline = null;
    transformersModelId = null;

    console.log(`[Offscreen] WebLLM engine initialized for ${modelId}`);
    return { success: true };
  } catch (error) {
    isInitializing = false;
    webllmEngine = null;
    webllmModelId = null;
    currentEngineType = null;
    console.error('[Offscreen] Failed to initialize WebLLM:', error);
    return { success: false, error: error instanceof Error ? error.message : String(error) };
  }
}

async function handleReset(): Promise<{ success: boolean }> {
  console.log('[Offscreen] Resetting LLM engines');
  transformersPipeline = null;
  transformersModelId = null;
  webllmEngine = null;
  webllmModelId = null;
  isInitializing = false;
  currentEngineType = null;
  return { success: true };
}

async function handleChat(
  messages: ChatCompletionMessageParam[],
  options: { temperature?: number; maxTokens?: number } = {}
): Promise<{ success: boolean; content?: string; error?: string }> {
  console.log(`[Offscreen] handleChat called, engineType: ${currentEngineType}`);

  if (currentEngineType === 'transformers') {
    return handleChatTransformers(messages, options);
  } else if (currentEngineType === 'webllm') {
    return handleChatWebLLM(messages, options);
  } else {
    return { success: false, error: 'No LLM engine initialized' };
  }
}

/**
 * Handle chat with Transformers.js pipeline
 */
async function handleChatTransformers(
  messages: ChatCompletionMessageParam[],
  options: { temperature?: number; maxTokens?: number } = {}
): Promise<{ success: boolean; content?: string; error?: string }> {
  if (!transformersPipeline) {
    return { success: false, error: 'Transformers pipeline not initialized' };
  }

  try {
    // Convert messages to a single prompt
    const prompt = formatMessagesAsPrompt(messages);
    console.log(`[Offscreen] Transformers prompt length: ${prompt.length} chars`);

    // Generate response
    const output = await transformersPipeline(prompt, {
      max_new_tokens: options.maxTokens ?? 512,
      temperature: options.temperature ?? 0.3,
      do_sample: (options.temperature ?? 0.3) > 0,
      return_full_text: false,
    });

    // Extract the generated text
    const result = output as Array<{ generated_text: string }>;
    const content = result[0]?.generated_text?.trim();

    if (!content) {
      return { success: false, error: 'Empty response from model' };
    }

    console.log(`[Offscreen] Transformers response length: ${content.length} chars`);
    return { success: true, content };
  } catch (error) {
    console.error('[Offscreen] Transformers chat error:', error);
    return { success: false, error: error instanceof Error ? error.message : String(error) };
  }
}

/**
 * Handle chat with WebLLM engine
 */
async function handleChatWebLLM(
  messages: ChatCompletionMessageParam[],
  options: { temperature?: number; maxTokens?: number } = {}
): Promise<{ success: boolean; content?: string; error?: string }> {
  if (!webllmEngine || !webllmModelId) {
    return { success: false, error: 'WebLLM engine not initialized' };
  }

  if (isInitializing) {
    return { success: false, error: 'Engine is still initializing' };
  }

  try {
    const response = await webllmEngine.chat.completions.create({
      messages,
      temperature: options.temperature ?? 0.3,
      max_tokens: options.maxTokens ?? 4096,
      stream: false,
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      return { success: false, error: 'Empty response from LLM' };
    }

    return { success: true, content };
  } catch (error) {
    console.error('[Offscreen] WebLLM chat error:', error);
    const errorMsg = error instanceof Error ? error.message : String(error);

    if (errorMsg.includes('Model not loaded')) {
      webllmEngine = null;
      webllmModelId = null;
    }

    return { success: false, error: errorMsg };
  }
}

/**
 * Format chat messages as a prompt string for LFM2 models
 * Uses ChatML format: <|im_start|>role\ncontent<|im_end|>
 */
function formatMessagesAsPrompt(messages: ChatCompletionMessageParam[]): string {
  const parts: string[] = [];

  // Add start of text token
  parts.push('<|startoftext|>');

  for (const msg of messages) {
    if (msg.role === 'system') {
      parts.push(`<|im_start|>system\n${msg.content}<|im_end|>\n`);
    } else if (msg.role === 'user') {
      parts.push(`<|im_start|>user\n${msg.content}<|im_end|>\n`);
    } else if (msg.role === 'assistant') {
      parts.push(`<|im_start|>assistant\n${msg.content}<|im_end|>\n`);
    }
  }

  // Add the assistant prefix to prompt generation
  parts.push('<|im_start|>assistant\n');

  return parts.join('');
}

// ============================================================================
// VLM Functions
// ============================================================================

async function handleInitVLM(
  modelSize: 'tiny' | 'small' | 'base' = 'tiny'
): Promise<{ success: boolean; error?: string }> {
  console.log(`[Offscreen] Initializing VLM with size: ${modelSize}`);

  try {
    const success = await initializeVLM(modelSize, (progress) => {
      chrome.runtime.sendMessage({
        type: 'VLM_PROGRESS',
        progress,
      }).catch(() => {});
    });

    return { success };
  } catch (error) {
    console.error('[Offscreen] VLM initialization failed:', error);
    return { success: false, error: error instanceof Error ? error.message : String(error) };
  }
}

async function handleVLMDescribe(
  imageData: string,
  prompt?: string
): Promise<{ success: boolean; description?: string; error?: string }> {
  if (!isVLMReady()) {
    return { success: false, error: 'VLM not initialized' };
  }

  try {
    const description = await describeImage(imageData, prompt);
    return { success: true, description };
  } catch (error) {
    console.error('[Offscreen] VLM describe error:', error);
    return { success: false, error: error instanceof Error ? error.message : String(error) };
  }
}

async function handleVLMAnalyze(
  imageData: string,
  task: string,
  currentStep: string
): Promise<{ success: boolean; analysis?: string; error?: string }> {
  if (!isVLMReady()) {
    return { success: false, error: 'VLM not initialized' };
  }

  try {
    const analysis = await analyzePageForAction(imageData, task, currentStep);
    return { success: true, analysis };
  } catch (error) {
    console.error('[Offscreen] VLM analyze error:', error);
    return { success: false, error: error instanceof Error ? error.message : String(error) };
  }
}

console.log('[Offscreen] Script loaded with Transformers.js + WebLLM support');
