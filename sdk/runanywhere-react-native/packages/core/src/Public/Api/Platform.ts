/**
 * Platform services the v3 modality spec does not cover: storage housekeeping,
 * logging, control-plane identity, and the Hugging Face download token. These
 * are retained namespaces, not spec verbs.
 */

import type { StorageInfo } from '@runanywhere/proto-ts/storage_types';

import { isNativeModuleAvailable, requireNativeModule } from '../../native';
import {
  cleanTempFiles,
  clearCache,
  getStorageInfo,
} from '../Extensions/Storage/RunAnywhere+Storage';
import {
  addLogDestination,
  configureLogging,
  flushLogs,
  setDebugMode,
  setLocalLoggingEnabled,
  setLogLevel,
} from '../Extensions/RunAnywhere+Logging';

/** SDK storage housekeeping. */
export const storage = {
  /** Device, app, and per-model storage usage, or `null` when unavailable. */
  info(): Promise<StorageInfo | null> {
    return getStorageInfo();
  },

  /** Clear the SDK cache directory. */
  clearCache(): Promise<void> {
    return clearCache();
  },

  /** Clear the SDK temp directory. */
  cleanTempFiles(): Promise<void> {
    return cleanTempFiles();
  },
};

/** Log verbosity and destinations. */
export const logging = {
  configure: configureLogging,
  setLevel: setLogLevel,
  setLocalEnabled: setLocalLoggingEnabled,
  setDebugMode,
  addDestination: addLogDestination,
  flush: flushLogs,
};

/** Control-plane identity, available once the network phase has landed. */
export const auth = {
  /** Whether the SDK holds valid control-plane credentials. */
  async isAuthenticated(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    return requireNativeModule().isAuthenticated();
  },

  /** Whether this device is registered with the control plane. */
  async isDeviceRegistered(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    return requireNativeModule().isDeviceRegistered();
  },

  /** Authenticated user id, or `null`. */
  async userId(): Promise<string | null> {
    if (!isNativeModuleAvailable()) return null;
    const value = await requireNativeModule().getUserId();
    return value ? value : null;
  },

  /** Authenticated organization id, or `null`. */
  async organizationId(): Promise<string | null> {
    if (!isNativeModuleAvailable()) return null;
    const value = await requireNativeModule().getOrganizationId();
    return value ? value : null;
  },

  /**
   * Set the Hugging Face bearer token used for gated model downloads; pass an
   * empty string to clear it.
   */
  async setHuggingFaceToken(token: string): Promise<void> {
    if (!isNativeModuleAvailable()) return;
    await requireNativeModule().setHfToken(token);
  },
};
