/**
 * Browser relay contract for the first-party RunAnywhere control plane.
 *
 * Native mobile clients can call the control plane directly. Browsers cannot:
 * the mobile endpoint intentionally does not opt into arbitrary browser CORS.
 * The Web example therefore sends only this exact upstream through a fixed
 * same-origin path. Vite and Vercel own the corresponding server-side relay.
 * No request-controlled upstream is accepted, which keeps this from becoming
 * an open proxy or SSRF surface.
 */

export const FIRST_PARTY_CONTROL_PLANE_BASE_URL =
  'https://runanywhere-backend-production.up.railway.app';

export const CONTROL_PLANE_RELAY_PREFIX = '/api/runanywhere';

/**
 * Public marker passed to the SDK while the real API key remains server-side.
 *
 * This value is intentionally non-secret. The relay requires it as a narrow
 * protocol discriminator and replaces it in both the `apikey` header and the
 * authenticate JSON body before contacting the fixed first-party upstream.
 */
export const FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL =
  'runanywhere-first-party-relay';

interface ControlPlaneRelayInput {
  configuredBaseURL: string;
  apiKey: string | undefined;
  pageOrigin: string;
  relayEnabled: boolean;
}

/** Parse the one browser-safe build flag that enables the first-party relay. */
export function controlPlaneRelayIsEnabled(value: string | undefined): boolean {
  return value?.trim().toLowerCase() === 'true';
}

function isLoopbackHostname(hostname: string): boolean {
  return hostname === 'localhost'
    || hostname === '127.0.0.1'
    || hostname === '[::1]'
    || hostname === '::1';
}

/**
 * Resolve the SDK-facing URL while retaining the mobile URL in Settings.
 *
 * Relaying is fail-closed: the explicit build flag, public relay credential,
 * and runtime base must all match this contract. Deployed pages must be HTTPS;
 * loopback HTTP remains available for local Vite development. Custom SDK
 * endpoints and user-entered credentials remain direct and must publish their
 * own CORS policy.
 */
export function resolveSDKControlPlaneBaseURL({
  configuredBaseURL,
  apiKey,
  pageOrigin,
  relayEnabled,
}: ControlPlaneRelayInput): string {
  if (
    !relayEnabled
    || apiKey !== FIRST_PARTY_CONTROL_PLANE_RELAY_CREDENTIAL
    || configuredBaseURL !== FIRST_PARTY_CONTROL_PLANE_BASE_URL
  ) {
    return configuredBaseURL;
  }

  try {
    const origin = new URL(pageOrigin);
    const transportIsAllowed = origin.protocol === 'https:'
      || (origin.protocol === 'http:' && isLoopbackHostname(origin.hostname));
    if (
      !transportIsAllowed
      || origin.username.length > 0
      || origin.password.length > 0
      || origin.pathname !== '/'
      || origin.search.length > 0
      || origin.hash.length > 0
    ) {
      return configuredBaseURL;
    }
    return new URL(CONTROL_PLANE_RELAY_PREFIX, origin.origin).toString().replace(/\/$/, '');
  } catch {
    return configuredBaseURL;
  }
}
