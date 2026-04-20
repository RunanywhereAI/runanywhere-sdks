// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import { Environment, type AuthData, RunAnywhereError } from './Types.js';
import { requireNativeSessionBindings } from './NativeBindings.js';

/**
 * SDK-wide state: init, environment, API key, auth tokens, device
 * registration. Wraps ra_state_* C ABI via host bindings.
 */
export const SDKState = {
  initialize(options: {
    apiKey: string;
    environment?: Environment;
    baseUrl?: string;
    deviceId?: string;
  }): void {
    const b = requireNativeSessionBindings();
    const rc = b.stateInitialize(
      options.environment ?? Environment.Production,
      options.apiKey,
      options.baseUrl ?? '',
      options.deviceId ?? '');
    if (rc !== 0) throw new RunAnywhereError(rc, 'ra_state_initialize failed');
  },

  get isInitialized(): boolean {
    const b = requireNativeSessionBindings();
    return b.stateIsInitialized();
  },

  reset(): void {
    const b = requireNativeSessionBindings(); b.stateReset();
  },

  get environment(): Environment {
    const b = requireNativeSessionBindings();
    return b.stateGetEnvironment() as Environment;
  },

  get apiKey(): string    { return requireNativeSessionBindings().stateGetApiKey(); },
  get baseUrl(): string   { return requireNativeSessionBindings().stateGetBaseUrl(); },
  get deviceId(): string  { return requireNativeSessionBindings().stateGetDeviceId(); },

  setAuth(data: AuthData): void {
    const b = requireNativeSessionBindings();
    const rc = b.stateSetAuth(data);
    if (rc !== 0) throw new RunAnywhereError(rc, 'ra_state_set_auth failed');
  },

  get accessToken(): string    { return requireNativeSessionBindings().stateGetAccessToken(); },
  get refreshToken(): string   { return requireNativeSessionBindings().stateGetRefreshToken(); },
  get userId(): string         { return requireNativeSessionBindings().stateGetUserId(); },
  get organizationId(): string { return requireNativeSessionBindings().stateGetOrganizationId(); },
  get isAuthenticated(): boolean { return requireNativeSessionBindings().stateIsAuthenticated(); },
  get tokenExpiresAt(): number { return requireNativeSessionBindings().stateGetTokenExpiresAt(); },

  tokenNeedsRefresh(horizonSeconds = 60): boolean {
    return requireNativeSessionBindings().stateTokenNeedsRefresh(horizonSeconds);
  },

  clearAuth(): void { requireNativeSessionBindings().stateClearAuth(); },

  get isDeviceRegistered(): boolean { return requireNativeSessionBindings().stateIsDeviceRegistered(); },
  setDeviceRegistered(r: boolean): void { requireNativeSessionBindings().stateSetDeviceRegistered(r); },

  validateApiKey(key: string): boolean { return requireNativeSessionBindings().stateValidateApiKey(key); },
  validateBaseUrl(url: string): boolean { return requireNativeSessionBindings().stateValidateBaseUrl(url); },
};
