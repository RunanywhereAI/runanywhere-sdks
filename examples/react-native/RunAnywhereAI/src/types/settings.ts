/**
 * Settings Types
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Settings/
 */

import { RoutingPolicy } from '@runanywhere/core';

export { RoutingPolicy };

export const ROUTING_POLICY_OPTIONS = [
  RoutingPolicy.ROUTING_POLICY_UNSPECIFIED,
  RoutingPolicy.ROUTING_POLICY_PREFER_LOCAL,
  RoutingPolicy.ROUTING_POLICY_PREFER_CLOUD,
  RoutingPolicy.ROUTING_POLICY_COST_OPTIMIZED,
  RoutingPolicy.ROUTING_POLICY_LATENCY_OPTIMIZED,
  RoutingPolicy.ROUTING_POLICY_MANUAL,
] as const;

/**
 * Generation settings
 */
export interface GenerationSettings {
  /** Temperature (0.0 - 2.0) */
  temperature: number;

  /** Max tokens (500 - 20000) */
  maxTokens: number;

  /** Top P (optional) */
  topP?: number;

  /** Top K (optional) */
  topK?: number;
}

/**
 * App settings
 */
export interface AppSettings {
  /** Routing policy */
  routingPolicy: RoutingPolicy;

  /** Generation settings */
  generation: GenerationSettings;

  /** API key (if set) */
  apiKey?: string;

  /** Whether API key is configured */
  isApiKeyConfigured: boolean;

  /** Enable debug mode */
  debugMode: boolean;
}

/**
 * Storage info
 */
export interface StorageInfo {
  /** Total device storage in bytes */
  totalStorage: number;

  /** Storage used by app in bytes */
  appStorage: number;

  /** Storage used by models in bytes */
  modelsStorage: number;

  /** Cache size in bytes */
  cacheSize: number;

  /** Free space in bytes */
  freeSpace: number;
}

/**
 * Default settings values
 */
export const DEFAULT_SETTINGS: AppSettings = {
  routingPolicy: RoutingPolicy.ROUTING_POLICY_UNSPECIFIED,
  generation: {
    temperature: 0.7,
    maxTokens: 10000,
  },
  isApiKeyConfigured: false,
  debugMode: false,
};

/**
 * Settings constraints
 */
export const SETTINGS_CONSTRAINTS = {
  temperature: {
    min: 0,
    max: 2,
    step: 0.1,
  },
  maxTokens: {
    min: 500,
    max: 20000,
    step: 500,
  },
};

/**
 * Routing policy display names
 */
export const RoutingPolicyDisplayNames: Record<RoutingPolicy, string> = {
  [RoutingPolicy.ROUTING_POLICY_UNSPECIFIED]: 'Automatic',
  [RoutingPolicy.ROUTING_POLICY_PREFER_LOCAL]: 'Prefer Local',
  [RoutingPolicy.ROUTING_POLICY_PREFER_CLOUD]: 'Prefer Cloud',
  [RoutingPolicy.ROUTING_POLICY_COST_OPTIMIZED]: 'Cost Optimized',
  [RoutingPolicy.ROUTING_POLICY_LATENCY_OPTIMIZED]: 'Latency Optimized',
  [RoutingPolicy.ROUTING_POLICY_MANUAL]: 'Manual',
  [RoutingPolicy.UNRECOGNIZED]: 'Unrecognized',
};

/**
 * Routing policy descriptions
 */
export const RoutingPolicyDescriptions: Record<RoutingPolicy, string> = {
  [RoutingPolicy.ROUTING_POLICY_UNSPECIFIED]:
    'Automatically chooses between device and cloud based on model availability and performance.',
  [RoutingPolicy.ROUTING_POLICY_PREFER_LOCAL]:
    'Prefer on-device execution when a local model is available.',
  [RoutingPolicy.ROUTING_POLICY_PREFER_CLOUD]:
    'Prefer cloud execution when a configured provider is available.',
  [RoutingPolicy.ROUTING_POLICY_COST_OPTIMIZED]:
    'Choose the lowest-cost route based on model and provider availability.',
  [RoutingPolicy.ROUTING_POLICY_LATENCY_OPTIMIZED]:
    'Choose the lowest-latency route based on current availability.',
  [RoutingPolicy.ROUTING_POLICY_MANUAL]:
    'Use the route explicitly selected by the user.',
  [RoutingPolicy.UNRECOGNIZED]:
    'Routing policy is not recognized by this SDK version.',
};

/**
 * AsyncStorage keys for generation settings persistence
 * Matches iOS/Android naming convention for cross-platform consistency
 */
export const GENERATION_SETTINGS_KEYS = {
  TEMPERATURE: 'defaultTemperature',
  MAX_TOKENS: 'defaultMaxTokens',
  SYSTEM_PROMPT: 'defaultSystemPrompt',
} as const;
