import { SDKException } from '../../Foundation/SDKException.js';
import { SDKLogger } from '../../Foundation/SDKLogger.js';
import { tryRunanywhereModule, type EmscriptenRunanywhereModule } from '../../runtime/EmscriptenModule.js';

const logger = new SDKLogger('HuggingFace');

// Session-only, in-memory holder for the Hugging Face token. A token is a
// secret and must never be persisted to browser storage (localStorage /
// IndexedDB / OPFS): those are readable by same-origin scripts/XSS and linger
// in the browser profile. The token lives only for the current page session
// and must be re-entered after a reload.
let sessionHfToken: string | null = null;

interface HfTokenModule extends EmscriptenRunanywhereModule {
  _rac_http_hf_token_set?(tokenPtr: number): number;
}

/**
 * Configure the Hugging Face token used by native download requests.
 *
 * The token is held in memory for the current session only and is never
 * persisted to browser storage. Current Web artifacts may not include
 * `_rac_http_hf_token_set`; the in-memory value is re-applied to a rebuilt
 * artifact during its next platform initialization.
 */
export function setHfToken(token: string | null): void {
  const normalized = token?.trim() || null;
  const module = tryRunanywhereModule() as HfTokenModule | null;
  const setNative = module?._rac_http_hf_token_set;

  if (typeof setNative === 'function' && module) {
    let ptr = 0;
    try {
      if (normalized) {
        const bytes = module.lengthBytesUTF8(normalized) + 1;
        ptr = module._malloc(bytes);
        module.stringToUTF8(normalized, ptr, bytes);
      }
      const rc = setNative.call(module, ptr);
      if (rc !== 0) {
        throw SDKException.fromCode(rc, 'Failed to set Hugging Face token.', 'setHfToken');
      }
    } finally {
      if (ptr) module._free(ptr);
    }
  } else {
    logger.debug('Native Hugging Face token export unavailable; using session-only in-memory storage.');
  }

  sessionHfToken = normalized;
}

export function getStoredHfToken(): string | null {
  return sessionHfToken;
}
