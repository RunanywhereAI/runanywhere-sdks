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
export declare function categoryForCode(code: number): ErrorCategory;
