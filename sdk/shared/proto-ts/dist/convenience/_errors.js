"use strict";
// Hand-written companion to the generated `<base>_convenience.ts` files.
// Owned by humans, NOT by idl/codegen/generate_ts_convenience.py.
//
// Validation failures emitted by `validate<Msg>` helpers throw a typed
// `ValidationError` so callers can `catch` it without inspecting the
// generic `Error.message` string. The class shape mirrors the SDKException
// convention used by the Kotlin / Dart SDKs (see
// idl/codegen/CONVENIENCE_CODEGEN_DESIGN.md §9.1).
Object.defineProperty(exports, "__esModule", { value: true });
exports.ValidationError = void 0;
class ValidationError extends Error {
    constructor(message) {
        super(message);
        this.name = 'ValidationError';
        // Restore the prototype chain so `instanceof ValidationError` keeps
        // working when the bundle is transpiled to ES5 targets that lose the
        // built-in Error.prototype linkage.
        Object.setPrototypeOf(this, new.target.prototype);
    }
}
exports.ValidationError = ValidationError;
