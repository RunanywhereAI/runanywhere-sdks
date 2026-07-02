/**
 * wasm_platform_shims.cpp
 *
 * Platform-specific shims for Emscripten/WASM compilation.
 * Provides stubs or alternative implementations for features
 * that are not available in the WASM environment.
 *
 * Key facts about Emscripten's defines:
 *   - __EMSCRIPTEN__ is always defined
 *   - __linux__ is NOT defined (unlike some other WASM toolchains)
 *   - __clang__ IS defined (Emscripten uses clang)
 *   - __unix__ is NOT defined
 *
 * This means:
 *   - backtrace() code (guarded by __APPLE__ || __linux__) is excluded -- OK
 *   - RAC_API gets visibility("default") via __clang__ -- OK
 *   - Apple/Android code paths are excluded -- OK
 */

#ifdef __EMSCRIPTEN__

#include <emscripten/emscripten.h>

// =============================================================================
// Verification: Platform adapter sanity check
// =============================================================================

extern "C" {

/**
 * Return the platform identifier for this WASM build.
 * Called from TypeScript to verify the module is the correct platform.
 */
EMSCRIPTEN_KEEPALIVE
const char* rac_wasm_get_platform(void) {
    return "emscripten";
}

} // extern "C"

#endif // __EMSCRIPTEN__
