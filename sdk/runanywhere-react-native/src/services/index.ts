/**
 * RunAnywhere React Native SDK - Services
 *
 * Core services for SDK functionality.
 *
 * NOTE: These services are placeholders and require native module methods
 * that are not yet implemented. They are excluded from the build for now.
 */

// TODO: Enable these exports once native module methods are implemented:
// export { ConfigurationService, type ConfigurationUpdateOptions } from './ConfigurationService';
// export { AuthenticationService, type AuthenticationResponse, type AuthenticationState, type DeviceRegistrationInfo } from './AuthenticationService';
// export { ModelRegistry, type ModelCriteria, type AddModelFromURLOptions } from './ModelRegistry';
// export { DownloadService, DownloadState, type DownloadProgress, type DownloadTask, type DownloadConfiguration, type ProgressCallback } from './DownloadService';

// Placeholder exports for type compatibility
export type ConfigurationUpdateOptions = Record<string, unknown>;
export type AuthenticationResponse = { success: boolean; token?: string };
export type AuthenticationState = { isAuthenticated: boolean; userId?: string; organizationId?: string; deviceId?: string };
export type DeviceRegistrationInfo = { deviceId: string; registered: boolean };
export type ModelCriteria = { category?: string; format?: string };
export type AddModelFromURLOptions = { url: string; modelId: string };
export type DownloadProgress = { modelId: string; progress: number; bytesDownloaded: number; totalBytes: number };
export type DownloadTask = { modelId: string; state: DownloadState; progress: number };
export type DownloadConfiguration = { concurrentDownloads: number; allowCellular: boolean };
export type ProgressCallback = (progress: DownloadProgress) => void;

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

export const ModelRegistry = {
  getInstance: () => ({
    initialize: async () => {},
    getModels: async () => [],
    getModel: async () => null,
  }),
};

export enum DownloadState {
  Idle = 'idle',
  Downloading = 'downloading',
  Paused = 'paused',
  Completed = 'completed',
  Failed = 'failed',
}

export const DownloadService = {
  getInstance: () => ({
    download: async () => {},
    pause: async () => {},
    resume: async () => {},
    cancel: async () => {},
    getProgress: async () => null,
  }),
};
