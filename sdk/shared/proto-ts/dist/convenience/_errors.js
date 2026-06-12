"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.ValidationError = exports.VALIDATION_ERROR_CATEGORY = exports.VALIDATION_ERROR_CODE = void 0;
/** Canonical error-code discriminant for validation failures. */
exports.VALIDATION_ERROR_CODE = 'invalid_argument';
/** Canonical category discriminant for validation failures. */
exports.VALIDATION_ERROR_CATEGORY = 'validation';
/**
 * Typed exception thrown by the generated `validate<Msg>` helpers.
 *
 * Shape matches the proto-backed `SDKException` exposed by the Swift /
 * Kotlin / Dart SDKs: `code`, `category`, `fieldPath`, and `message`.
 */
class ValidationError extends Error {
    /** Discriminant code; `'invalid_argument'` for all validation failures. */
    code;
    /** Discriminant category; `'validation'` for all validation failures. */
    category;
    /** Dot-separated path to the failing field, e.g. `STTOptions.sampleRate`. */
    fieldPath;
    constructor(init) {
        const opts = typeof init === 'string' ? { message: init } : init;
        super(opts.message);
        this.name = 'ValidationError';
        this.code = opts.code ?? exports.VALIDATION_ERROR_CODE;
        this.category = opts.category ?? exports.VALIDATION_ERROR_CATEGORY;
        this.fieldPath = opts.fieldPath;
        // Restore the prototype chain so `instanceof ValidationError` keeps
        // working when the bundle is transpiled to ES5 targets that lose the
        // built-in Error.prototype linkage.
        Object.setPrototypeOf(this, new.target.prototype);
    }
}
exports.ValidationError = ValidationError;
