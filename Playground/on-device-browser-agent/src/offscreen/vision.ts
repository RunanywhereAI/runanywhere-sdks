/**
 * Vision Module for VLM Inference
 *
 * Uses Transformers.js with SmolVLM for image understanding.
 * Runs in the offscreen document context with WebGPU acceleration.
 */

import { pipeline, env, type ImageToTextPipeline } from '@huggingface/transformers';

// Configure Transformers.js
env.allowLocalModels = false;
env.useBrowserCache = true;

// ============================================================================
// State
// ============================================================================

let vlmPipeline: ImageToTextPipeline | null = null;
let isInitializing = false;

// Model options (smallest to largest)
const VLM_MODELS = {
  tiny: 'HuggingFaceTB/SmolVLM-256M-Instruct',
  small: 'HuggingFaceTB/SmolVLM-500M-Instruct',
  base: 'HuggingFaceTB/SmolVLM-Instruct',
};

// ============================================================================
// Initialization
// ============================================================================

export async function initializeVLM(
  modelSize: 'tiny' | 'small' | 'base' = 'tiny',
  onProgress?: (progress: number) => void
): Promise<boolean> {
  if (vlmPipeline) {
    console.log('[Vision] VLM already initialized');
    return true;
  }

  if (isInitializing) {
    console.log('[Vision] Already initializing');
    return false;
  }

  isInitializing = true;
  const modelId = VLM_MODELS[modelSize];
  console.log(`[Vision] Initializing VLM: ${modelId}`);

  try {
    vlmPipeline = await pipeline('image-to-text', modelId, {
      device: 'webgpu',
      dtype: 'q4', // 4-bit quantization for efficiency
      progress_callback: (progress: { progress: number; status: string }) => {
        console.log(`[Vision] Loading: ${Math.round(progress.progress * 100)}%`);
        onProgress?.(progress.progress);
      },
    });

    isInitializing = false;
    console.log('[Vision] VLM initialized successfully');
    return true;
  } catch (error) {
    isInitializing = false;
    console.error('[Vision] Failed to initialize VLM:', error);
    throw error;
  }
}

// ============================================================================
// Inference
// ============================================================================

export async function describeImage(
  imageData: string, // base64 encoded image
  prompt?: string
): Promise<string> {
  if (!vlmPipeline) {
    throw new Error('VLM not initialized. Call initializeVLM() first.');
  }

  const defaultPrompt = 'Describe what you see on this webpage. List all interactive elements like buttons, links, and input fields with their labels.';
  const fullPrompt = prompt || defaultPrompt;

  try {
    // SmolVLM expects the image and prompt together
    const result = await vlmPipeline(imageData, {
      max_new_tokens: 512,
      prompt: fullPrompt,
    });

    // Extract text from result
    const output = Array.isArray(result) ? result[0] : result;
    return output.generated_text || String(output);
  } catch (error) {
    console.error('[Vision] Inference error:', error);
    throw error;
  }
}

export async function analyzePageForAction(
  imageData: string,
  task: string,
  currentStep: string
): Promise<string> {
  const prompt = `You are a web automation assistant.

Task: ${task}
Current step: ${currentStep}

Look at this webpage screenshot and describe:
1. What page is this? (URL/title if visible)
2. What interactive elements are visible? (buttons, links, inputs)
3. Which element should be clicked/interacted with to complete the current step?
4. What is the exact text or identifier of that element?

Be specific and concise.`;

  return describeImage(imageData, prompt);
}

// ============================================================================
// Status
// ============================================================================

export function isVLMReady(): boolean {
  return vlmPipeline !== null && !isInitializing;
}

export function isVLMInitializing(): boolean {
  return isInitializing;
}
