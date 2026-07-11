import { describe, expect, it } from 'vitest';
import {
  CONTROL_PLANE_RELAY_PREFIX,
  controlPlaneRelayIsEnabled,
  FIRST_PARTY_CONTROL_PLANE_BASE_URL,
  FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL,
  resolveSDKControlPlaneBaseURL,
} from './control-plane-relay';

describe('control-plane relay browser configuration', () => {
  it('parses only an explicit true build flag', () => {
    expect(controlPlaneRelayIsEnabled('true')).toBe(true);
    expect(controlPlaneRelayIsEnabled(' TRUE ')).toBe(true);
    expect(controlPlaneRelayIsEnabled('1')).toBe(false);
    expect(controlPlaneRelayIsEnabled(undefined)).toBe(false);
  });

  it('uses the same-origin relay only for the complete first-party contract', () => {
    expect(resolveSDKControlPlaneBaseURL({
      configuredBaseURL: FIRST_PARTY_CONTROL_PLANE_BASE_URL,
      apiKey: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL,
      pageOrigin: 'https://web.runanywhere.ai',
      relayEnabled: true,
    })).toBe(`https://web.runanywhere.ai${CONTROL_PLANE_RELAY_PREFIX}`);
  });

  it('supports loopback HTTP for local Vite without permitting remote HTTP', () => {
    expect(resolveSDKControlPlaneBaseURL({
      configuredBaseURL: FIRST_PARTY_CONTROL_PLANE_BASE_URL,
      apiKey: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL,
      pageOrigin: 'http://127.0.0.1:5173',
      relayEnabled: true,
    })).toBe(`http://127.0.0.1:5173${CONTROL_PLANE_RELAY_PREFIX}`);

    expect(resolveSDKControlPlaneBaseURL({
      configuredBaseURL: FIRST_PARTY_CONTROL_PLANE_BASE_URL,
      apiKey: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL,
      pageOrigin: 'http://web.runanywhere.ai',
      relayEnabled: true,
    })).toBe(FIRST_PARTY_CONTROL_PLANE_BASE_URL);
  });

  it.each([
    {
      configuredBaseURL: 'https://customer.example.com',
      apiKey: 'customer-key',
      relayEnabled: true,
    },
    {
      configuredBaseURL: FIRST_PARTY_CONTROL_PLANE_BASE_URL,
      apiKey: 'customer-key',
      relayEnabled: true,
    },
    {
      configuredBaseURL: FIRST_PARTY_CONTROL_PLANE_BASE_URL,
      apiKey: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL,
      relayEnabled: false,
    },
  ])('leaves custom or disabled configurations direct', (input) => {
    expect(resolveSDKControlPlaneBaseURL({
      ...input,
      pageOrigin: 'https://web.runanywhere.ai',
    })).toBe(input.configuredBaseURL);
  });

  it('rejects credential-bearing or request-specific page origins', () => {
    for (const pageOrigin of [
      'https://user:pass@web.runanywhere.ai',
      'https://web.runanywhere.ai/path',
      'https://web.runanywhere.ai?target=other',
    ]) {
      expect(resolveSDKControlPlaneBaseURL({
        configuredBaseURL: FIRST_PARTY_CONTROL_PLANE_BASE_URL,
        apiKey: FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL,
        pageOrigin,
        relayEnabled: true,
      })).toBe(FIRST_PARTY_CONTROL_PLANE_BASE_URL);
    }
  });
});
