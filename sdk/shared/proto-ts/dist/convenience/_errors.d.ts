/** Canonical error-code discriminant for validation failures. */
export declare const VALIDATION_ERROR_CODE: "invalid_argument";
/** Canonical category discriminant for validation failures. */
export declare const VALIDATION_ERROR_CATEGORY: "validation";
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
export declare class ValidationError extends Error {
    /** Discriminant code; `'invalid_argument'` for all validation failures. */
    readonly code: string;
    /** Discriminant category; `'validation'` for all validation failures. */
    readonly category: string;
    /** Dot-separated path to the failing field, e.g. `STTOptions.sampleRate`. */
    readonly fieldPath?: string;
    constructor(init: ValidationErrorInit | string);
}
