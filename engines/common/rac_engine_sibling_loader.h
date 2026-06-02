#ifndef RUNANYWHERE_ENGINES_COMMON_SIBLING_LOADER_H
#define RUNANYWHERE_ENGINES_COMMON_SIBLING_LOADER_H

/**
 * Cross-register a sibling engine backend that lives in a separate shared
 * library, working around Android's per-class-loader linker namespaces.
 *
 * Motivation: when an engine (e.g. onnx) wants to opportunistically register a
 * sibling backend (e.g. sherpa) that another module loaded via
 * System.loadLibrary, `dlsym(RTLD_DEFAULT, "<sibling>_register")` is NOT enough
 * on Android. Libraries loaded by a non-bootclassloader live in that class
 * loader's private linker namespace, so RTLD_DEFAULT (which searches the
 * caller's global group) cannot see the sibling's exported symbols even though
 * the .so is already mapped into the process. The fix is to `dlopen()` the
 * sibling by name — which returns a handle into the current namespace and bumps
 * its refcount — then `dlsym()` from that explicit handle.
 *
 * This helper packages exactly that fallback chain so any engine's JNI bridge
 * can cross-register a sibling with a single parameterized call, instead of
 * hand-rolling the dlopen/dlsym dance (a layering inversion where one engine's
 * glue hardcodes another engine's .so name and register symbol). The names stay
 * caller-supplied, so this header knows nothing about any specific sibling.
 *
 * Resolution order (first hit wins):
 *   1. dlsym(RTLD_DEFAULT, register_symbol)            — already-global hosts
 *      (iOS / WASM / RAC_STATIC_PLUGINS, or a sibling already in the global
 *      group) resolve here with no extra dlopen.
 *   2. dlopen(solib_name, RTLD_NOW | RTLD_GLOBAL) then dlsym(handle, ...)
 *      — Android's namespaced case. RTLD_GLOBAL promotes the sibling so later
 *      RTLD_DEFAULT lookups (and its own transitive deps) can see it too.
 *
 * The dlopen handle is intentionally NOT dlclose()'d: a successful register
 * installs a vtable the registry keeps live for the process lifetime, so the
 * sibling .so must stay mapped. Leaking one handle per successful cross-register
 * (at most once per sibling) is the correct, deliberate trade.
 *
 * Header-only / inline — no .cpp, no CMake wiring. Internal to the engines/
 * tree; not part of the stable rac_* C ABI.
 */

#include <dlfcn.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

// Local logging tag/macros, namespaced to this header so it is self-contained
// regardless of whether the including TU defined its own LOGi/LOGe.
#define RAC_SIBLING_LOADER_TAG "Engine.SiblingLoader"

/**
 * Signature every sibling register/unregister entry point must have:
 * `extern "C" rac_result_t name(void)`. Matches rac_backend_<name>_register().
 */
typedef rac_result_t (*rac_engine_sibling_fn_t)(void);

/**
 * Resolve `register_symbol` (falling back to dlopen(`solib_name`)) and call it.
 *
 * @param solib_name      Sibling shared-object file name to dlopen if the symbol
 *                        is not already globally visible, e.g.
 *                        "librac_backend_sherpa.so".
 * @param register_symbol Exported C entry point to resolve and invoke, e.g.
 *                        "rac_backend_sherpa_register". Must have signature
 *                        `rac_result_t(void)`.
 * @return The sibling register fn's own rac_result_t when it was found and
 *         called; RAC_ERROR_MODULE_NOT_FOUND when the symbol could not be
 *         resolved via either path (treated as "sibling unavailable", a
 *         non-fatal condition for opportunistic cross-registration). Callers
 *         typically tolerate both RAC_SUCCESS and RAC_ERROR_MODULE_ALREADY_REGISTERED.
 *
 * Mirrors onnx's original inline workaround exactly: dlopen first (so a freshly
 * namespaced sibling becomes resolvable), cache dlerror() once on failure
 * (POSIX clears the per-thread error after the first read), then dlsym from the
 * handle when we have one, else from RTLD_DEFAULT.
 */
static inline rac_result_t rac_engine_register_sibling(const char* solib_name,
                                                       const char* register_symbol) {
    void* handle = dlopen(solib_name, RTLD_NOW | RTLD_GLOBAL);
    if (handle == nullptr) {
        // Fall back to RTLD_DEFAULT in case the .so is already global (iOS / WASM).
        // Read dlerror() exactly once: POSIX clears the per-thread error after the
        // first read, so reading it twice would log "no error" on a real failure.
        const char* err = dlerror();
        RAC_LOG_WARNING(RAC_SIBLING_LOADER_TAG,
                        "dlopen(%s) failed (%s); falling back to RTLD_DEFAULT", solib_name,
                        err ? err : "no error");
    }

    auto* sibling_register = reinterpret_cast<rac_engine_sibling_fn_t>(
        handle != nullptr ? dlsym(handle, register_symbol) : dlsym(RTLD_DEFAULT, register_symbol));

    if (sibling_register == nullptr) {
        RAC_LOG_INFO(RAC_SIBLING_LOADER_TAG,
                     "%s symbol not present; sibling backend unavailable", register_symbol);
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_result_t rc = sibling_register();
    if (rc != RAC_SUCCESS && rc != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        RAC_LOG_WARNING(RAC_SIBLING_LOADER_TAG, "%s returned %d", register_symbol, rc);
    } else {
        RAC_LOG_INFO(RAC_SIBLING_LOADER_TAG, "sibling backend registered via %s", register_symbol);
    }
    return rc;
}

#endif  // RUNANYWHERE_ENGINES_COMMON_SIBLING_LOADER_H
