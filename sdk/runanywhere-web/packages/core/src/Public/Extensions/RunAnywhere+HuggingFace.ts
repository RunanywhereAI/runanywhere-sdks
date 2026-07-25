import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException.js';
import { SDKLogger } from '../../Foundation/SDKLogger.js';
import { tryRunanywhereModule, type EmscriptenRunanywhereModule } from '../../runtime/EmscriptenModule.js';

const logger = new SDKLogger('HuggingFace');
const HF_TOKEN_STORAGE_KEY = 'rac_sdk_plaintext_hf_token';

interface HfTokenModule extends EmscriptenRunanywhereModule {
  _rac_http_hf_token_set?(tokenPtr: number): number;
}

/**
 * Configure the Hugging Face token used by native download requests.
 *
 * Current Web artifacts may not include `_rac_http_hf_token_set`. In that
 * case the browser fallback is localStorage under the explicitly plaintext
 * PlatformAdapter storage namespace; it is supplied to a rebuilt artifact
 * during its next platform initialization.
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
    logger.debug('Native Hugging Face token export unavailable; using browser plaintext storage fallback.');
  }

  try {
    if (typeof localStorage !== 'undefined') {
      if (normalized) localStorage.setItem(HF_TOKEN_STORAGE_KEY, normalized);
      else localStorage.removeItem(HF_TOKEN_STORAGE_KEY);
    }
  } catch (error) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_STORAGE_ERROR,
      `Failed to persist Hugging Face token: ${error instanceof Error ? error.message : String(error)}`,
      'setHfToken',
    );
  }
}

export function getStoredHfToken(): string | null {
  try {
    return typeof localStorage === 'undefined'
      ? null
      : localStorage.getItem(HF_TOKEN_STORAGE_KEY);
  } catch {
    return null;
  }
}
