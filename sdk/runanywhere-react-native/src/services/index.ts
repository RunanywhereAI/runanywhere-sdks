/**
 * RunAnywhere React Native SDK - Services
 *
 * Core services for SDK functionality.
 */

// Model Registry - Manages model discovery and registration (JS-based)
export {
  ModelRegistry,
  type ModelCriteria,
  type AddModelFromURLOptions,
} from './ModelRegistry';

// JS Download Service - JavaScript-based download using react-native-fs
export {
  JSDownloadService,
  type JSDownloadProgress,
} from './JSDownloadService';

// Download Service - Native-based download (requires native module implementation)
export {
  DownloadService,
  DownloadState,
  type DownloadProgress,
  type DownloadTask,
  type DownloadConfiguration,
  type ProgressCallback,
} from './DownloadService';

// TTS Service - Native implementation available
export {
  SystemTTSService,
  getVoicesByLanguage,
  getDefaultVoice,
  getPlatformDefaultVoice,
  PlatformVoices,
} from './SystemTTSService';

// Conversation Manager - For managing LLM conversation context
export {
  ConversationManager,
  type ConversationConfig,
  type ConversationStats,
  type ConversationSnapshot,
} from './ConversationManager';

// Placeholder exports for type compatibility
export type ConfigurationUpdateOptions = Record<string, unknown>;
export type AuthenticationResponse = { success: boolean; token?: string };
export type AuthenticationState = {
  isAuthenticated: boolean;
  userId?: string;
  organizationId?: string;
  deviceId?: string;
};
export type DeviceRegistrationInfo = { deviceId: string; registered: boolean };

// Placeholder service stubs
export const ConfigurationService = {
  getInstance: () => ({
    initialize: async () => {},
    getConfiguration: async () => ({}),
    updateConfiguration: async () => {},
  }),
};

export const AuthenticationService = {
  getInstance: () => ({
    authenticate: async () => ({ success: false }),
    isAuthenticated: async () => false,
    logout: async () => {},
  }),
};
