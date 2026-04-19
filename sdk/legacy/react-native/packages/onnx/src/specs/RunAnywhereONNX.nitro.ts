/**
 * RunAnywhereONNX Nitrogen Spec
 *
 * ONNX backend interface for speech processing:
 * - Backend Registration
 * - Speech-to-Text (STT)
 * - Text-to-Speech (TTS)
 * - Voice Activity Detection (VAD)
 * - Voice Agent (full pipeline orchestration)
 *
 * Matches Swift SDK: ONNXRuntime/ONNX.swift + CppBridge STT/TTS/VAD extensions
 */
import type { HybridObject } from 'react-native-nitro-modules';

/**
 * ONNX speech processing native interface
 *
 * This interface provides ONNX-based STT, TTS, and VAD capabilities.
 * Requires @runanywhere/core to be initialized first.
 */
export interface RunAnywhereONNX
  extends HybridObject<{
    ios: 'c++';
    android: 'c++';
  }> {
  // ============================================================================
  // Backend Registration
  // Matches Swift: ONNX.register(), ONNX.unregister()
  // ============================================================================

  /**
   * Register the ONNX backend with the C++ service registry.
   * Registers STT, TTS, and VAD providers.
   * Safe to call multiple times - subsequent calls are no-ops.
   * @returns true if registered successfully (or already registered)
   */
  registerBackend(): Promise<boolean>;

  /**
   * Unregister the ONNX backend from the C++ service registry.
   * @returns true if unregistered successfully
   */
  unregisterBackend(): Promise<boolean>;

  /**
   * Check if the ONNX backend is registered
   * @returns true if backend is registered
   */
  isBackendRegistered(): Promise<boolean>;

  // ============================================================================
  // Speech-to-Text (STT)
  // Matches Swift: CppBridge+STT.swift, RunAnywhere+STT.swift
  // ============================================================================

  /**
   * Load an STT model
   * @param path Path to the model directory
   * @param modelType Model type (e.g., 'whisper', 'whisper-tiny')
   * @param configJson Optional JSON configuration
   * @returns true if loaded successfully
   */
  loadSTTModel(
    path: string,
    modelType: string,
    configJson?: string
  ): Promise<boolean>;

  /**
   * Check if an STT model is loaded
   */
  isSTTModelLoaded(): Promise<boolean>;

  /**
   * Unload the current STT model
   */
  unloadSTTModel(): Promise<boolean>;

  /**
   * Transcribe audio data
   * @param audioBase64 Base64-encoded float32 PCM audio
   * @param sampleRate Audio sample rate (e.g., 16000)
   * @param language Language code (e.g., 'en')
   * @returns JSON string with transcription result:
   *   - text: Transcribed text
   *   - confidence: Confidence score (0-1)
   *   - isFinal: Whether this is a final result
   */
  transcribe(
    audioBase64: string,
    sampleRate: number,
    language?: string
  ): Promise<string>;

  /**
   * Transcribe audio from a file path
   * Native code handles M4A/WAV/CAF to PCM conversion
   * @param filePath Path to the audio file
   * @param language Language code (e.g., 'en')
   * @returns JSON string with transcription result
   */
  transcribeFile(filePath: string, language?: string): Promise<string>;

  /**
   * Check if STT supports streaming
   */
  supportsSTTStreaming(): Promise<boolean>;

  // ============================================================================
  // Text-to-Speech (TTS)
  // Matches Swift: CppBridge+TTS.swift, RunAnywhere+TTS.swift
  // ============================================================================

  /**
   * Load a TTS model
   * @param path Path to the model directory
   * @param modelType Model type (e.g., 'piper', 'vits')
   * @param configJson Optional JSON configuration
   * @returns true if loaded successfully
   */
  loadTTSModel(
    path: string,
    modelType: string,
    configJson?: string
  ): Promise<boolean>;

  /**
   * Check if a TTS model is loaded
   */
  isTTSModelLoaded(): Promise<boolean>;

  /**
   * Unload the current TTS model
   */
  unloadTTSModel(): Promise<boolean>;

  /**
   * Synthesize speech from text
   * @param text Text to synthesize
   * @param voiceId Voice ID to use
   * @param speedRate Speed multiplier (1.0 = normal)
   * @param pitchShift Pitch adjustment
   * @returns JSON string with audio data:
   *   - audio: Base64-encoded audio data
   *   - sampleRate: Audio sample rate
   *   - numSamples: Number of samples
   *   - duration: Duration in seconds
   */
  synthesize(
    text: string,
    voiceId: string,
    speedRate: number,
    pitchShift: number
  ): Promise<string>;

  /**
   * Get available TTS voices
   * @returns JSON array of voice info
   */
  getTTSVoices(): Promise<string>;

  // ============================================================================
  // Voice Activity Detection (VAD)
  // Matches Swift: CppBridge+VAD.swift, RunAnywhere+VAD.swift
  // ============================================================================

  /**
   * Load a VAD model
   * @param path Path to the VAD model
   * @param configJson Optional configuration JSON
   * @returns true if loaded successfully
   */
  loadVADModel(path: string, configJson?: string): Promise<boolean>;

  /**
   * Check if VAD model is loaded
   */
  isVADModelLoaded(): Promise<boolean>;

  /**
   * Unload the current VAD model
   */
  unloadVADModel(): Promise<boolean>;

  /**
   * Process audio for voice activity detection
   * @param audioBase64 Base64-encoded audio data
   * @param optionsJson Optional processing options
   * @returns JSON string with VAD result:
   *   - isSpeech: Whether speech is detected
   *   - speechProbability: Probability of speech (0-1)
   *   - startTime: Speech start time (if detected)
   *   - endTime: Speech end time (if detected)
   */
  processVAD(audioBase64: string, optionsJson?: string): Promise<string>;

  /**
   * Reset VAD state (for continuous processing)
   */
  resetVAD(): Promise<void>;

  /**
   * Initialize VAD with configuration
   * @param configJson Optional configuration JSON
   */
  initializeVAD(configJson?: string): Promise<boolean>;

  /**
   * Cleanup VAD resources
   */
  cleanupVAD(): Promise<void>;

  /**
   * Start VAD processing
   */
  startVAD(): Promise<boolean>;

  /**
   * Stop VAD processing
   */
  stopVAD(): Promise<boolean>;

  // ============================================================================
  // Voice Agent (Full Voice Pipeline)
  // Matches Swift: CppBridge+VoiceAgent.swift, RunAnywhere+VoiceAgent.swift
  // ============================================================================

  /**
   * Initialize voice agent with configuration
   * @param configJson Configuration JSON with STT/LLM/TTS model IDs
   * @returns true if initialized successfully
   */
  initializeVoiceAgent(configJson: string): Promise<boolean>;

  /**
   * Check if voice agent is ready (all components initialized)
   */
  isVoiceAgentReady(): Promise<boolean>;

  /**
   * Process a complete voice turn: audio -> transcription -> response -> speech
   * Note: LLM generation requires @runanywhere/llamacpp to be installed
   * @param audioBase64 Base64-encoded audio input
   * @returns JSON with transcription, response, and synthesized audio
   */
  processVoiceTurn(audioBase64: string): Promise<string>;

  /**
   * Cleanup voice agent resources
   */
  cleanupVoiceAgent(): Promise<void>;

  // ============================================================================
  // Utilities
  // ============================================================================

  /**
   * Get the last error message from the ONNX backend
   */
  getLastError(): Promise<string>;

  /**
   * Get current memory usage of the ONNX backend
   * @returns Memory usage in bytes
   */
  getMemoryUsage(): Promise<number>;
}
