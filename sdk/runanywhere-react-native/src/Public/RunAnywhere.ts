/**
 * RunAnywhere React Native SDK - Main Entry Point
 *
 * The clean, event-based RunAnywhere SDK for React Native.
 * Single entry point with both event-driven and async/await patterns.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift
 */

import { EventBus } from './Events';
import {
  requireNativeModule,
  isNativeModuleAvailable,
  requireFileSystemModule,
} from '../native';
import {
  SDKEnvironment,
  ExecutionTarget,
  HardwareAcceleration,
  ModelCategory,
} from '../types';
import { ModelRegistry } from '../services/ModelRegistry';
import { ServiceContainer } from '../Foundation/DependencyInjection/ServiceContainer';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';
import { DeviceIdentityService } from '../Foundation/DeviceIdentity/DeviceIdentityService';
import { SDKConstants } from '../Foundation/Constants/SDKConstants';

const logger = new SDKLogger('RunAnywhere');
import type {
  InitializationPhase,
  InitializationState,
  SDKInitParams,
} from '../Foundation/Initialization';
import {
  createInitialState,
  markCoreInitialized,
  markServicesInitializing,
  markServicesInitialized,
  markInitializationFailed,
  resetState,
} from '../Foundation/Initialization';
import type {
  GenerationOptions,
  GenerationResult,
  SDKInitOptions,
  STTOptions,
  STTResult,
  TTSConfiguration,
  TTSResult,
  ModelInfo,
  LLMFramework,
} from '../types';
import { StructuredOutputHandler } from '../Capabilities/StructuredOutput/Services/StructuredOutputHandler';
import type { GeneratableType } from '../Capabilities/StructuredOutput/Services/StructuredOutputHandler';

// ============================================================================
// Internal State
// ============================================================================

/**
 * SDK initialization state following iOS two-phase pattern.
 *
 * Phase 1 (Core): Sync, fast (~1-5ms)
 *   - Validate config, setup logging, create backend
 *   - isSDKInitialized = true after this
 *
 * Phase 2 (Services): Async (~100-500ms)
 *   - Initialize ModelRegistry, register providers
 *   - areServicesReady = true after this
 */
let initState: InitializationState = createInitialState();

// Legacy state structure for backwards compatibility during migration
interface SDKState {
  initialized: boolean;
  environment: SDKEnvironment | null;
  backendType: string | null;
}

const state: SDKState = {
  initialized: false,
  environment: null,
  backendType: null,
};

// Track active downloads for cancellation
const activeDownloads = new Map<string, number>();

// ============================================================================
// Conversation Helper
// ============================================================================

/**
 * Simple conversation manager for multi-turn conversations
 * Reference: Conversation class in RunAnywhere.swift
 */
export class Conversation {
  private messages: string[] = [];

  /**
   * Send a message and get response
   */
  async send(message: string): Promise<string> {
    this.messages.push(`User: ${message}`);

    const contextPrompt = this.messages.join('\n') + '\nAssistant:';
    const result = await RunAnywhere.generate(contextPrompt);

    this.messages.push(`Assistant: ${result.text}`);
    return result.text;
  }

  /**
   * Get conversation history
   */
  get history(): string[] {
    return [...this.messages];
  }

  /**
   * Clear conversation
   */
  clear(): void {
    this.messages = [];
  }
}

// ============================================================================
// RunAnywhere SDK
// ============================================================================

/**
 * The RunAnywhere SDK for React Native
 *
 * Provides on-device AI capabilities with intelligent routing between
 * on-device and cloud execution for optimal cost and privacy.
 *
 * @example
 * ```typescript
 * // Initialize the SDK
 * await RunAnywhere.initialize({
 *   apiKey: 'your-api-key',
 *   baseURL: 'https://api.runanywhere.com',
 *   environment: SDKEnvironment.Production,
 * });
 *
 * // Simple chat
 * const result = await RunAnywhere.generate('Hello, how are you?');
 * console.log(result.text);
 *
 * // Subscribe to generation events
 * const unsubscribe = RunAnywhere.events.onGeneration((event) => {
 *   console.log('Generation event:', event);
 * });
 * ```
 */
export const RunAnywhere = {
  // ============================================================================
  // Event Access
  // ============================================================================

  /**
   * Access to all SDK events for subscription-based patterns
   */
  events: EventBus,

  // ============================================================================
  // SDK State (Two-Phase Initialization)
  // ============================================================================

  /**
   * Check if SDK is initialized (Phase 1 complete)
   *
   * After Phase 1, the SDK is usable for basic operations.
   * Services may still be initializing in the background.
   *
   * Matches iOS: isSDKInitialized
   */
  get isSDKInitialized(): boolean {
    return initState.isCoreInitialized;
  },

  /**
   * Check if all services are ready (Phase 2 complete)
   *
   * When true, all async services (ModelRegistry, providers, etc.)
   * have completed initialization.
   *
   * Matches iOS: areServicesReady
   */
  get areServicesReady(): boolean {
    return initState.hasCompletedServicesInit;
  },

  /**
   * Check if SDK is active and ready for use
   *
   * Matches iOS: isActive
   */
  get isActive(): boolean {
    return initState.isCoreInitialized && initState.initParams !== null;
  },

  /**
   * Get current initialization phase
   */
  get initializationPhase(): InitializationPhase {
    return initState.phase;
  },

  /**
   * Get current environment
   */
  get currentEnvironment(): SDKEnvironment | null {
    return initState.environment;
  },

  /**
   * Get the persistent device identifier
   *
   * Returns the cached device UUID if available, null otherwise.
   * For guaranteed access, use `getDeviceId()` which is async.
   *
   * Matches iOS: `static var deviceId: String`
   */
  get deviceId(): string | null {
    return DeviceIdentityService.getCachedDeviceUUID();
  },

  /**
   * Get the persistent device identifier (async version)
   *
   * Returns the device UUID, loading from secure storage if needed.
   * This UUID survives app reinstalls.
   *
   * @returns Promise resolving to the persistent device UUID
   */
  async getDeviceId(): Promise<string> {
    return DeviceIdentityService.getPersistentDeviceUUID();
  },

  /**
   * Whether the currently loaded LLM service supports true streaming generation
   *
   * Matches iOS: static var supportsLLMStreaming: Bool
   *
   * @returns `true` if streaming is supported, `false` otherwise
   * @note Returns `false` if no LLM model is loaded
   */
  get supportsLLMStreaming(): boolean {
    return ServiceContainer.shared.llmCapability.supportsStreaming;
  },

  /**
   * Current SDK version
   *
   * Matches iOS: static var version: String
   */
  get version(): string {
    return SDKConstants.version;
  },

  /**
   * Current environment (null if not initialized)
   *
   * Matches iOS: static var environment: SDKEnvironment?
   */
  get environment(): SDKEnvironment | null {
    return initState.environment;
  },

  // ============================================================================
  // Authentication Info (Production/Staging only)
  // ============================================================================

  /**
   * Get current user ID from authentication
   *
   * Matches iOS: static func getUserId() async -> String?
   *
   * @returns User ID if authenticated, null otherwise
   */
  async getUserId(): Promise<string | null> {
    if (!initState.isCoreInitialized) {
      return null;
    }
    try {
      const { AuthenticationService } =
        await import('../Data/Network/Services/AuthenticationService');
      const authService = ServiceContainer.shared.authenticationService;
      if (!authService || !(authService instanceof AuthenticationService)) {
        return null;
      }
      return (
        authService as InstanceType<typeof AuthenticationService>
      ).getUserId();
    } catch {
      return null;
    }
  },

  /**
   * Get current organization ID from authentication
   *
   * Matches iOS: static func getOrganizationId() async -> String?
   *
   * @returns Organization ID if authenticated, null otherwise
   */
  async getOrganizationId(): Promise<string | null> {
    if (!initState.isCoreInitialized) {
      return null;
    }
    try {
      const { AuthenticationService } =
        await import('../Data/Network/Services/AuthenticationService');
      const authService = ServiceContainer.shared.authenticationService;
      if (!authService || !(authService instanceof AuthenticationService)) {
        return null;
      }
      return (
        authService as InstanceType<typeof AuthenticationService>
      ).getOrganizationId();
    } catch {
      return null;
    }
  },

  /**
   * Check if device is registered with backend
   *
   * Matches iOS: static func isDeviceRegistered() async -> Bool
   */
  async isDeviceRegistered(): Promise<boolean> {
    const { DeviceRegistrationService } =
      await import('../Infrastructure/Device');
    return DeviceRegistrationService.shared.isRegistered();
  },

  // ============================================================================
  // SDK Initialization (Two-Phase Pattern)
  // ============================================================================

  /**
   * Initialize the RunAnywhere SDK
   *
   * Uses a two-phase initialization pattern matching iOS SDK:
   *
   * **Phase 1 (Core)**: Synchronous, fast (~1-5ms)
   *   - Validate configuration
   *   - Create native backend
   *   - Pass configuration to native layer
   *   - SDK becomes usable immediately
   *
   * **Phase 2 (Services)**: Asynchronous, in background (~100-500ms)
   *   - Register framework providers
   *   - Initialize ModelRegistry
   *   - Non-blocking, non-critical
   *
   * After this method returns, `isSDKInitialized` is true.
   * Check `areServicesReady` to know when Phase 2 completes.
   *
   * @param options - SDK initialization options
   * @throws Error if Phase 1 initialization fails
   *
   * @example
   * ```typescript
   * // Initialize (returns after Phase 1)
   * await RunAnywhere.initialize({
   *   apiKey: 'your-api-key',
   *   environment: SDKEnvironment.Production,
   * });
   *
   * // SDK is usable immediately
   * console.log(RunAnywhere.isSDKInitialized); // true
   *
   * // Wait for services if needed
   * await RunAnywhere.completeServicesInitialization();
   * console.log(RunAnywhere.areServicesReady); // true
   * ```
   */
  async initialize(options: SDKInitOptions): Promise<void> {
    const environment = options.environment ?? SDKEnvironment.Production;
    const initParams: SDKInitParams = {
      apiKey: options.apiKey,
      baseURL: options.baseURL,
      environment,
    };

    // Publish initialization started event
    EventBus.publish('Initialization', { type: 'started' });

    // ========================================================================
    // PHASE 1: Core Initialization (Sync, Fast)
    // ========================================================================
    logger.info(' Phase 1: Core initialization starting...');
    const phase1Start = Date.now();

    let backendType: string | null = null;

    // Check if native module is available
    if (!isNativeModuleAvailable()) {
      if (__DEV__ || environment === SDKEnvironment.Development) {
        logger.warning(
          'Native module not available. Running in limited development mode.'
        );
        initState = markCoreInitialized(initState, initParams, null);
        state.initialized = true;
        state.environment = environment;
        EventBus.publish('Initialization', { type: 'completed' });

        // Start Phase 2 in background (non-blocking)
        this._startPhase2InBackground();
        return;
      }
      initState = markInitializationFailed(
        initState,
        new Error('Native module not available')
      );
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();

    // Create the backend
    const backendName = 'llamacpp';
    try {
      const backendCreated = native.createBackend(backendName);
      if (!backendCreated) {
        if (__DEV__ || environment === SDKEnvironment.Development) {
          logger.warning('Failed to create backend, running in limited mode');
          initState = markCoreInitialized(initState, initParams, null);
          state.initialized = true;
          state.environment = environment;
          state.backendType = null;
          EventBus.publish('Initialization', { type: 'completed' });
          this._startPhase2InBackground();
          return;
        }
        initState = markInitializationFailed(
          initState,
          new Error('Failed to create backend')
        );
        throw new Error('Failed to create backend');
      }
      backendType = backendName;
      state.backendType = backendName;
    } catch (error) {
      if (__DEV__ || environment === SDKEnvironment.Development) {
        const errorMessage =
          error instanceof Error ? error.message : String(error);
        logger.warning(`Backend creation error: ${errorMessage}`);
        initState = markCoreInitialized(initState, initParams, null);
        state.initialized = true;
        state.environment = environment;
        EventBus.publish('Initialization', { type: 'completed' });
        this._startPhase2InBackground();
        return;
      }
      initState = markInitializationFailed(initState, error as Error);
      throw error;
    }

    // Initialize with configuration
    try {
      const configJson = JSON.stringify({
        apiKey: options.apiKey,
        baseURL: options.baseURL,
        environment: environment,
      });

      const result = native.initialize(configJson);
      if (!result) {
        if (__DEV__ || environment === SDKEnvironment.Development) {
          logger.warning(
            'Native initialize returned false, continuing in dev mode'
          );
          initState = markCoreInitialized(initState, initParams, backendType);
          state.initialized = true;
          state.environment = environment;
          EventBus.publish('Initialization', { type: 'completed' });
          this._startPhase2InBackground();
          return;
        }
        initState = markInitializationFailed(
          initState,
          new Error('Failed to initialize SDK')
        );
        throw new Error('Failed to initialize SDK');
      }
    } catch (error) {
      if (__DEV__ || environment === SDKEnvironment.Development) {
        const errorMessage =
          error instanceof Error ? error.message : String(error);
        logger.warning(`Initialize error: ${errorMessage}`);
        initState = markCoreInitialized(initState, initParams, backendType);
        state.initialized = true;
        state.environment = environment;
        EventBus.publish('Initialization', { type: 'completed' });
        this._startPhase2InBackground();
        return;
      }
      initState = markInitializationFailed(initState, error as Error);
      throw error;
    }

    // Phase 1 complete
    const phase1Duration = Date.now() - phase1Start;
    logger.info(`Phase 1 complete (${phase1Duration}ms)`);

    initState = markCoreInitialized(initState, initParams, backendType);
    state.initialized = true;
    state.environment = environment;
    EventBus.publish('Initialization', { type: 'completed' });

    // ========================================================================
    // PHASE 2: Services Initialization (Async, Background)
    // ========================================================================
    this._startPhase2InBackground();
  },

  /**
   * Start Phase 2 initialization in background
   * @internal
   */
  _startPhase2InBackground(): void {
    logger.info(' Starting Phase 2 (services) in background...');

    // Run Phase 2 asynchronously without blocking
    // Uses setTimeout to ensure it runs in the next event loop tick
    setTimeout(async () => {
      try {
        await this.completeServicesInitialization();
        logger.info('Phase 2 complete (background)');
      } catch (error) {
        // Phase 2 failure is non-critical
        const errorMessage =
          error instanceof Error ? error.message : String(error);
        logger.warning(`Phase 2 failed (non-critical): ${errorMessage}`);
      }
    }, 0);
  },

  /**
   * Complete services initialization (Phase 2)
   *
   * This method is idempotent - calling it multiple times is safe.
   * If services are already initialized, this returns immediately.
   *
   * Matches iOS: completeServicesInitialization()
   *
   * @example
   * ```typescript
   * // Wait for all services to be ready
   * await RunAnywhere.completeServicesInitialization();
   * console.log(RunAnywhere.areServicesReady); // true
   * ```
   */
  async completeServicesInitialization(): Promise<void> {
    // Fast path: already completed
    if (initState.hasCompletedServicesInit) {
      return;
    }

    // Guard: must have completed Phase 1
    if (!initState.isCoreInitialized) {
      throw new Error('SDK not initialized. Call initialize() first.');
    }

    // Mark Phase 2 in progress
    initState = markServicesInitializing(initState);
    const phase2Start = Date.now();

    // Step 1: Setup API client (matches iOS setupAPIClient pattern)
    // The API client is used for analytics, model sync, and other network operations
    if (initState.initParams) {
      const params = initState.initParams;
      const environment = initState.environment ?? SDKEnvironment.Production;

      logger.info(' Initializing API client...');
      try {
        // Initialize the API client in ServiceContainer
        // This also wires the client to AnalyticsQueueManager
        ServiceContainer.shared.initializeAPIClient(
          {
            baseURL: params.baseURL ?? '',
            apiKey: params.apiKey ?? '',
            timeout: 30000,
          },
          environment,
          undefined // Auth provider will be set after authentication
        );
        logger.info(' API client initialized');
      } catch (error) {
        logger.warning('Failed to initialize API client (non-critical):', {
          error,
        });
      }
    }

    // Step 2: Register framework providers (same pattern as Swift SDK)
    logger.info('Registering framework providers...');
    try {
      // Register LlamaCPP provider for GGUF models
      const { LlamaCppProvider } = require('../Providers/LlamaCppProvider');
      LlamaCppProvider.register();
      logger.info('LlamaCPP provider registered');
    } catch (error) {
      logger.warning('Failed to register LlamaCPP provider:', { error });
    }

    try {
      // Register ONNX providers for STT/TTS models
      const { registerONNXProviders } = require('../Providers/ONNXProvider');
      registerONNXProviders();
      logger.info('ONNX providers registered');
    } catch (error) {
      logger.warning('Failed to register ONNX providers:', { error });
    }

    // Step 3: Initialize the Model Registry
    try {
      await ModelRegistry.initialize();
      logger.info('Model Registry initialized successfully');
    } catch (error) {
      logger.warning('Model Registry initialization failed (non-critical):', {
        error,
      });
    }

    // Step 4: Register device with backend
    // Matches iOS: await serviceContainer.deviceRegistrationService.registerIfNeeded(...)
    try {
      const apiClient = ServiceContainer.shared.apiClient;
      const environment = initState.environment ?? SDKEnvironment.Production;

      if (apiClient) {
        const { DeviceRegistrationService } =
          await import('../Infrastructure/Device');
        await DeviceRegistrationService.shared.registerIfNeeded(
          apiClient,
          environment
        );
        logger.info('Device registration check complete');
      } else {
        logger.debug('No API client available, skipping device registration');
      }
    } catch (error) {
      // Device registration failure is non-critical
      logger.warning('Device registration failed (non-critical):', { error });
    }

    // Mark Phase 2 complete
    const phase2Duration = Date.now() - phase2Start;
    logger.info(`Phase 2 complete (${phase2Duration}ms)`);
    initState = markServicesInitialized(initState);
  },

  /**
   * Ensure services are ready before proceeding
   *
   * This is a convenience method that guarantees Phase 2 is complete.
   * O(1) performance on subsequent calls.
   *
   * Matches iOS: ensureServicesReady()
   *
   * @internal
   */
  async ensureServicesReady(): Promise<void> {
    if (initState.hasCompletedServicesInit) {
      return; // O(1) fast path
    }
    await this.completeServicesInitialization();
  },

  /**
   * Destroy SDK and release resources
   *
   * Resets all initialization state. After calling this,
   * you must call initialize() again to use the SDK.
   *
   * Matches iOS: reset()
   */
  async destroy(): Promise<void> {
    if (isNativeModuleAvailable()) {
      const native = requireNativeModule();
      await native.destroy();
    }

    // Reset ServiceContainer (clears API client, auth, analytics wiring)
    ServiceContainer.shared.reset();

    // Reset new initialization state
    initState = resetState();

    // Reset legacy state
    state.initialized = false;
    state.environment = null;
    state.backendType = null;
  },

  /**
   * Reset SDK state (alias for destroy for iOS parity)
   *
   * Matches iOS: reset()
   */
  async reset(): Promise<void> {
    await this.destroy();
  },

  /**
   * Check if SDK is initialized (async version for native query)
   */
  async isInitialized(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return state.initialized;
    }
    const native = requireNativeModule();
    return native.isInitialized();
  },

  /**
   * Get SDK version
   */
  async getVersion(): Promise<string> {
    // Version is managed at the JS layer
    return SDKConstants.version;
  },

  // ============================================================================
  // Logging
  // ============================================================================

  /**
   * Set SDK log level
   * Matches iOS: static func setLogLevel(_ level: LogLevel)
   *
   * @param level - The minimum log level to output
   */
  setLogLevel(
    level: import('../Foundation/Logging/Models/LogLevel').LogLevel
  ): void {
    const { LoggingManager } = require('../Foundation/Logging');
    LoggingManager.shared.setLogLevel(level);
  },

  /**
   * Subscribe to all SDK log events
   * Matches iOS pattern of exposing log events publicly.
   *
   * This allows consumers to receive log events for their own logging infrastructure
   * (e.g., Sentry, LogRocket, custom analytics).
   *
   * @param callback - Function called for each log entry
   * @returns Unsubscribe function
   *
   * @example
   * ```typescript
   * const unsubscribe = RunAnywhere.onLog((entry) => {
   *   console.log(`[${entry.level}] ${entry.category}: ${entry.message}`);
   *   // Or send to your logging service
   *   Sentry.captureMessage(entry.message, entry.level);
   * });
   *
   * // Later: unsubscribe();
   * ```
   */
  onLog(
    callback: import('../Foundation/Logging').LogEventCallback
  ): () => void {
    const { LoggingManager } = require('../Foundation/Logging');
    return LoggingManager.shared.onLog(callback);
  },

  /**
   * Add a custom log destination
   * Matches iOS: static func addLogDestination(_ destination: LogDestination)
   *
   * Use this to add custom logging backends (file, remote service, etc.)
   *
   * @param destination - Log destination to add
   */
  addLogDestination(
    destination: import('../Foundation/Logging').LogDestination
  ): void {
    const { LoggingManager } = require('../Foundation/Logging');
    LoggingManager.shared.addDestination(destination);
  },

  /**
   * Remove a log destination by identifier
   *
   * @param identifier - Destination identifier to remove
   */
  removeLogDestination(identifier: string): void {
    const { LoggingManager } = require('../Foundation/Logging');
    LoggingManager.shared.removeDestination(identifier);
  },

  // ============================================================================
  // Text Generation (LLM)
  // ============================================================================

  /**
   * Load an LLM model by ID or path
   *
   * Matches iOS: `RunAnywhere.loadModel(_:)`
   *
   * @param modelPathOrId - Path to the model file or model ID
   * @param config - Optional configuration
   * @returns true if model loaded successfully
   *
   * @example
   * ```typescript
   * await RunAnywhere.loadModel('/path/to/model.gguf');
   * // or with model ID
   * await RunAnywhere.loadModel('llama-3.2-1b-q4');
   * ```
   */
  async loadModel(
    modelPathOrId: string,
    config?: Record<string, unknown>
  ): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      logger.warning('Native module not available for loadModel');
      return false;
    }
    const native = requireNativeModule();
    return native.loadTextModel(
      modelPathOrId,
      config ? JSON.stringify(config) : undefined
    );
  },

  /**
   * Load a text generation model
   *
   * @deprecated Use `loadModel()` instead for iOS API parity
   * @param modelPath - Path to the model file
   * @param config - Optional configuration
   */
  async loadTextModel(
    modelPath: string,
    config?: Record<string, unknown>
  ): Promise<boolean> {
    return this.loadModel(modelPath, config);
  },

  /**
   * Check if an LLM model is loaded
   *
   * Matches iOS: `RunAnywhere.isModelLoaded`
   */
  async isModelLoaded(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.isTextModelLoaded();
  },

  /**
   * Check if a text model is loaded
   *
   * @deprecated Use `isModelLoaded()` instead for iOS API parity
   */
  async isTextModelLoaded(): Promise<boolean> {
    return this.isModelLoaded();
  },

  /**
   * Unload the currently loaded LLM model
   *
   * Matches iOS: `RunAnywhere.unloadModel()`
   */
  async unloadModel(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.unloadTextModel();
  },

  /**
   * Unload the current text model
   *
   * @deprecated Use `unloadModel()` instead for iOS API parity
   */
  async unloadTextModel(): Promise<boolean> {
    return this.unloadModel();
  },

  /**
   * Simple chat - returns just the text response
   * Matches Swift SDK: RunAnywhere.chat(_:)
   *
   * @param prompt - The chat prompt
   * @returns The generated text response
   *
   * @example
   * ```typescript
   * const response = await RunAnywhere.chat('Hello, how are you?');
   * console.log(response);
   * ```
   */
  async chat(prompt: string): Promise<string> {
    const result = await this.generate(prompt);
    return result.text;
  },

  /**
   * Text generation with options and full metrics
   * Matches Swift SDK: RunAnywhere.generate(_:options:)
   *
   * @param prompt - The text prompt
   * @param options - Generation options
   * @returns GenerationResult with full metrics
   *
   * @example
   * ```typescript
   * const result = await RunAnywhere.generate('Explain quantum computing', {
   *   maxTokens: 200,
   *   temperature: 0.7,
   * });
   * console.log('Text:', result.text);
   * ```
   */
  async generate(
    prompt: string,
    options?: GenerationOptions
  ): Promise<GenerationResult> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }
    const native = requireNativeModule();

    // Build options JSON for native generateText
    const optionsJson = JSON.stringify({
      max_tokens: options?.maxTokens ?? 256,
      temperature: options?.temperature ?? 0.7,
      system_prompt: options?.systemPrompt ?? null,
    });

    const resultJson = await native.generate(prompt, optionsJson);

    try {
      const result = JSON.parse(resultJson);
      return {
        text: result.text ?? '',
        thinkingContent: result.thinkingContent,
        tokensUsed: result.tokensUsed ?? 0,
        modelUsed: result.modelUsed ?? 'unknown',
        latencyMs: result.latencyMs ?? 0,
        executionTarget: result.executionTarget ?? 0,
        savedAmount: result.savedAmount ?? 0,
        framework: result.framework,
        hardwareUsed: result.hardwareUsed ?? 0,
        memoryUsed: result.memoryUsed ?? 0,
        performanceMetrics: {
          timeToFirstTokenMs: result.performanceMetrics?.timeToFirstTokenMs,
          tokensPerSecond: result.performanceMetrics?.tokensPerSecond,
          inferenceTimeMs:
            result.performanceMetrics?.inferenceTimeMs ?? result.latencyMs ?? 0,
        },
        thinkingTokens: result.thinkingTokens,
        responseTokens: result.responseTokens ?? result.tokensUsed ?? 0,
      };
    } catch {
      // If parsing fails, treat as error message
      if (resultJson.includes('error')) {
        throw new Error(resultJson);
      }
      return {
        text: resultJson,
        tokensUsed: 0,
        modelUsed: 'unknown',
        latencyMs: 0,
        executionTarget: ExecutionTarget.OnDevice,
        savedAmount: 0,
        hardwareUsed: HardwareAcceleration.CPU,
        memoryUsed: 0,
        performanceMetrics: {
          inferenceTimeMs: 0,
        },
        responseTokens: 0,
      };
    }
  },

  /**
   * Streaming text generation
   *
   * Starts a streaming generation session. Tokens are delivered via events.
   *
   * @param prompt - The text prompt
   * @param options - Generation options
   * @param onToken - Callback for each token
   *
   * @example
   * ```typescript
   * RunAnywhere.generateStream('Tell me a story', {}, (token) => {
   *   process.stdout.write(token);
   * });
   * ```
   */
  generateStream(
    prompt: string,
    options?: GenerationOptions,
    onToken?: (token: string) => void
  ): void {
    if (!isNativeModuleAvailable()) {
      EventBus.publish('Generation', {
        type: 'failed',
        error: 'Native module not available',
      });
      return;
    }
    const native = requireNativeModule();

    // Build options JSON for native generateStream
    const optionsJson = JSON.stringify({
      max_tokens: options?.maxTokens ?? 256,
      temperature: options?.temperature ?? 0.7,
      system_prompt: options?.systemPrompt ?? null,
    });

    // Subscribe to generation events if callback provided
    if (onToken) {
      const unsubscribe = EventBus.onGeneration((event) => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const evt = event as any;
        if (evt.type === 'tokenGenerated' && evt.token) {
          onToken(evt.token);
        } else if (evt.type === 'completed' || evt.type === 'failed') {
          unsubscribe();
        }
      });
    }

    // Native generateStream takes (prompt, optionsJson, callback)
    native.generateStream(
      prompt,
      optionsJson,
      (token: string, isComplete: boolean) => {
        if (onToken && !isComplete) {
          onToken(token);
        }
        if (isComplete) {
          EventBus.publish('Generation', { type: 'completed' });
        }
      }
    );
  },

  /**
   * Cancel ongoing text generation
   */
  cancelGeneration(): void {
    if (!isNativeModuleAvailable()) {
      return;
    }
    const native = requireNativeModule();
    native.cancelGeneration();
  },

  // ============================================================================
  // Structured Output Generation
  // ============================================================================

  /**
   * Generate structured output that conforms to a type schema
   *
   * Matches iOS: `RunAnywhere.generateStructured(_:prompt:options:)`
   *
   * @param schema - Object with a `jsonSchema` property defining the expected output structure
   * @param prompt - The prompt to generate from
   * @param options - Optional generation options
   * @returns The generated object parsed from JSON
   * @throws Error if generation fails or output is not valid JSON
   *
   * @example
   * ```typescript
   * // Define your schema
   * const QuizQuestionSchema = {
   *   jsonSchema: JSON.stringify({
   *     type: 'object',
   *     properties: {
   *       question: { type: 'string' },
   *       options: { type: 'array', items: { type: 'string' } },
   *       correctAnswer: { type: 'integer' }
   *     },
   *     required: ['question', 'options', 'correctAnswer']
   *   })
   * };
   *
   * // Generate structured output
   * const quiz = await RunAnywhere.generateStructured(
   *   QuizQuestionSchema,
   *   'Create a quiz question about Swift programming'
   * );
   * console.log(quiz.question);
   * ```
   */
  async generateStructured<T>(
    schema: GeneratableType,
    prompt: string,
    options?: GenerationOptions
  ): Promise<T> {
    const handler = new StructuredOutputHandler();

    // Get the system prompt from the handler
    const systemPrompt = handler.getSystemPrompt(schema);

    // Build the user prompt
    const userPrompt = handler.buildUserPrompt(schema, prompt);

    // Create effective options with structured output system prompt
    const effectiveOptions: GenerationOptions = {
      ...options,
      maxTokens: options?.maxTokens ?? 1500,
      temperature: options?.temperature ?? 0.7,
      systemPrompt: systemPrompt,
    };

    // Generate using the standard generate method
    const result = await this.generate(userPrompt, effectiveOptions);

    // Parse structured output using the handler (matches iOS)
    return handler.parseStructuredOutput<T>(result.text, schema);
  },

  /**
   * Extract JSON from potentially mixed text
   * @internal
   */
  _extractJSON(text: string): string {
    const trimmed = text.trim();

    // Try to find JSON object boundaries
    const startIndex = trimmed.indexOf('{');
    if (startIndex !== -1) {
      const endIndex = this._findMatchingBrace(trimmed, startIndex);
      if (endIndex !== null) {
        return trimmed.substring(startIndex, endIndex + 1);
      }
    }

    // Try to find JSON array boundaries
    const arrayStartIndex = trimmed.indexOf('[');
    if (arrayStartIndex !== -1) {
      const arrayEndIndex = this._findMatchingBracket(trimmed, arrayStartIndex);
      if (arrayEndIndex !== null) {
        return trimmed.substring(arrayStartIndex, arrayEndIndex + 1);
      }
    }

    // If no clear JSON boundaries, check if the entire text might be JSON
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return trimmed;
    }

    throw new Error('No valid JSON found in the response');
  },

  /**
   * Find matching closing brace
   * @internal
   */
  _findMatchingBrace(text: string, startIndex: number): number | null {
    let depth = 0;
    let inString = false;
    let escaped = false;

    for (let i = startIndex; i < text.length; i++) {
      const char = text[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char === '\\') {
        escaped = true;
        continue;
      }

      if (char === '"') {
        inString = !inString;
        continue;
      }

      if (inString) continue;

      if (char === '{') {
        depth++;
      } else if (char === '}') {
        depth--;
        if (depth === 0) {
          return i;
        }
      }
    }

    return null;
  },

  /**
   * Find matching closing bracket
   * @internal
   */
  _findMatchingBracket(text: string, startIndex: number): number | null {
    let depth = 0;
    let inString = false;
    let escaped = false;

    for (let i = startIndex; i < text.length; i++) {
      const char = text[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char === '\\') {
        escaped = true;
        continue;
      }

      if (char === '"') {
        inString = !inString;
        continue;
      }

      if (inString) continue;

      if (char === '[') {
        depth++;
      } else if (char === ']') {
        depth--;
        if (depth === 0) {
          return i;
        }
      }
    }

    return null;
  },

  // ============================================================================
  // Speech-to-Text (STT)
  // ============================================================================

  /**
   * Load an STT model
   *
   * @param modelPath - Path to the model file
   * @param modelType - Model type (e.g., 'whisper', 'sherpa')
   * @param config - Optional configuration
   */
  async loadSTTModel(
    modelPath: string,
    modelType: string = 'whisper',
    config?: Record<string, unknown>
  ): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      logger.warning('Native module not available for loadSTTModel');
      return false;
    }
    const native = requireNativeModule();
    return native.loadSTTModel(
      modelPath,
      modelType,
      config ? JSON.stringify(config) : undefined
    );
  },

  /**
   * Check if an STT model is loaded
   */
  async isSTTModelLoaded(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.isSTTModelLoaded();
  },

  /**
   * Unload the current STT model
   */
  async unloadSTTModel(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.unloadSTTModel();
  },

  /**
   * Transcribe audio data
   *
   * @param audioData - Audio data (base64 encoded or ArrayBuffer)
   * @param options - STT options
   * @returns Transcription result
   *
   * @example
   * ```typescript
   * const result = await RunAnywhere.transcribe(audioBase64, { language: 'en' });
   * console.log('Transcript:', result.text);
   * ```
   */
  async transcribe(
    audioData: string | ArrayBuffer,
    options?: STTOptions
  ): Promise<STTResult> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }
    const native = requireNativeModule();

    // Convert ArrayBuffer to base64 if needed
    let audioBase64: string;
    if (typeof audioData === 'string') {
      audioBase64 = audioData;
    } else {
      const bytes = new Uint8Array(audioData);
      let binary = '';
      for (let i = 0; i < bytes.byteLength; i++) {
        const byte = bytes[i];
        if (byte !== undefined) {
          binary += String.fromCharCode(byte);
        }
      }
      audioBase64 = btoa(binary);
    }

    const sampleRate = options?.sampleRate ?? 16000;
    const language = options?.language;

    const resultJson = await native.transcribe(
      audioBase64,
      sampleRate,
      language
    );

    try {
      const result = JSON.parse(resultJson);
      return {
        text: result.text ?? '',
        segments: result.segments ?? [],
        language: result.language,
        confidence: result.confidence ?? 1.0,
        duration: result.duration ?? 0,
        alternatives: result.alternatives ?? [],
      };
    } catch {
      if (resultJson.includes('error')) {
        throw new Error(resultJson);
      }
      return {
        text: resultJson,
        segments: [],
        confidence: 1.0,
        duration: 0,
        alternatives: [],
      };
    }
  },

  /**
   * Transcribe audio from a file path.
   * Automatically handles format conversion to 16kHz mono PCM.
   * Supports various audio formats (M4A, AAC, WAV, CAF, etc.)
   *
   * @param filePath - Path to the audio file
   * @param options - STT options (language, etc.)
   * @returns Transcription result
   *
   * @example
   * ```typescript
   * const result = await RunAnywhere.transcribeFile('/path/to/audio.m4a', { language: 'en' });
   * console.log('Transcript:', result.text);
   * ```
   */
  async transcribeFile(
    filePath: string,
    options?: STTOptions
  ): Promise<STTResult> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }
    const native = requireNativeModule();

    const language = options?.language ?? 'en'; // Default to English
    const resultJson = await native.transcribeFile(filePath, language);

    try {
      const result = JSON.parse(resultJson);
      if (result.error) {
        throw new Error(result.error);
      }
      return {
        text: result.text ?? '',
        segments: result.segments ?? [],
        language: result.language,
        confidence: result.confidence ?? 1.0,
        duration: result.duration ?? 0,
        alternatives: result.alternatives ?? [],
      };
    } catch {
      if (resultJson.includes('error')) {
        const errorMatch = resultJson.match(/"error":\s*"([^"]+)"/);
        throw new Error(errorMatch ? errorMatch[1] : resultJson);
      }
      return {
        text: resultJson,
        segments: [],
        confidence: 1.0,
        duration: 0,
        alternatives: [],
      };
    }
  },

  // ============================================================================
  // Streaming STT (Real-time transcription with AVAudioEngine)
  // ============================================================================

  /**
   * Start streaming speech-to-text transcription
   *
   * Uses AVAudioEngine for real-time audio capture at 16kHz mono.
   * Transcription results are delivered via events:
   * - onSTTPartial: Partial results as audio is processed
   * - onSTTFinal: Final result when streaming stops
   * - onSTTError: Error during transcription
   *
   * @param language - Language code (e.g., 'en')
   * @param onPartial - Callback for partial transcription results
   * @param onFinal - Callback for final transcription result
   * @param onError - Callback for errors
   * @returns true if streaming started successfully
   *
   * @example
   * ```typescript
   * await RunAnywhere.startStreamingSTT('en',
   *   (text) => console.log('Partial:', text),
   *   (text) => console.log('Final:', text),
   *   (error) => console.error('Error:', error)
   * );
   * // ... user speaks ...
   * await RunAnywhere.stopStreamingSTT();
   * ```
   */
  async startStreamingSTT(
    language: string = 'en',
    onPartial?: (text: string, confidence: number) => void,
    onFinal?: (text: string, confidence: number) => void,
    onError?: (error: string) => void
  ): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      logger.warning('Native module not available for startStreamingSTT');
      return false;
    }
    const native = requireNativeModule();

    // Subscribe to Voice/STT events
    if (onPartial || onFinal || onError) {
      EventBus.onVoice((event) => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const evt = event as any;
        if (evt.type === 'sttPartialResult' && onPartial) {
          onPartial(evt.text || '', evt.confidence || 0);
        } else if (evt.type === 'sttCompleted' && onFinal) {
          onFinal(evt.text || '', evt.confidence || 0);
        } else if (evt.type === 'sttFailed' && onError) {
          onError(evt.error || 'Unknown error');
        }
      });
    }

    return native.startStreamingSTT(language);
  },

  /**
   * Stop streaming speech-to-text transcription
   *
   * Stops audio capture and processing. Any remaining audio will be
   * transcribed and delivered via the onSTTFinal event.
   *
   * @returns true if streaming was stopped successfully
   */
  async stopStreamingSTT(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.stopStreamingSTT();
  },

  /**
   * Check if streaming STT is currently active
   *
   * @returns true if streaming is active
   */
  async isStreamingSTT(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.isStreamingSTT();
  },

  // ============================================================================
  // Text-to-Speech (TTS)
  // ============================================================================

  /**
   * Load a TTS model
   *
   * @param modelPath - Path to the model file
   * @param modelType - Model type (e.g., 'piper', 'vits')
   * @param config - Optional configuration
   */
  async loadTTSModel(
    modelPath: string,
    modelType: string = 'piper',
    config?: Record<string, unknown>
  ): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      logger.warning('Native module not available for loadTTSModel');
      return false;
    }
    const native = requireNativeModule();
    return native.loadTTSModel(
      modelPath,
      modelType,
      config ? JSON.stringify(config) : undefined
    );
  },

  /**
   * Check if a TTS model is loaded
   */
  async isTTSModelLoaded(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.isTTSModelLoaded();
  },

  /**
   * Unload the current TTS model
   */
  async unloadTTSModel(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.unloadTTSModel();
  },

  /**
   * Synthesize text to speech
   *
   * @param text - Text to synthesize
   * @param configuration - TTS configuration
   * @returns TTS result with audio data
   *
   * @example
   * ```typescript
   * const result = await RunAnywhere.synthesize('Hello, world!', {
   *   voice: 'en-US-default',
   *   rate: 1.0,
   * });
   * // result.audio is base64 encoded audio
   * ```
   */
  async synthesize(
    text: string,
    configuration?: TTSConfiguration
  ): Promise<TTSResult> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }
    const native = requireNativeModule();

    const voiceId = configuration?.voice ?? ''; // Empty string, not null - native expects string
    const speedRate = configuration?.rate ?? 1.0;
    const pitchShift = configuration?.pitch ?? 1.0;

    const resultJson = await native.synthesize(
      text,
      voiceId,
      speedRate,
      pitchShift
    );

    try {
      const result = JSON.parse(resultJson);
      return {
        audio: result.audio ?? '',
        sampleRate: result.sampleRate ?? 22050,
        numSamples: result.numSamples ?? 0,
        duration: result.numSamples ? result.numSamples / result.sampleRate : 0,
      };
    } catch {
      if (resultJson.includes('error')) {
        throw new Error(resultJson);
      }
      return {
        audio: resultJson,
        sampleRate: 22050,
        numSamples: 0,
        duration: 0,
      };
    }
  },

  /**
   * Get available TTS voices
   */
  async getTTSVoices(): Promise<string[]> {
    if (!isNativeModuleAvailable()) {
      return [];
    }
    const native = requireNativeModule();
    const voicesJson = await native.getTTSVoices();
    try {
      return JSON.parse(voicesJson);
    } catch {
      return voicesJson ? [voicesJson] : [];
    }
  },

  /**
   * Cancel ongoing TTS synthesis
   */
  cancelTTS(): void {
    if (!isNativeModuleAvailable()) {
      return;
    }
    const native = requireNativeModule();
    native.cancelTTS();
  },

  // ============================================================================
  // Voice Activity Detection (VAD)
  // ============================================================================

  /**
   * Load a VAD model
   */
  async loadVADModel(
    modelPath: string,
    config?: Record<string, unknown>
  ): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.loadVADModel(
      modelPath,
      config ? JSON.stringify(config) : undefined
    );
  },

  /**
   * Check if a VAD model is loaded
   */
  async isVADModelLoaded(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.isVADModelLoaded();
  },

  /**
   * Process audio for voice activity detection
   */
  async processVAD(
    audioData: string | ArrayBuffer,
    sampleRate: number = 16000
  ): Promise<{ isSpeech: boolean; probability: number }> {
    if (!isNativeModuleAvailable()) {
      return { isSpeech: false, probability: 0 };
    }
    const native = requireNativeModule();

    let audioBase64: string;
    if (typeof audioData === 'string') {
      audioBase64 = audioData;
    } else {
      const bytes = new Uint8Array(audioData);
      let binary = '';
      for (let i = 0; i < bytes.byteLength; i++) {
        const byte = bytes[i];
        if (byte !== undefined) {
          binary += String.fromCharCode(byte);
        }
      }
      audioBase64 = btoa(binary);
    }

    const resultJson = await native.processVAD(audioBase64, sampleRate);
    try {
      return JSON.parse(resultJson);
    } catch {
      return { isSpeech: false, probability: 0 };
    }
  },

  // ============================================================================
  // Voice Session (High-Level Voice Assistant API)
  // ============================================================================

  /**
   * Start a voice session with event-based handling
   *
   * This is the simplest way to integrate voice assistant.
   * The session handles audio capture, VAD, and processing internally.
   *
   * **Note:** In React Native, actual audio capture must be handled by the app
   * using external packages like react-native-live-audio-stream. Feed audio
   * to the session using `session.feedAudio()`.
   *
   * Matches iOS: static func startVoiceSession(config:) async throws -> VoiceSessionHandle
   *
   * @param config - Optional session configuration
   * @returns Session handle for control and event subscription
   *
   * @example
   * ```typescript
   * const session = await RunAnywhere.startVoiceSession();
   *
   * // Subscribe to events
   * const unsubscribe = session.onEvent((event) => {
   *   switch (event.type) {
   *     case 'listening':
   *       updateAudioMeter(event.audioLevel);
   *       break;
   *     case 'turnCompleted':
   *       showResult(event.transcript, event.response);
   *       break;
   *   }
   * });
   *
   * // Feed audio from external capture (e.g., react-native-live-audio-stream)
   * audioCapture.on('data', (pcmData: ArrayBuffer) => {
   *   session.feedAudio(pcmData, getAudioLevel());
   * });
   *
   * // Stop when done
   * await session.stop();
   * unsubscribe();
   * ```
   */
  async startVoiceSession(
    config?: Partial<import('../Features/VoiceSession').VoiceSessionConfig>
  ): Promise<import('../Features/VoiceSession').VoiceSessionHandle> {
    const { VoiceSessionHandle } = await import('../Features/VoiceSession');
    const session = new VoiceSessionHandle(config);
    await session.start();
    return session;
  },

  /**
   * Start a voice session with callback-based event handling
   *
   * Alternative API using callbacks instead of event subscription.
   *
   * Matches iOS: static func startVoiceSession(config:onEvent:) async throws -> VoiceSessionHandle
   *
   * @param config - Session configuration
   * @param onEvent - Callback for each event
   * @returns Session handle for control
   *
   * @example
   * ```typescript
   * const session = await RunAnywhere.startVoiceSessionWithCallback(
   *   { continuousMode: true },
   *   (event) => {
   *     if (event.type === 'turnCompleted') {
   *       console.log('User:', event.transcript);
   *       console.log('Assistant:', event.response);
   *     }
   *   }
   * );
   * ```
   */
  async startVoiceSessionWithCallback(
    config: Partial<import('../Features/VoiceSession').VoiceSessionConfig>,
    onEvent: import('../Features/VoiceSession').VoiceSessionEventListener
  ): Promise<import('../Features/VoiceSession').VoiceSessionHandle> {
    const { VoiceSessionHandle } = await import('../Features/VoiceSession');
    const session = new VoiceSessionHandle(config);
    session.onEvent(onEvent);
    await session.start();
    return session;
  },

  // ============================================================================
  // Utilities
  // ============================================================================

  /**
   * Get last error message from native layer
   */
  async getLastError(): Promise<string> {
    if (!isNativeModuleAvailable()) {
      return '';
    }
    const native = requireNativeModule();
    return native.getLastError();
  },

  /**
   * Get backend info
   */
  async getBackendInfo(): Promise<Record<string, unknown>> {
    if (!isNativeModuleAvailable()) {
      return {};
    }
    const native = requireNativeModule();
    const infoJson = await native.getBackendInfo();
    try {
      return JSON.parse(infoJson);
    } catch {
      return {};
    }
  },

  /**
   * Get supported capabilities
   */
  async getCapabilities(): Promise<string[]> {
    if (!isNativeModuleAvailable()) {
      return [];
    }
    const native = requireNativeModule();
    const capabilitiesJson = await native.getCapabilities();
    try {
      const parsed = JSON.parse(capabilitiesJson);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  },

  /**
   * Check if a capability is supported
   */
  async supportsCapability(capability: string): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.supportsCapability(capability);
  },

  // ============================================================================
  // Model Registry
  // ============================================================================

  /**
   * Get available models from the catalog
   *
   * This uses the JavaScript ModelRegistry service (same pattern as Swift SDK)
   * and does not require native module calls.
   *
   * @returns Array of model info objects
   *
   * @example
   * ```typescript
   * const models = await RunAnywhere.getAvailableModels();
   * const sttModels = models.filter(m => m.modality === 'stt');
   * ```
   */
  async getAvailableModels(): Promise<ModelInfo[]> {
    return ModelRegistry.getAvailableModels();
  },

  /**
   * Get available frameworks
   *
   * Returns an array of frameworks that have registered providers.
   * This matches the Swift SDK's getAvailableFrameworks() API.
   *
   * @returns Array of available frameworks
   *
   * @example
   * ```typescript
   * const frameworks = RunAnywhere.getAvailableFrameworks();
   * console.log('Available frameworks:', frameworks);
   * ```
   */
  getAvailableFrameworks(): import('../types').LLMFramework[] {
    const {
      ServiceRegistry,
    } = require('../Foundation/DependencyInjection/ServiceRegistry');

    // Get all registered LLM providers
    const llmProviders = ServiceRegistry.shared.allLLMProviders();

    // Extract unique frameworks from models provided by each provider
    const frameworksSet = new Set<import('../types').LLMFramework>();

    for (const provider of llmProviders) {
      if (provider.getProvidedModels) {
        const models = provider.getProvidedModels();
        for (const model of models) {
          // Add all compatible frameworks
          for (const framework of model.compatibleFrameworks) {
            frameworksSet.add(framework);
          }
          // Also add preferred framework if specified
          if (model.preferredFramework) {
            frameworksSet.add(model.preferredFramework);
          }
        }
      }
    }

    return Array.from(frameworksSet);
  },

  /**
   * Get models for a specific framework
   *
   * This matches the Swift SDK's getModelsForFramework() API.
   *
   * @param framework - The framework to query
   * @returns Array of models compatible with the framework
   *
   * @example
   * ```typescript
   * const llamaCppModels = RunAnywhere.getModelsForFramework(LLMFramework.LlamaCpp);
   * ```
   */
  async getModelsForFramework(
    framework: import('../types').LLMFramework
  ): Promise<ModelInfo[]> {
    const allModels = await ModelRegistry.getAvailableModels();
    return allModels.filter(
      (model) =>
        model.compatibleFrameworks.includes(framework) ||
        model.preferredFramework === framework
    );
  },

  // ============================================================================
  // Model Assignments API
  // ============================================================================

  /**
   * Fetch model assignments for the current device from the backend
   *
   * This method fetches models assigned to this device based on device type and platform.
   * Uses the ModelAssignmentService for server-side model catalog.
   *
   * Matches iOS: static func fetchModelAssignments(forceRefresh:) async throws -> [ModelInfo]
   *
   * @param forceRefresh - Force refresh even if cached models are available
   * @returns Array of ModelInfo objects assigned to this device
   * @throws Error if fetching fails
   *
   * @example
   * ```typescript
   * const models = await RunAnywhere.fetchModelAssignments();
   * console.log(`Found ${models.length} assigned models`);
   * ```
   */
  async fetchModelAssignments(forceRefresh = false): Promise<ModelInfo[]> {
    // Ensure SDK is initialized
    if (!initState.isCoreInitialized) {
      throw new Error('SDK not initialized. Call initialize() first.');
    }

    // Ensure services are ready
    await this.ensureServicesReady();

    logger.info('Fetching model assignments...');

    const modelAssignmentService =
      ServiceContainer.shared.modelAssignmentService;
    if (!modelAssignmentService) {
      throw new Error('ModelAssignmentService not available');
    }

    const models =
      await modelAssignmentService.fetchModelAssignments(forceRefresh);
    logger.info(`Successfully fetched ${models.length} model assignments`);
    return models;
  },

  /**
   * Get available models for a specific category
   *
   * Matches iOS: static func getModelsForCategory(_:) async throws -> [ModelInfo]
   *
   * @param category - The model category to filter models for
   * @returns Array of ModelInfo objects in the specified category
   *
   * @example
   * ```typescript
   * const sttModels = await RunAnywhere.getModelsForCategory(ModelCategory.STT);
   * ```
   */
  async getModelsForCategory(category: ModelCategory): Promise<ModelInfo[]> {
    // Ensure SDK is initialized
    if (!initState.isCoreInitialized) {
      throw new Error('SDK not initialized. Call initialize() first.');
    }

    await this.ensureServicesReady();

    const modelAssignmentService =
      ServiceContainer.shared.modelAssignmentService;
    if (!modelAssignmentService) {
      // Fallback to local filtering if service not available
      const allModels = await ModelRegistry.getAvailableModels();
      return allModels.filter((m) => m.category === category);
    }

    return modelAssignmentService.getModelsForCategory(category);
  },

  /**
   * Clear cached model assignments
   *
   * Matches iOS: static func clearModelAssignmentsCache() async
   */
  async clearModelAssignmentsCache(): Promise<void> {
    if (!initState.isCoreInitialized) {
      return;
    }

    const modelAssignmentService =
      ServiceContainer.shared.modelAssignmentService;
    if (modelAssignmentService) {
      modelAssignmentService.clearCache();
    }
  },

  /**
   * Register a model from a download URL
   *
   * Use this to add models for development or offline use.
   *
   * Matches iOS: static func registerModel(id:name:url:framework:modality:...)
   *
   * @param options - Model registration options
   * @returns The created ModelInfo
   *
   * @example
   * ```typescript
   * const model = await RunAnywhere.registerModel({
   *   name: 'My Custom Model',
   *   url: 'https://example.com/model.gguf',
   *   framework: LLMFramework.LlamaCpp,
   * });
   * ```
   */
  async registerModel(options: {
    id?: string;
    name: string;
    url: string;
    framework: LLMFramework;
    category?: ModelCategory;
    memoryRequirement?: number;
    supportsThinking?: boolean;
  }): Promise<ModelInfo> {
    const { ModelFormat, ConfigurationSource } = await import('../types/enums');
    const now = new Date().toISOString();

    const modelInfo: ModelInfo = {
      id: options.id ?? this._generateModelId(options.url),
      name: options.name,
      category: options.category ?? ModelCategory.Language,
      format: options.url.includes('.gguf')
        ? ModelFormat.GGUF
        : ModelFormat.GGUF,
      downloadURL: options.url,
      localPath: undefined,
      downloadSize: undefined,
      memoryRequired: options.memoryRequirement,
      compatibleFrameworks: [options.framework],
      preferredFramework: options.framework,
      supportsThinking: options.supportsThinking ?? false,
      metadata: { tags: [] },
      source: ConfigurationSource.Local,
      createdAt: now,
      updatedAt: now,
      syncPending: false,
      usageCount: 0,
      isDownloaded: false,
      isAvailable: true,
    };

    await ModelRegistry.registerModel(modelInfo);
    return modelInfo;
  },

  /**
   * Generate a stable model ID from URL
   * @internal
   */
  _generateModelId(url: string): string {
    // Extract filename without extension
    const urlObj = new URL(url);
    const pathname = urlObj.pathname;
    const filename = pathname.split('/').pop() ?? 'model';
    return filename.replace(/\.(gguf|bin|safetensors|tar\.gz|zip)$/i, '');
  },

  /**
   * Get info for a specific model
   *
   * @param modelId - Model ID
   * @returns Model info or null if not found
   */
  async getModelInfo(modelId: string): Promise<ModelInfo | null> {
    if (!isNativeModuleAvailable()) {
      return null;
    }
    const native = requireNativeModule();
    const infoJson = await native.getModelInfo(modelId);
    try {
      const result = JSON.parse(infoJson);
      return result === 'null' ? null : result;
    } catch {
      return null;
    }
  },

  /**
   * Check if a model is downloaded
   *
   * @param modelId - Model ID
   */
  async isModelDownloaded(modelId: string): Promise<boolean> {
    const { JSDownloadService } = require('../services/JSDownloadService');
    return JSDownloadService.isModelDownloaded(modelId);
  },

  /**
   * Get local path for a downloaded model
   *
   * @param modelId - Model ID
   * @returns Path or null if not downloaded
   */
  async getModelPath(modelId: string): Promise<string | null> {
    const { JSDownloadService } = require('../services/JSDownloadService');
    return JSDownloadService.getModelPath(modelId);
  },

  /**
   * Get list of downloaded models
   *
   * @returns Array of downloaded model info objects
   */
  async getDownloadedModels(): Promise<ModelInfo[]> {
    if (!isNativeModuleAvailable()) {
      return [];
    }
    const native = requireNativeModule();
    const modelsJson = await native.getDownloadedModels();
    try {
      return JSON.parse(modelsJson);
    } catch {
      return [];
    }
  },

  // ============================================================================
  // Model Download
  // ============================================================================

  /**
   * Download a model
   *
   * Uses native OkHttp (Android) / URLSession (iOS) for maximum download speed.
   * Bypasses the React Native JS bridge for direct native file transfer.
   *
   * @param modelId - Model ID to download
   * @param onProgress - Optional progress callback
   * @returns Promise that resolves to local file path when complete
   *
   * @example
   * ```typescript
   * const localPath = await RunAnywhere.downloadModel('smollm2-360m-q8-0', (progress) => {
   *   console.log(`Progress: ${(progress.progress * 100).toFixed(1)}%`);
   * });
   * console.log('Model downloaded to:', localPath);
   * ```
   */
  async downloadModel(
    modelId: string,
    onProgress?: (progress: DownloadProgress) => void
  ): Promise<string> {
    // Get model info from registry
    const modelInfo = await ModelRegistry.getModel(modelId);
    if (!modelInfo) {
      throw new Error(`Model not found: ${modelId}`);
    }

    if (!modelInfo.downloadURL) {
      throw new Error(`Model has no download URL: ${modelId}`);
    }

    // Get native file system module for fast downloads (bypasses JS bridge)
    const fs = requireFileSystemModule();

    // Determine file name with extension - preserve archive extensions for extraction
    let extension = '';
    if (modelInfo.downloadURL.includes('.gguf')) {
      extension = '.gguf';
    } else if (modelInfo.downloadURL.includes('.tar.bz2')) {
      extension = '.tar.bz2';
    } else if (modelInfo.downloadURL.includes('.tar.gz')) {
      extension = '.tar.gz';
    } else if (modelInfo.downloadURL.includes('.zip')) {
      extension = '.zip';
    }
    const fileName = `${modelId}${extension}`;

    logger.info(' Starting native download (OkHttp/URLSession):', {
      modelId,
      url: modelInfo.downloadURL,
    });

    // Track download state
    activeDownloads.set(modelId, 1);
    let lastLoggedProgress = -1;

    try {
      // Use native module for maximum download speed
      // Android: OkHttp with HTTP/1.1 (faster than HTTP/2 for large files)
      // iOS: URLSession with native download task
      await fs.downloadModel(
        fileName,
        modelInfo.downloadURL,
        (progress: number) => {
          // Only log every 10% to reduce noise
          const progressPct = Math.round(progress * 100);
          if (progressPct - lastLoggedProgress >= 10) {
            logger.debug(`Download progress: ${progressPct}%`);
            lastLoggedProgress = progressPct;
          }

          if (onProgress) {
            onProgress({
              modelId,
              bytesDownloaded: Math.round(
                progress * (modelInfo.downloadSize || 0)
              ),
              totalBytes: modelInfo.downloadSize || 0,
              progress,
            });
          }
        }
      );

      // Get the actual path where model was downloaded
      const destPath = await fs.getModelPath(fileName);

      logger.info(' Download completed:', {
        modelId,
        destPath,
      });

      // Keep the archive path - C++ extractArchiveIfNeeded will handle extraction
      // and finding the correct nested model folder when loading
      const updatedModel: ModelInfo = {
        ...modelInfo,
        localPath: destPath,
        isDownloaded: true,
      };
      await ModelRegistry.registerModel(updatedModel);

      return destPath;
    } finally {
      activeDownloads.delete(modelId);
    }
  },

  /**
   * Cancel an ongoing download
   *
   * @param modelId - Model ID being downloaded
   */
  async cancelDownload(modelId: string): Promise<boolean> {
    // Note: Native cancellation requires additional implementation
    if (activeDownloads.has(modelId)) {
      activeDownloads.delete(modelId);
      logger.info(`Marked download as cancelled: ${modelId}`);
      return true;
    }
    return false;
  },

  /**
   * Delete a downloaded model
   *
   * @param modelId - Model ID to delete
   */
  async deleteModel(modelId: string): Promise<boolean> {
    try {
      const fs = requireFileSystemModule();

      // Get model info to find the file name
      const modelInfo = await ModelRegistry.getModel(modelId);
      const extension = modelInfo?.downloadURL?.includes('.gguf')
        ? '.gguf'
        : '';
      const fileName = `${modelId}${extension}`;

      // Check if model exists and delete via native module
      const exists = await fs.modelExists(fileName);
      if (exists) {
        await fs.deleteModel(fileName);
        logger.info(`Deleted model: ${modelId}`);
      }

      // Also try without extension
      const existsPlain = await fs.modelExists(modelId);
      if (existsPlain) {
        await fs.deleteModel(modelId);
      }

      // Update registry
      if (modelInfo) {
        const updatedModel: ModelInfo = {
          ...modelInfo,
          localPath: undefined,
          isDownloaded: false,
        };
        await ModelRegistry.registerModel(updatedModel);
      }

      return true;
    } catch (error) {
      logger.error('Delete model error:', { error });
      return false;
    }
  },

  // ============================================================================
  // Factory Methods
  // ============================================================================

  /**
   * Create a new conversation
   *
   * @returns A new Conversation instance
   *
   * @example
   * ```typescript
   * const conversation = RunAnywhere.conversation();
   * const response1 = await conversation.send('Hello!');
   * const response2 = await conversation.send('What did I just say?');
   * ```
   */
  conversation(): Conversation {
    return new Conversation();
  },
};

// ============================================================================
// Types for Model Registry/Download
// ============================================================================

/**
 * Model information from the catalog
 * Re-exported from types/models.ts
 */
export type { ModelInfo } from '../types/models';

/**
 * Download progress information
 */
export interface DownloadProgress {
  modelId: string;
  bytesDownloaded: number;
  totalBytes: number;
  progress: number;
}

// Default export
