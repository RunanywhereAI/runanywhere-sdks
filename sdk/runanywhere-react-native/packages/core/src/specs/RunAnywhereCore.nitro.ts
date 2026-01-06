/**
 * RunAnywhereCore Nitrogen Spec
 *
 * Core SDK interface - includes only core functionality:
 * - SDK Lifecycle (init, destroy)
 * - Authentication
 * - Device Registration
 * - Model Registry
 * - Download Service
 * - Storage
 * - Events
 * - HTTP Client
 * - Utilities
 *
 * NO LLM/STT/TTS/VAD/VoiceAgent methods - those are in separate packages.
 *
 * Matches Swift SDK: RunAnywhere.swift + CppBridge core extensions
 */
import type { HybridObject } from 'react-native-nitro-modules';

/**
 * Core RunAnywhere native interface
 *
 * This interface provides core SDK functionality without any inference backends.
 * For LLM, STT, TTS, VAD capabilities, use the separate packages:
 * - @runanywhere/llamacpp for text generation
 * - @runanywhere/onnx for speech processing
 */
export interface RunAnywhereCore
  extends HybridObject<{
    ios: 'c++';
    android: 'c++';
  }> {
  // ============================================================================
  // SDK Lifecycle
  // Matches Swift: CppBridge+Init.swift
  // ============================================================================

  /**
   * Initialize the SDK with configuration
   * @param configJson JSON string with apiKey, baseURL, environment
   * @returns true if initialized successfully
   */
  initialize(configJson: string): Promise<boolean>;

  /**
   * Destroy the SDK and clean up resources
   */
  destroy(): Promise<void>;

  /**
   * Check if SDK is initialized
   */
  isInitialized(): Promise<boolean>;

  /**
   * Get backend info as JSON string
   */
  getBackendInfo(): Promise<string>;

  // ============================================================================
  // Authentication
  // Matches Swift: CppBridge+Auth.swift
  // ============================================================================

  /**
   * Authenticate with API key
   * @param apiKey API key
   * @returns true if authenticated successfully
   */
  authenticate(apiKey: string): Promise<boolean>;

  /**
   * Check if currently authenticated
   */
  isAuthenticated(): Promise<boolean>;

  /**
   * Get current user ID
   * @returns User ID or empty if not authenticated
   */
  getUserId(): Promise<string>;

  /**
   * Get current organization ID
   * @returns Organization ID or empty if not authenticated
   */
  getOrganizationId(): Promise<string>;

  // ============================================================================
  // Device Registration
  // Matches Swift: CppBridge+Device.swift
  // ============================================================================

  /**
   * Register device with backend
   * @param environmentJson Environment configuration JSON
   * @returns true if registered successfully
   */
  registerDevice(environmentJson: string): Promise<boolean>;

  /**
   * Check if device is registered
   */
  isDeviceRegistered(): Promise<boolean>;

  /**
   * Get the device ID
   * @returns Device ID or empty if not registered
   */
  getDeviceId(): Promise<string>;

  // ============================================================================
  // Model Registry
  // Matches Swift: CppBridge+ModelRegistry.swift
  // ============================================================================

  /**
   * Get list of available models
   * @returns JSON array of model info
   */
  getAvailableModels(): Promise<string>;

  /**
   * Get info for a specific model
   * @param modelId Model identifier
   * @returns JSON with model info
   */
  getModelInfo(modelId: string): Promise<string>;

  /**
   * Check if a model is downloaded
   * @param modelId Model identifier
   * @returns true if model exists locally
   */
  isModelDownloaded(modelId: string): Promise<boolean>;

  /**
   * Get local path for a model
   * @param modelId Model identifier
   * @returns Local file path or empty if not downloaded
   */
  getModelPath(modelId: string): Promise<string>;

  /**
   * Register a custom model with the registry
   * @param modelJson JSON with model definition
   * @returns true if registered successfully
   */
  registerModel(modelJson: string): Promise<boolean>;

  // ============================================================================
  // Download Service
  // Matches Swift: CppBridge+Download.swift
  // ============================================================================

  /**
   * Download a model
   * @param modelId Model identifier
   * @param url Download URL
   * @param destPath Destination path
   * @returns true if download started successfully
   */
  downloadModel(
    modelId: string,
    url: string,
    destPath: string
  ): Promise<boolean>;

  /**
   * Cancel an ongoing download
   * @param modelId Model identifier
   * @returns true if cancelled
   */
  cancelDownload(modelId: string): Promise<boolean>;

  /**
   * Get download progress
   * @param modelId Model identifier
   * @returns JSON with progress info (bytes, total, percentage)
   */
  getDownloadProgress(modelId: string): Promise<string>;

  // ============================================================================
  // Storage
  // Matches Swift: RunAnywhere+Storage.swift
  // ============================================================================

  /**
   * Get storage info (disk usage, available space)
   * @returns JSON with storage info
   */
  getStorageInfo(): Promise<string>;

  /**
   * Clear model cache
   * @returns true if cleared successfully
   */
  clearCache(): Promise<boolean>;

  /**
   * Delete a specific model
   * @param modelId Model identifier
   * @returns true if deleted successfully
   */
  deleteModel(modelId: string): Promise<boolean>;

  // ============================================================================
  // Events
  // Matches Swift: CppBridge+Events.swift
  // ============================================================================

  /**
   * Emit an event to the native event system
   * @param eventJson Event JSON with type, category, data
   */
  emitEvent(eventJson: string): Promise<void>;

  /**
   * Poll for pending events from native
   * @returns JSON array of events
   */
  pollEvents(): Promise<string>;

  // ============================================================================
  // HTTP Client
  // Matches Swift: CppBridge+HTTP.swift
  // ============================================================================

  /**
   * Configure HTTP client
   * @param baseUrl Base URL for API
   * @param apiKey API key for authentication
   * @returns true if configured successfully
   */
  configureHttp(baseUrl: string, apiKey: string): Promise<boolean>;

  /**
   * Make HTTP POST request
   * @param path API path
   * @param bodyJson Request body JSON
   * @returns Response JSON
   */
  httpPost(path: string, bodyJson: string): Promise<string>;

  /**
   * Make HTTP GET request
   * @param path API path
   * @returns Response JSON
   */
  httpGet(path: string): Promise<string>;

  // ============================================================================
  // Utility Functions
  // ============================================================================

  /**
   * Get the last error message
   */
  getLastError(): Promise<string>;

  /**
   * Extract an archive (tar.bz2, tar.gz, zip)
   * @param archivePath Path to the archive
   * @param destPath Destination directory
   */
  extractArchive(archivePath: string, destPath: string): Promise<boolean>;

  /**
   * Get device capabilities
   * @returns JSON string with device info
   */
  getDeviceCapabilities(): Promise<string>;

  /**
   * Get memory usage
   * @returns Current memory usage in bytes
   */
  getMemoryUsage(): Promise<number>;
}
