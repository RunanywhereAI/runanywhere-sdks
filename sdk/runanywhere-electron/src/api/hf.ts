// hf.ts — the Hugging Face bearer token, mirrored on the TypeScript side.
//
// Commons owns the canonical token. `rac_http_hf_token_set` stores it and
// `rac_http_client_default.cpp` attaches the `Authorization` header inside its
// own dispatcher, so the value cannot be read back across the ABI and cannot
// leak into a log. Every transfer the download orchestrator runs is
// authenticated by that alone.
//
// `download.ts` is the exception, and it is the reason this file exists. Its
// HuggingFace repo resolver — the tree listing, the LFS digest lookup, and the
// GGUF/mmproj fetch behind `backend.ensure` — runs on Node's own http/https and
// never reaches the commons dispatcher, so nothing attaches a header for it. A
// gated repo therefore 401'd on that path while the same model downloaded fine
// through the orchestrator, which is a difference no caller can see or explain.
//
// So the token is kept here as well, and the eligibility rules are reproduced
// exactly rather than approximated (`rac::http::is_hf_host` /
// `hf_bearer_for_url`):
//
//   - **https only**, and the host must be **exactly** `huggingface.co` or
//     `hf.co`. Subdomains are excluded on purpose: an LFS/CDN redirect target
//     must never receive the bearer token.
//   - A caller-supplied `Authorization` header is never overridden.
//
// Mirrored in the SDK rather than in the app for the obvious reason: an example
// app must not know how model downloads authenticate.

import * as fs from 'fs';
import * as path from 'path';

/**
 * The explicit override, or `undefined` when none was ever set — which is where
 * the environment fallback applies. An empty string is a *deliberate* opt-out
 * and must not silently re-enable that fallback, so it is stored as `''` rather
 * than collapsed to `undefined`.
 */
let override: string | undefined;

let environmentToken: string | undefined;
let environmentResolved = false;

/** Trimmed, or `undefined` when nothing usable is left. */
function normalized(raw: string): string | undefined {
  const trimmed = raw.trim();
  return trimmed ? trimmed : undefined;
}

function readTokenFile(file: string): string | undefined {
  try {
    return normalized(fs.readFileSync(file, 'utf8'));
  } catch {
    return undefined; // absent or unreadable: try the next candidate
  }
}

/**
 * The environment and token-file chain commons resolves, mirrored here.
 *
 * Without it a developer authenticated the ordinary way (`hf auth login`, which
 * writes a token file) would get 401s on this path and successes on every other
 * one. Order matches `rac::http::env_token` and `huggingface_hub`: `HF_TOKEN`,
 * then `$HF_TOKEN_PATH`, then `$HF_HOME/token`, then
 * `~/.cache/huggingface/token`.
 *
 * Resolved once, as commons does, so both paths agree for the life of the
 * process instead of diverging when a file changes underneath them.
 */
function resolveEnvironmentToken(): string | undefined {
  if (environmentResolved) return environmentToken;
  environmentResolved = true;
  const env = process.env;
  const direct = env.HF_TOKEN ? normalized(env.HF_TOKEN) : undefined;
  if (direct) {
    environmentToken = direct;
    return environmentToken;
  }
  const candidates = [
    env.HF_TOKEN_PATH,
    env.HF_HOME ? path.join(env.HF_HOME, 'token') : undefined,
    env.HOME ? path.join(env.HOME, '.cache', 'huggingface', 'token') : undefined,
  ];
  for (const candidate of candidates) {
    if (!candidate) continue;
    const value = readTokenFile(candidate);
    if (value) {
      environmentToken = value;
      return environmentToken;
    }
  }
  return undefined;
}

/**
 * Set the token this process's Node-side HuggingFace requests authenticate
 * with. `null` returns to the environment lookup; an empty string clears the
 * override and disables that fallback.
 *
 * Commons is told separately (through `RaBackend.hfTokenSet`) so both transfer
 * paths carry the same credential; the facade's `setHfToken` drives both.
 */
export function setHuggingFaceToken(token: string | null): void {
  override = token === null ? undefined : token.trim();
}

/** Exact-host match over https, matching commons' `is_hf_host`. */
function isHuggingFaceHost(url: string): boolean {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  if (parsed.protocol !== 'https:') return false;
  // Reject userinfo outright, the way commons does — `https://x@evil.example`
  // must not be read as the huggingface.co host that follows an `@`.
  if (parsed.username || parsed.password) return false;
  const host = parsed.hostname.toLowerCase();
  return host === 'huggingface.co' || host === 'hf.co';
}

/**
 * The `Authorization` header value for `url`, or `undefined` when the token
 * must not be attached.
 *
 * An explicitly stored token wins outright — including an empty one, which is a
 * deliberate opt-out and must not silently fall through to the environment.
 */
export function huggingFaceBearer(url: string): string | undefined {
  if (!isHuggingFaceHost(url)) return undefined;
  const token = override ?? resolveEnvironmentToken();
  return token ? `Bearer ${token}` : undefined;
}
