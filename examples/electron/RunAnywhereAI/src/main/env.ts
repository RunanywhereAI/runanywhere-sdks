/**
 * Control-plane credentials, read from a gitignored `.env` (or the environment).
 *
 * Mirrors the Android example's `local.properties` contract: with both a base URL
 * and an API key set, the SDK initializes in PRODUCTION (org-scoped, authed
 * telemetry); with neither, DEVELOPMENT (keyless).
 *
 * Read in main because the sandboxed renderer has no filesystem access.
 */
import fs from 'node:fs';
import path from 'node:path';

import type { BackendConfig } from '../shared/ipc-contract';

import { APP_ROOT } from './paths';

/** Parse a minimal .env: `KEY=value`, `#` comments, optional surrounding quotes. */
function readDotEnv(file: string): Record<string, string> {
  const out: Record<string, string> = {};
  let raw: string;
  try {
    raw = fs.readFileSync(file, 'utf8');
  } catch {
    return out; // no .env is fine — fall back to process.env / keyless development
  }
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed === '' || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const eq = trimmed.indexOf('=');
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed
      .slice(eq + 1)
      .trim()
      .replace(/^['"]|['"]$/g, '');
    if (key !== '') out[key] = value;
  }
  return out;
}

export function backendConfig(): BackendConfig {
  const fromFile = readDotEnv(path.join(APP_ROOT, '.env'));
  // A real environment variable wins over the file, so a CI or shell override
  // does not need the file edited.
  const read = (key: string): string => (process.env[key] ?? fromFile[key] ?? '').trim();

  const apiKey = read('RUNANYWHERE_API_KEY');
  const baseUrl = read('RUNANYWHERE_BASE_URL');

  return {
    apiKey,
    baseUrl,
    environment: apiKey !== '' && baseUrl !== '' ? 'production' : 'development',
  };
}
