/**
 * RunAnywhereLlama Nitrogen Spec
 *
 * LlamaCPP backend interface for Llama-based text generation:
 * - Backend Registration
 * - Model Loading/Unloading
 * - Text Generation (non-streaming and streaming)
 * - Structured Output (JSON schema generation)
 *
 * Matches Swift SDK: LlamaCPPRuntime/LlamaCPP.swift + CppBridge+LLM.swift
 */
import type { HybridObject } from 'react-native-nitro-modules';

/**
 * Llama text generation native interface
 *
 * This interface provides Llama-based LLM capabilities.
 * Requires @runanywhere/core to be initialized first.
 */
export interface RunAnywhereLlama
  extends HybridObject<{
    ios: 'c++';
    android: 'c++';
  }> {
  // ============================================================================
  // Backend Registration
  // Matches Swift: LlamaCPP.register(), LlamaCPP.unregister()
  // ============================================================================

  /**
   * Register the LlamaCPP backend with the C++ service registry.
   * Calls rac_backend_llamacpp_register() from runanywhere-binaries.
   * Safe to call multiple times - subsequent calls are no-ops.
   * @returns true if registered successfully (or already registered)
   */
  registerBackend(): Promise<boolean>;

  /**
   * Unregister the LlamaCPP backend from the C++ service registry.
   * @returns true if unregistered successfully
   */
  unregisterBackend(): Promise<boolean>;

  /**
   * Check if the LlamaCPP backend is registered
   * @returns true if backend is registered
   */
  isBackendRegistered(): Promise<boolean>;

  // ============================================================================
  // Model Loading
  // Matches Swift: CppBridge+LLM.swift loadTextModel/unloadTextModel
  // ============================================================================

  /**
   * Load a Llama model for text generation
   * @param path Path to the model file (.gguf)
   * @param modelId Optional unique identifier for the model
   * @param modelName Optional human-readable name for the model
   * @param configJson Optional JSON configuration (context_length, gpu_layers, etc.)
   * @returns true if loaded successfully
   */
  loadModel(
    path: string,
    modelId?: string,
    modelName?: string,
    configJson?: string
  ): Promise<boolean>;

  /**
   * Check if a Llama model is loaded
   */
  isModelLoaded(): Promise<boolean>;

  /**
   * Unload the current Llama model
   */
  unloadModel(): Promise<boolean>;

  /**
   * Get info about the currently loaded model
   * @returns JSON with model info or empty if not loaded
   */
  getModelInfo(): Promise<string>;

  // ============================================================================
  // Text Generation
  // Matches Swift: RunAnywhere+TextGeneration.swift
  // ============================================================================

  /**
   * Generate text (non-streaming)
   * @param prompt The prompt text
   * @param optionsJson JSON string with generation options:
   *   - max_tokens: Maximum tokens to generate (default: 512)
   *   - temperature: Sampling temperature (default: 0.7)
   *   - top_p: Nucleus sampling parameter (default: 0.9)
   *   - top_k: Top-k sampling parameter (default: 40)
   *   - system_prompt: Optional system prompt
   * @returns JSON string with generation result:
   *   - text: Generated text
   *   - tokensUsed: Number of tokens generated
   *   - latencyMs: Generation time in milliseconds
   *   - cancelled: Whether generation was cancelled
   */
  generate(prompt: string, optionsJson?: string): Promise<string>;

  /**
   * Generate text with streaming callback
   * @param prompt The prompt text
   * @param optionsJson JSON string with generation options
   * @param callback Called for each token with (token, isComplete)
   * @returns Complete generated text
   */
  generateStream(
    prompt: string,
    optionsJson: string,
    callback: (token: string, isComplete: boolean) => void
  ): Promise<string>;

  /**
   * Cancel ongoing text generation
   * @returns true if cancellation was successful
   */
  cancelGeneration(): Promise<boolean>;

  // ============================================================================
  // Structured Output
  // Matches Swift: RunAnywhere+StructuredOutput.swift
  // ============================================================================

  /**
   * Generate structured output following a JSON schema
   * Uses constrained generation to ensure output conforms to schema
   * @param prompt The prompt text
   * @param schema JSON schema string defining the output structure
   * @param optionsJson Optional generation options
   * @returns JSON string conforming to the provided schema
   */
  generateStructured(
    prompt: string,
    schema: string,
    optionsJson?: string
  ): Promise<string>;

  // ============================================================================
  // Utilities
  // ============================================================================

  /**
   * Get the last error message from the Llama backend
   */
  getLastError(): Promise<string>;

  /**
   * Get current memory usage of the Llama backend
   * @returns Memory usage in bytes
   */
  getMemoryUsage(): Promise<number>;
}
