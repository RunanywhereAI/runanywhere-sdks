/**
 * ModuleRegistry.ts
 *
 * Central registry for external AI module implementations
 * Allows optional dependencies to register their implementations at runtime
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/ModuleRegistry.swift
 */

import type { STTServiceProvider } from '../Core/Protocols/Voice/STTServiceProvider';
import type { LLMServiceProvider } from '../Core/Protocols/LLM/LLMServiceProvider';
import type { TTSServiceProvider } from '../Core/Protocols/Voice/TTSServiceProvider';
import type { SpeakerDiarizationServiceProvider } from '../Core/Protocols/Voice/SpeakerDiarizationServiceProvider';
import type { VLMServiceProvider } from '../Core/Protocols/VLM/VLMServiceProvider';
import type { WakeWordServiceProvider } from '../Core/Protocols/Voice/WakeWordServiceProvider';

/**
 * Internal structure to track providers with their priorities
 */
interface PrioritizedProvider<T> {
  provider: T;
  priority: number;
}

/**
 * Central registry for external AI module implementations
 *
 * This allows optional dependencies to register their implementations
 * at runtime, enabling a plugin-based architecture where modules like
 * WhisperCPP, llama.cpp, and FluidAudioDiarization can be added as needed.
 *
 * @example
 * ```typescript
 * import { ModuleRegistry } from '@runanywhere/react-native';
 * import { WhisperSTTProvider } from '@runanywhere/whisper';
 *
 * // In your app initialization:
 * ModuleRegistry.shared.registerSTT(new WhisperSTTProvider());
 * ```
 */
export class ModuleRegistry {
  // MARK: - Singleton

  /**
   * Shared instance
   */
  public static readonly shared = new ModuleRegistry();

  // MARK: - Properties

  private sttProviders: PrioritizedProvider<STTServiceProvider>[] = [];
  private llmProviders: PrioritizedProvider<LLMServiceProvider>[] = [];
  private ttsProviders: PrioritizedProvider<TTSServiceProvider>[] = [];
  private speakerDiarizationProviders: SpeakerDiarizationServiceProvider[] = [];
  private vlmProviders: VLMServiceProvider[] = [];
  private wakeWordProviders: WakeWordServiceProvider[] = [];

  private constructor() {}

  // MARK: - Registration Methods

  /**
   * Register a Speech-to-Text provider with optional priority
   * Higher priority providers are preferred (default: 100)
   *
   * @param provider - STT service provider
   * @param priority - Priority (higher = preferred, default: 100)
   */
  public registerSTT(provider: STTServiceProvider, priority: number = 100): void {
    const prioritizedProvider: PrioritizedProvider<STTServiceProvider> = {
      provider,
      priority,
    };
    this.sttProviders.push(prioritizedProvider);
    // Sort by priority (higher first)
    this.sttProviders.sort((a, b) => b.priority - a.priority);
    console.log(
      `[ModuleRegistry] Registered STT provider: ${provider.name} with priority: ${priority}`
    );

    // Call provider's onRegistration lifecycle hook (if implemented)
    if ((provider as any).onRegistration && typeof (provider as any).onRegistration === 'function') {
      console.log(`[ModuleRegistry] Calling onRegistration() for STT provider: ${provider.name}`);
      (provider as any).onRegistration();
    }
  }

  /**
   * Register a Language Model provider with optional priority
   * Higher priority providers are preferred (default: 100)
   *
   * @param provider - LLM service provider
   * @param priority - Priority (higher = preferred, default: 100)
   */
  public registerLLM(provider: LLMServiceProvider, priority: number = 100): void {
    const prioritizedProvider: PrioritizedProvider<LLMServiceProvider> = {
      provider,
      priority,
    };
    this.llmProviders.push(prioritizedProvider);
    // Sort by priority (higher first)
    this.llmProviders.sort((a, b) => b.priority - a.priority);
    console.log(
      `[ModuleRegistry] Registered LLM provider: ${provider.name} with priority: ${priority}`
    );

    // Call provider's onRegistration lifecycle hook (if implemented)
    if (provider.onRegistration && typeof provider.onRegistration === 'function') {
      console.log(`[ModuleRegistry] Calling onRegistration() for provider: ${provider.name}`);
      provider.onRegistration();
    }
  }

  /**
   * Register a Text-to-Speech provider with optional priority
   * Higher priority providers are preferred (default: 100)
   *
   * @param provider - TTS service provider
   * @param priority - Priority (higher = preferred, default: 100)
   */
  public registerTTS(provider: TTSServiceProvider, priority: number = 100): void {
    const prioritizedProvider: PrioritizedProvider<TTSServiceProvider> = {
      provider,
      priority,
    };
    this.ttsProviders.push(prioritizedProvider);
    // Sort by priority (higher first)
    this.ttsProviders.sort((a, b) => b.priority - a.priority);
    console.log(
      `[ModuleRegistry] Registered TTS provider: ${provider.name} with priority: ${priority}`
    );

    // Call provider's onRegistration lifecycle hook (if implemented)
    if ((provider as any).onRegistration && typeof (provider as any).onRegistration === 'function') {
      console.log(`[ModuleRegistry] Calling onRegistration() for TTS provider: ${provider.name}`);
      (provider as any).onRegistration();
    }
  }

  /**
   * Register a Speaker Diarization provider
   *
   * @param provider - Speaker diarization service provider
   */
  public registerSpeakerDiarization(provider: SpeakerDiarizationServiceProvider): void {
    this.speakerDiarizationProviders.push(provider);
    console.log(`[ModuleRegistry] Registered Speaker Diarization provider: ${provider.name}`);
  }

  /**
   * Register a Vision Language Model provider
   *
   * @param provider - VLM service provider
   */
  public registerVLM(provider: VLMServiceProvider): void {
    this.vlmProviders.push(provider);
    console.log(`[ModuleRegistry] Registered VLM provider: ${provider.name}`);
  }

  /**
   * Register a Wake Word Detection provider
   *
   * @param provider - Wake word service provider
   */
  public registerWakeWord(provider: WakeWordServiceProvider): void {
    this.wakeWordProviders.push(provider);
    console.log(`[ModuleRegistry] Registered Wake Word provider: ${provider.name}`);
  }

  // MARK: - Provider Access

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

  /**
   * Get a VLM provider
   *
   * @returns VLM service provider or null if none available
   */
  public vlmProvider(): VLMServiceProvider | null {
    return this.vlmProviders[0] ?? null;
  }

  /**
   * Get ALL VLM providers
   *
   * @returns Array of VLM service providers
   */
  public allVLMProviders(): VLMServiceProvider[] {
    return [...this.vlmProviders];
  }

  /**
   * Get a Wake Word provider
   *
   * @returns Wake word service provider or null if none available
   */
  public wakeWordProvider(): WakeWordServiceProvider | null {
    return this.wakeWordProviders[0] ?? null;
  }

  /**
   * Get ALL Wake Word providers
   *
   * @returns Array of wake word service providers
   */
  public allWakeWordProviders(): WakeWordServiceProvider[] {
    return [...this.wakeWordProviders];
  }

  // MARK: - Availability Checks

  /**
   * Check if any STT provider is registered
   */
  public get hasSTT(): boolean {
    return this.sttProviders.length > 0;
  }

  /**
   * Check if any LLM provider is registered
   */
  public get hasLLM(): boolean {
    return this.llmProviders.length > 0;
  }

  /**
   * Check if any TTS provider is registered
   */
  public get hasTTS(): boolean {
    return this.ttsProviders.length > 0;
  }

  /**
   * Check if any Speaker Diarization provider is registered
   */
  public get hasSpeakerDiarization(): boolean {
    return this.speakerDiarizationProviders.length > 0;
  }

  /**
   * Check if any VLM provider is registered
   */
  public get hasVLM(): boolean {
    return this.vlmProviders.length > 0;
  }

  /**
   * Check if any Wake Word provider is registered
   */
  public get hasWakeWord(): boolean {
    return this.wakeWordProviders.length > 0;
  }

  /**
   * Clear all registered providers (useful for testing)
   */
  public clear(): void {
    this.sttProviders = [];
    this.llmProviders = [];
    this.ttsProviders = [];
    this.speakerDiarizationProviders = [];
    this.vlmProviders = [];
    this.wakeWordProviders = [];
  }
}

