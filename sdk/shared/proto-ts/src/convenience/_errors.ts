// Hand-written companion to the generated `<base>_convenience.ts` files.
// Owned by humans, NOT by idl/codegen/generate_ts_convenience.py.
//
// Validation failures emitted by `validate<Msg>` helpers throw a typed
// `ValidationError` carrying the canonical RunAnywhere validation shape:
//
//     { code: 'invalid_argument', category: 'validation',
//       fieldPath: '<Message>.<field>', message: '<human>' }
//
// This shape matches the proto-backed `SDKException` the Swift / Kotlin /
// Dart SDKs throw — the four SDKs are byte-isomorphic via the proto
// SDKError type. Cross-platform consumer code (the React Native ↔ shared
// validation layer, streaming-perf parity tests) can rely on the same
// discriminants on every platform:
//
//     try {
//       validateXxx(opts);
//     } catch (e) {
//       if (e instanceof ValidationError && e.code === 'invalid_argument') {
//         // structured handling: e.fieldPath identifies the failing field.
//       }
//     }
//
// See `idl/codegen/CONVENIENCE_CODEGEN_DESIGN.md §9.1` for the cross-SDK
// contract.

/** Canonical error-code discriminant for validation failures. */
export const VALIDATION_ERROR_CODE = 'invalid_argument' as const;

/** Canonical category discriminant for validation failures. */
export const VALIDATION_ERROR_CATEGORY = 'validation' as const;

/** Constructor options for {@link ValidationError}. */
export interface ValidationErrorInit {
  /** Human-readable, non-localized failure description. Required. */
  message: string;
  /** Dot-separated path to the field that failed (e.g. `STTOptions.sampleRate`). */
  fieldPath?: string;
  /** Discriminant code. Defaults to {@link VALIDATION_ERROR_CODE}. */
  code?: string;
  /** Discriminant category. Defaults to {@link VALIDATION_ERROR_CATEGORY}. */
  category?: string;
}

/**
 * Typed exception thrown by the generated `validate<Msg>` helpers.
 *
 * Shape matches the proto-backed `SDKException` exposed by the Swift /
 * Kotlin / Dart SDKs: `code`, `category`, `fieldPath`, and `message`.
 */
export class ValidationError extends Error {
  /** Discriminant code; `'invalid_argument'` for all validation failures. */
  public readonly code: string;
  /** Discriminant category; `'validation'` for all validation failures. */
  public readonly category: string;
  /** Dot-separated path to the failing field, e.g. `STTOptions.sampleRate`. */
  public readonly fieldPath?: string;

  constructor(init: ValidationErrorInit | string) {
    const opts: ValidationErrorInit =
      typeof init === 'string' ? { message: init } : init;
    super(opts.message);
    this.name = 'ValidationError';
    this.code = opts.code ?? VALIDATION_ERROR_CODE;
    this.category = opts.category ?? VALIDATION_ERROR_CATEGORY;
    this.fieldPath = opts.fieldPath;
    // Restore the prototype chain so `instanceof ValidationError` keeps
    // working when the bundle is transpiled to ES5 targets that lose the
    // built-in Error.prototype linkage.
    Object.setPrototypeOf(this, new.target.prototype);
  }
}
