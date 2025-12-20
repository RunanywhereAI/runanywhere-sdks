/**
 * ServiceRegistry.ts
 *
 * Unified registry for all AI service factories and providers.
 * Simple, clean architecture: Module -> Service -> Capability -> Public API
 *
 * This consolidates the previous ModuleRegistry (provider objects) and
 * ServiceRegistry (factory functions) into a single source of truth.
 *
 * Supports two registration patterns:
 * 1. Factory-based: registerSTTFactory(), createSTT()
 * 2. Provider-based: registerSTTProvider(), sttProvider()
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/ServiceRegistry.swift
 */

import type { STTConfiguration } from '../../Features/STT/STTConfiguration';
import type { LLMConfiguration } from '../../Features/LLM/LLMConfiguration';
import type { TTSConfiguration } from '../../Features/TTS/TTSConfiguration';
import type { VADConfiguration } from '../../Features/VAD/VADConfiguration';
import type { SpeakerDiarizationConfiguration } from '../../Features/SpeakerDiarization/SpeakerDiarizationConfiguration';
import type { STTService } from '../../Core/Protocols/Voice/STTService';
import type { LLMService } from '../../Core/Protocols/LLM/LLMService';
import type { TTSService } from '../../Core/Protocols/Voice/TTSService';
import type { SpeakerDiarizationService } from '../../Core/Protocols/Voice/SpeakerDiarizationService';
import type { STTServiceProvider } from '../../Core/Protocols/Voice/STTServiceProvider';
import type { LLMServiceProvider } from '../../Core/Protocols/LLM/LLMServiceProvider';
import type { TTSServiceProvider } from '../../Core/Protocols/Voice/TTSServiceProvider';
import type { SpeakerDiarizationServiceProvider } from '../../Core/Protocols/Voice/SpeakerDiarizationServiceProvider';
import { SDKError } from '../ErrorTypes/SDKError';
import { ErrorCode } from '../ErrorTypes/ErrorCodes';
import { ErrorCategory } from '../ErrorTypes/ErrorCategory';

// ============================================================================
// Provider Registration (for provider objects)
// ============================================================================

/**
 * Internal structure to track providers with their priorities
 */
interface PrioritizedProvider<T> {
  provider: T;
  priority: number;
}

// ============================================================================
// Service Factory Types
// ============================================================================

/**
 * Factory function for creating STT services
 */
export type STTServiceFactory = (config: STTConfiguration) => Promise<STTService>;

/**
 * Factory function for creating LLM services
 */
export type LLMServiceFactory = (config: LLMConfiguration) => Promise<LLMService>;

/**
 * Factory function for creating TTS services
 */
export type TTSServiceFactory = (config: TTSConfiguration) => Promise<TTSService>;

/**
 * Factory function for creating VAD services
 * Note: VAD uses a simpler interface (no separate protocol yet)
 */
export interface VADService {
  /** Initialize the VAD service */
  initialize(): Promise<void>;
  /** Check if service is ready */
  readonly isReady: boolean;
  /** Start voice activity detection */
  startDetection(): Promise<void>;
  /** Stop voice activity detection */
  stopDetection(): Promise<void>;
  /** Clean up resources */
  cleanup(): Promise<void>;
}

export type VADServiceFactory = (config: VADConfiguration) => Promise<VADService>;

/**
 * Factory function for creating Speaker Diarization services
 */
export type SpeakerDiarizationServiceFactory = (
  config: SpeakerDiarizationConfiguration
) => Promise<SpeakerDiarizationService>;

// ============================================================================
// Service Registration
// ============================================================================

/**
 * Registration info for a service factory.
 * Matches iOS ServiceRegistration struct.
 */
export interface ServiceRegistration<Factory> {
  /** Service name (e.g., "WhisperKit", "LlamaCpp") */
  readonly name: string;
  /** Priority (higher = preferred, default: 100) */
  readonly priority: number;
  /** Function to check if this factory can handle the given modelId */
  readonly canHandle: (modelId: string | null) => boolean;
  /** Factory function to create the service */
  readonly factory: Factory;
}

/**
 * Create a service registration
 */
export function createServiceRegistration<Factory>(
  name: string,
  priority: number,
  canHandle: (modelId: string | null) => boolean,
  factory: Factory
): ServiceRegistration<Factory> {
  return {
    name,
    priority,
    canHandle,
    factory,
  };
}

// ============================================================================
// Capability Error (matches iOS CapabilityError)
// ============================================================================

/**
 * Error thrown when a provider is not found for a service type.
 */
export class ProviderNotFoundError extends SDKError {
  constructor(serviceType: string) {
    super(ErrorCode.NotInitialized, `No ${serviceType} provider registered. Please register a provider first.`, {
      category: ErrorCategory.Component,
    });
    this.name = 'ProviderNotFoundError';
  }
}

// ============================================================================
// Service Registry
// ============================================================================

/**
 * Unified registry for all AI services.
 *
 * This is the single source of truth for service registration.
 * External modules register their factory closures here, and
 * capabilities use this registry to create service instances.
 *
 * @example
 * ```typescript
 * import { ServiceRegistry } from '@runanywhere/react-native';
 *
 * // Register your service
 * ServiceRegistry.shared.registerSTT(
 *   'WhisperKit',
 *   100,
 *   (modelId) => modelId?.includes('whisper') ?? false,
 *   async (config) => {
 *     const service = new WhisperKitSTT();
 *     await service.initialize(config.modelId);
 *     return service;
 *   }
 * );
 * ```
 */
export class ServiceRegistry {
  // MARK: - Singleton

  public static readonly shared = new ServiceRegistry();

  // MARK: - Factory Storage (factory-based registration)

  private sttRegistrations: ServiceRegistration<STTServiceFactory>[] = [];
  private llmRegistrations: ServiceRegistration<LLMServiceFactory>[] = [];
  private ttsRegistrations: ServiceRegistration<TTSServiceFactory>[] = [];
  private vadRegistrations: ServiceRegistration<VADServiceFactory>[] = [];
  private speakerDiarizationRegistrations: ServiceRegistration<SpeakerDiarizationServiceFactory>[] = [];

  // MARK: - Provider Storage (provider object-based registration)

  private sttProviders: PrioritizedProvider<STTServiceProvider>[] = [];
  private llmProviders: PrioritizedProvider<LLMServiceProvider>[] = [];
  private ttsProviders: PrioritizedProvider<TTSServiceProvider>[] = [];
  private speakerDiarizationProviders: SpeakerDiarizationServiceProvider[] = [];

  private constructor() {}

  // ============================================================================
  // STT Registration
  // ============================================================================

  /**
   * Register an STT service factory
   *
   * @param name - Service name (e.g., "WhisperKit")
   * @param priority - Priority (higher = preferred, default: 100)
   * @param canHandle - Function to check if this factory can handle the given modelId
   * @param factory - Factory function to create the service
   */
  public registerSTT(
    name: string,
    priority: number = 100,
    canHandle: (modelId: string | null) => boolean,
    factory: STTServiceFactory
  ): void {
    const registration = createServiceRegistration(name, priority, canHandle, factory);
    this.sttRegistrations.push(registration);
    this.sttRegistrations.sort((a, b) => b.priority - a.priority);
    console.log(`[ServiceRegistry] Registered STT service: ${name} (priority: ${priority})`);
  }

  /**
   * Create an STT service for the given model
   *
   * @param modelId - Model identifier to match
   * @param config - STT configuration
   * @returns Promise resolving to the created service
   * @throws ProviderNotFoundError if no provider can handle the modelId
   */
  public async createSTT(modelId: string | null, config: STTConfiguration): Promise<STTService> {
    const registration = this.sttRegistrations.find((r) => r.canHandle(modelId));
    if (!registration) {
      throw new ProviderNotFoundError(`STT service for model: ${modelId ?? 'default'}`);
    }

    console.log(`[ServiceRegistry] Creating STT service: ${registration.name} for model: ${modelId ?? 'default'}`);
    return registration.factory(config);
  }

  /**
   * Check if any STT service is registered
   */
  public get hasSTT(): boolean {
    return this.sttRegistrations.length > 0;
  }

  // ============================================================================
  // LLM Registration
  // ============================================================================

  /**
   * Register an LLM service factory
   *
   * @param name - Service name (e.g., "LlamaCpp")
   * @param priority - Priority (higher = preferred, default: 100)
   * @param canHandle - Function to check if this factory can handle the given modelId
   * @param factory - Factory function to create the service
   */
  public registerLLM(
    name: string,
    priority: number = 100,
    canHandle: (modelId: string | null) => boolean,
    factory: LLMServiceFactory
  ): void {
    const registration = createServiceRegistration(name, priority, canHandle, factory);
    this.llmRegistrations.push(registration);
    this.llmRegistrations.sort((a, b) => b.priority - a.priority);
    console.log(`[ServiceRegistry] Registered LLM service: ${name} (priority: ${priority})`);
  }

  /**
   * Create an LLM service for the given model
   *
   * @param modelId - Model identifier to match
   * @param config - LLM configuration
   * @returns Promise resolving to the created service
   * @throws ProviderNotFoundError if no provider can handle the modelId
   */
  public async createLLM(modelId: string | null, config: LLMConfiguration): Promise<LLMService> {
    const registration = this.llmRegistrations.find((r) => r.canHandle(modelId));
    if (!registration) {
      throw new ProviderNotFoundError(`LLM service for model: ${modelId ?? 'default'}`);
    }

    console.log(`[ServiceRegistry] Creating LLM service: ${registration.name} for model: ${modelId ?? 'default'}`);
    return registration.factory(config);
  }

  /**
   * Check if any LLM service is registered
   */
  public get hasLLM(): boolean {
    return this.llmRegistrations.length > 0;
  }

  // ============================================================================
  // TTS Registration
  // ============================================================================

  /**
   * Register a TTS service factory
   *
   * @param name - Service name (e.g., "SystemTTS")
   * @param priority - Priority (higher = preferred, default: 100)
   * @param canHandle - Function to check if this factory can handle the given voiceId
   * @param factory - Factory function to create the service
   */
  public registerTTS(
    name: string,
    priority: number = 100,
    canHandle: (voiceId: string | null) => boolean,
    factory: TTSServiceFactory
  ): void {
    const registration = createServiceRegistration(name, priority, canHandle, factory);
    this.ttsRegistrations.push(registration);
    this.ttsRegistrations.sort((a, b) => b.priority - a.priority);
    console.log(`[ServiceRegistry] Registered TTS service: ${name} (priority: ${priority})`);
  }

  /**
   * Create a TTS service for the given voice
   *
   * @param voiceId - Voice identifier to match
   * @param config - TTS configuration
   * @returns Promise resolving to the created service
   * @throws ProviderNotFoundError if no provider can handle the voiceId
   */
  public async createTTS(voiceId: string | null, config: TTSConfiguration): Promise<TTSService> {
    const registration = this.ttsRegistrations.find((r) => r.canHandle(voiceId));
    if (!registration) {
      throw new ProviderNotFoundError(`TTS service for voice: ${voiceId ?? 'default'}`);
    }

    console.log(`[ServiceRegistry] Creating TTS service: ${registration.name} for voice: ${voiceId ?? 'default'}`);
    return registration.factory(config);
  }

  /**
   * Check if any TTS service is registered
   */
  public get hasTTS(): boolean {
    return this.ttsRegistrations.length > 0;
  }

  // ============================================================================
  // VAD Registration
  // ============================================================================

  /**
   * Register a VAD service factory
   * Note: VAD typically has only one implementation, so canHandle always returns true
   *
   * @param name - Service name (e.g., "SileroVAD")
   * @param priority - Priority (higher = preferred, default: 100)
   * @param factory - Factory function to create the service
   */
  public registerVAD(
    name: string,
    priority: number = 100,
    factory: VADServiceFactory
  ): void {
    const registration = createServiceRegistration<VADServiceFactory>(
      name,
      priority,
      () => true, // VAD typically handles all requests
      factory
    );
    this.vadRegistrations.push(registration);
    this.vadRegistrations.sort((a, b) => b.priority - a.priority);
    console.log(`[ServiceRegistry] Registered VAD service: ${name} (priority: ${priority})`);
  }

  /**
   * Create a VAD service
   *
   * @param config - VAD configuration
   * @returns Promise resolving to the created service
   * @throws ProviderNotFoundError if no provider is registered
   */
  public async createVAD(config: VADConfiguration): Promise<VADService> {
    const registration = this.vadRegistrations[0];
    if (!registration) {
      throw new ProviderNotFoundError('VAD service');
    }

    console.log(`[ServiceRegistry] Creating VAD service: ${registration.name}`);
    return registration.factory(config);
  }

  /**
   * Check if any VAD service is registered
   */
  public get hasVAD(): boolean {
    return this.vadRegistrations.length > 0;
  }

  // ============================================================================
  // Speaker Diarization Registration
  // ============================================================================

  /**
   * Register a Speaker Diarization service factory
   *
   * @param name - Service name (e.g., "FluidAudio")
   * @param priority - Priority (higher = preferred, default: 100)
   * @param canHandle - Function to check if this factory can handle the given modelId (default: always true)
   * @param factory - Factory function to create the service
   */
  public registerSpeakerDiarization(
    name: string,
    priority: number = 100,
    canHandle: (modelId: string | null) => boolean = () => true,
    factory: SpeakerDiarizationServiceFactory
  ): void {
    const registration = createServiceRegistration(name, priority, canHandle, factory);
    this.speakerDiarizationRegistrations.push(registration);
    this.speakerDiarizationRegistrations.sort((a, b) => b.priority - a.priority);
    console.log(`[ServiceRegistry] Registered Speaker Diarization service: ${name} (priority: ${priority})`);
  }

  /**
   * Create a Speaker Diarization service
   *
   * @param modelId - Optional model identifier to match
   * @param config - Speaker diarization configuration
   * @returns Promise resolving to the created service
   * @throws ProviderNotFoundError if no provider can handle the modelId
   */
  public async createSpeakerDiarization(
    modelId: string | null,
    config: SpeakerDiarizationConfiguration
  ): Promise<SpeakerDiarizationService> {
    const registration = this.speakerDiarizationRegistrations.find((r) => r.canHandle(modelId));
    if (!registration) {
      throw new ProviderNotFoundError('Speaker Diarization service');
    }

    console.log(`[ServiceRegistry] Creating Speaker Diarization service: ${registration.name}`);
    return registration.factory(config);
  }

  /**
   * Check if any Speaker Diarization service is registered
   */
  public get hasSpeakerDiarization(): boolean {
    return this.speakerDiarizationRegistrations.length > 0;
  }

  // ============================================================================
  // Availability
  // ============================================================================

  /**
   * List of registered service types
   */
  public get registeredServices(): string[] {
    const services: string[] = [];
    if (this.hasSTT) services.push('STT');
    if (this.hasLLM) services.push('LLM');
    if (this.hasTTS) services.push('TTS');
    if (this.hasVAD) services.push('VAD');
    if (this.hasSpeakerDiarization) services.push('SpeakerDiarization');
    return services;
  }

  // ============================================================================
  // Provider Registration (migrated from ModuleRegistry)
  // ============================================================================

  /**
   * Register an STT provider object with optional priority
   * Higher priority providers are preferred (default: 100)
   *
   * @param provider - STT service provider
   * @param priority - Priority (higher = preferred, default: 100)
   */
  public registerSTTProvider(provider: STTServiceProvider, priority: number = 100): void {
    const prioritizedProvider: PrioritizedProvider<STTServiceProvider> = {
      provider,
      priority,
    };
    this.sttProviders.push(prioritizedProvider);
    // Sort by priority (higher first)
    this.sttProviders.sort((a, b) => b.priority - a.priority);
    console.log(
      `[ServiceRegistry] Registered STT provider: ${provider.name} with priority: ${priority}`
    );

    // Call provider's onRegistration lifecycle hook (if implemented)
    if ((provider as any).onRegistration && typeof (provider as any).onRegistration === 'function') {
      console.log(`[ServiceRegistry] Calling onRegistration() for STT provider: ${provider.name}`);
      (provider as any).onRegistration();
    }
  }

  /**
   * Register an LLM provider object with optional priority
   * Higher priority providers are preferred (default: 100)
   *
   * @param provider - LLM service provider
   * @param priority - Priority (higher = preferred, default: 100)
   */
  public registerLLMProvider(provider: LLMServiceProvider, priority: number = 100): void {
    const prioritizedProvider: PrioritizedProvider<LLMServiceProvider> = {
      provider,
      priority,
    };
    this.llmProviders.push(prioritizedProvider);
    // Sort by priority (higher first)
    this.llmProviders.sort((a, b) => b.priority - a.priority);
    console.log(
      `[ServiceRegistry] Registered LLM provider: ${provider.name} with priority: ${priority}`
    );

    // Call provider's onRegistration lifecycle hook (if implemented)
    if (provider.onRegistration && typeof provider.onRegistration === 'function') {
      console.log(`[ServiceRegistry] Calling onRegistration() for provider: ${provider.name}`);
      provider.onRegistration();
    }
  }

  /**
   * Register a TTS provider object with optional priority
   * Higher priority providers are preferred (default: 100)
   *
   * @param provider - TTS service provider
   * @param priority - Priority (higher = preferred, default: 100)
   */
  public registerTTSProvider(provider: TTSServiceProvider, priority: number = 100): void {
    const prioritizedProvider: PrioritizedProvider<TTSServiceProvider> = {
      provider,
      priority,
    };
    this.ttsProviders.push(prioritizedProvider);
    // Sort by priority (higher first)
    this.ttsProviders.sort((a, b) => b.priority - a.priority);
    console.log(
      `[ServiceRegistry] Registered TTS provider: ${provider.name} with priority: ${priority}`
    );

    // Call provider's onRegistration lifecycle hook (if implemented)
    if ((provider as any).onRegistration && typeof (provider as any).onRegistration === 'function') {
      console.log(`[ServiceRegistry] Calling onRegistration() for TTS provider: ${provider.name}`);
      (provider as any).onRegistration();
    }
  }

  /**
   * Register a Speaker Diarization provider object
   *
   * @param provider - Speaker diarization service provider
   */
  public registerSpeakerDiarizationProvider(provider: SpeakerDiarizationServiceProvider): void {
    this.speakerDiarizationProviders.push(provider);
    console.log(`[ServiceRegistry] Registered Speaker Diarization provider: ${provider.name}`);
  }

  // ============================================================================
  // Provider Access (migrated from ModuleRegistry)
  // ============================================================================

  /**
   * Get an STT provider for the specified model (returns highest priority match)
   *
   * @param modelId - Optional model ID to match
   * @returns STT service provider or null if none available
   */
  public sttProvider(modelId?: string | null): STTServiceProvider | null {
    if (modelId) {
      const match = this.sttProviders.find((p) => p.provider.canHandle(modelId));
      return match?.provider ?? null;
    }
    return this.sttProviders[0]?.provider ?? null;
  }

  /**
   * Get ALL STT providers that can handle the specified model (sorted by priority)
   *
   * @param modelId - Optional model ID to match
   * @returns Array of STT service providers
   */
  public allSTTProviders(modelId?: string | null): STTServiceProvider[] {
    if (modelId) {
      return this.sttProviders
        .filter((p) => p.provider.canHandle(modelId))
        .map((p) => p.provider);
    }
    return this.sttProviders.map((p) => p.provider);
  }

  /**
   * Get an LLM provider for the specified model (returns highest priority match)
   *
   * @param modelId - Optional model ID to match
   * @returns LLM service provider or null if none available
   */
  public llmProvider(modelId?: string | null): LLMServiceProvider | null {
    if (modelId) {
      const match = this.llmProviders.find((p) => p.provider.canHandle(modelId));
      return match?.provider ?? null;
    }
    return this.llmProviders[0]?.provider ?? null;
  }

  /**
   * Get ALL LLM providers that can handle the specified model (sorted by priority)
   *
   * @param modelId - Optional model ID to match
   * @returns Array of LLM service providers
   */
  public allLLMProviders(modelId?: string | null): LLMServiceProvider[] {
    if (modelId) {
      return this.llmProviders
        .filter((p) => p.provider.canHandle(modelId))
        .map((p) => p.provider);
    }
    return this.llmProviders.map((p) => p.provider);
  }

  /**
   * Get a TTS provider for the specified model (returns highest priority match)
   *
   * @param modelId - Optional model ID to match
   * @returns TTS service provider or null if none available
   */
  public ttsProvider(modelId?: string | null): TTSServiceProvider | null {
    if (modelId) {
      const match = this.ttsProviders.find((p) => p.provider.canHandle(modelId));
      return match?.provider ?? null;
    }
    return this.ttsProviders[0]?.provider ?? null;
  }

  /**
   * Get ALL TTS providers that can handle the specified model (sorted by priority)
   *
   * @param modelId - Optional model ID to match
   * @returns Array of TTS service providers
   */
  public allTTSProviders(modelId?: string | null): TTSServiceProvider[] {
    if (modelId) {
      return this.ttsProviders
        .filter((p) => p.provider.canHandle(modelId))
        .map((p) => p.provider);
    }
    return this.ttsProviders.map((p) => p.provider);
  }

  /**
   * Get a Speaker Diarization provider
   *
   * @returns Speaker diarization service provider or null if none available
   */
  public speakerDiarizationProvider(): SpeakerDiarizationServiceProvider | null {
    return this.speakerDiarizationProviders[0] ?? null;
  }

  /**
   * Get ALL Speaker Diarization providers
   *
   * @returns Array of speaker diarization service providers
   */
  public allSpeakerDiarizationProviders(): SpeakerDiarizationServiceProvider[] {
    return [...this.speakerDiarizationProviders];
  }

  // ============================================================================
  // Reset
  // ============================================================================

  /**
   * Reset all registrations (useful for testing)
   */
  public reset(): void {
    // Reset factory registrations
    this.sttRegistrations = [];
    this.llmRegistrations = [];
    this.ttsRegistrations = [];
    this.vadRegistrations = [];
    this.speakerDiarizationRegistrations = [];
    // Reset provider registrations
    this.sttProviders = [];
    this.llmProviders = [];
    this.ttsProviders = [];
    this.speakerDiarizationProviders = [];
    console.log('[ServiceRegistry] Service registry reset');
  }

  /**
   * Clear all registered providers (alias for reset, for backward compatibility)
   */
  public clear(): void {
    this.reset();
  }
}
