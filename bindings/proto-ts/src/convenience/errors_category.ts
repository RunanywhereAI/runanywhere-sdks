/**
 * Canonical `ErrorCode` / `rac_result_t` → `ErrorCategory` range table for
 * every TypeScript SDK (Web, React Native, Electron).
 *
 * HAND-AUTHORED — not produced by `idl/codegen/generate_ts_convenience.py`.
 * The fold from numeric ranges onto the 9-bucket proto `ErrorCategory` exists
 * only as C++ control flow, not as proto annotations, so there is nothing for
 * the IDL codegen to emit. Do not invent a second table in an SDK.
 *
 * This table is the richer 18-range mapping historically shared byte-for-byte
 * by Web and React Native. It deliberately covers bands beyond |329|
 * (archive/extraction 350–369, calibration 370–379, module/service 400–499,
 * platform/adapter 500–599, backend/runtime 600–699, …) so those defined
 * proto codes keep meaningful categories instead of collapsing to INTERNAL.
 *
 * C++ commons (`rac::foundation::rac_result_to_proto_category` in
 * `core/src/foundation/rac_proto_adapters.cpp`) currently
 * only maps |100|–|329| and falls through to INTERNAL — that is a known
 * under-mapping, deliberately deferred (see `ts_shared_layer.md` Known issue).
 * Do NOT “fix” this TS table down to match commons.
 *
 * Callers may pass either the signed C ABI code or the positive proto
 * `ErrorCode` (abs magnitude); both are accepted via `Math.abs`.
 */

import { ErrorCategory } from '../errors';

export { ErrorCategory };

/**
 * Map a proto `ErrorCode` (positive) or signed `rac_result_t` to the matching
 * proto `ErrorCategory`.
 */
export function categoryForCode(code: number): ErrorCategory {
  if (code === 0) return ErrorCategory.ERROR_CATEGORY_UNSPECIFIED;
  const abs = Math.abs(Math.trunc(code));
  if (abs === 0) return ErrorCategory.ERROR_CATEGORY_UNSPECIFIED;
  if (abs >= 100 && abs <= 109) return ErrorCategory.ERROR_CATEGORY_CONFIGURATION;
  if (abs >= 110 && abs <= 129) return ErrorCategory.ERROR_CATEGORY_MODEL;
  if (abs >= 130 && abs <= 149) return ErrorCategory.ERROR_CATEGORY_INTERNAL;
  if (abs >= 150 && abs <= 179) return ErrorCategory.ERROR_CATEGORY_NETWORK;
  if ((abs >= 180 && abs <= 219) || (abs >= 280 && abs <= 299)) {
    return ErrorCategory.ERROR_CATEGORY_IO;
  }
  if (abs >= 220 && abs <= 229) return ErrorCategory.ERROR_CATEGORY_INTERNAL;
  if (abs >= 230 && abs <= 249) return ErrorCategory.ERROR_CATEGORY_COMPONENT;
  if (abs >= 250 && abs <= 279) return ErrorCategory.ERROR_CATEGORY_VALIDATION;
  if (abs >= 300 && abs <= 319) return ErrorCategory.ERROR_CATEGORY_COMPONENT;
  if (abs >= 320 && abs <= 329) return ErrorCategory.ERROR_CATEGORY_AUTH;
  if (abs >= 330 && abs <= 349) return ErrorCategory.ERROR_CATEGORY_AUTH;
  if (abs >= 350 && abs <= 369) return ErrorCategory.ERROR_CATEGORY_IO;
  if (abs >= 370 && abs <= 379) return ErrorCategory.ERROR_CATEGORY_VALIDATION;
  if (abs >= 380 && abs <= 389) return ErrorCategory.ERROR_CATEGORY_INTERNAL;
  if (abs >= 400 && abs <= 499) return ErrorCategory.ERROR_CATEGORY_COMPONENT;
  if (abs >= 500 && abs <= 599) return ErrorCategory.ERROR_CATEGORY_CONFIGURATION;
  if (abs >= 600 && abs <= 699) return ErrorCategory.ERROR_CATEGORY_COMPONENT;
  if (abs >= 700 && abs <= 799) return ErrorCategory.ERROR_CATEGORY_INTERNAL;
  if (abs >= 800 && abs <= 899) return ErrorCategory.ERROR_CATEGORY_INTERNAL;
  if (abs >= 900 && abs <= 999) return ErrorCategory.ERROR_CATEGORY_INTERNAL;
  return ErrorCategory.ERROR_CATEGORY_UNSPECIFIED;
}
