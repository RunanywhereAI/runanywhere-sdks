export interface APIConfiguration {
  apiKey: string;
  baseURL: string;
}

type APIConfigurationApplyHandler = (
  configuration: APIConfiguration | null
) => Promise<void>;

let sessionConfiguration: APIConfiguration | null = null;
let applyHandler: APIConfigurationApplyHandler | null = null;

function isLoopbackHost(hostname: string): boolean {
  return (
    hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '[::1]'
  );
}

/**
 * Validate a credential-bearing control-plane configuration without exposing
 * either value in an error. Release builds require HTTPS. Development builds
 * may opt into cleartext only for an explicit loopback host.
 */
export function normalizeAPIConfiguration(
  apiKey: string,
  baseURL: string,
  options: { allowInsecureLoopback?: boolean } = {}
): APIConfiguration {
  const normalizedKey = apiKey.trim();
  if (normalizedKey.length < 8) {
    throw new Error('Enter a valid API key.');
  }

  const trimmedURL = baseURL.trim();
  if (!trimmedURL) {
    throw new Error('Enter a backend URL.');
  }

  let parsed: URL;
  try {
    parsed = new URL(
      trimmedURL.includes('://') ? trimmedURL : `https://${trimmedURL}`
    );
  } catch {
    throw new Error('Enter a valid backend URL.');
  }

  if (parsed.username || parsed.password || parsed.search || parsed.hash) {
    throw new Error(
      'The backend URL cannot contain credentials, query parameters, or a fragment.'
    );
  }

  const isSecure = parsed.protocol === 'https:';
  const isAllowedDevelopmentLoopback =
    options.allowInsecureLoopback === true &&
    parsed.protocol === 'http:' &&
    isLoopbackHost(parsed.hostname);
  if (!isSecure && !isAllowedDevelopmentLoopback) {
    throw new Error('The backend URL must use HTTPS.');
  }

  const serialized = parsed.toString();
  const normalizedURL =
    parsed.pathname === '/' && serialized.endsWith('/')
      ? serialized.slice(0, -1)
      : serialized;
  return { apiKey: normalizedKey, baseURL: normalizedURL };
}

export function getSessionAPIConfiguration(): APIConfiguration | null {
  return sessionConfiguration ? { ...sessionConfiguration } : null;
}

export function setAPIConfigurationApplyHandler(
  handler: APIConfigurationApplyHandler
): () => void {
  applyHandler = handler;
  return () => {
    if (applyHandler === handler) applyHandler = null;
  };
}

export async function applySessionAPIConfiguration(
  apiKey: string,
  baseURL: string,
  options: { allowInsecureLoopback?: boolean } = {}
): Promise<APIConfiguration> {
  const configuration = normalizeAPIConfiguration(apiKey, baseURL, options);
  if (!applyHandler) {
    throw new Error('SDK reconfiguration is not available yet.');
  }
  await applyHandler(configuration);
  sessionConfiguration = configuration;
  return { ...configuration };
}

export async function clearSessionAPIConfiguration(): Promise<void> {
  sessionConfiguration = null;
  if (!applyHandler) {
    throw new Error('SDK reconfiguration is not available yet.');
  }
  await applyHandler(null);
}
