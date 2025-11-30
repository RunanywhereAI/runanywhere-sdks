/**
 * Settings Types
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Settings/
 */

/**
 * Routing policy for execution decisions
 */
export enum RoutingPolicy {
  Automatic = 'automatic',
  DeviceOnly = 'deviceOnly',
  PreferDevice = 'preferDevice',
  PreferCloud = 'preferCloud',
}

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
  routingPolicy: RoutingPolicy.Automatic,
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
  [RoutingPolicy.Automatic]: 'Automatic',
  [RoutingPolicy.DeviceOnly]: 'Device Only',
  [RoutingPolicy.PreferDevice]: 'Prefer Device',
  [RoutingPolicy.PreferCloud]: 'Prefer Cloud',
};

/**
 * Routing policy descriptions
 */
export const RoutingPolicyDescriptions: Record<RoutingPolicy, string> = {
  [RoutingPolicy.Automatic]:
    'Automatically chooses between device and cloud based on model availability and performance.',
  [RoutingPolicy.DeviceOnly]:
    'Only use on-device models. Requests will fail if no device model is available.',
  [RoutingPolicy.PreferDevice]:
    'Prefer on-device execution, fall back to cloud if needed.',
  [RoutingPolicy.PreferCloud]:
    'Prefer cloud execution, fall back to device if offline.',
};
