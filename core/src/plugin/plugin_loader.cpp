/**
 * @file plugin_loader.cpp
 * @brief Dynamic plugin loader implementation.
 *
 * Two compile paths:
 *   - RAC_PLUGIN_MODE_STATIC (iOS / WASM / forced) — `rac_registry_load_plugin`
 *     returns RAC_ERROR_FEATURE_NOT_AVAILABLE so calling it never half-loads
 *     a plugin. Static plugins enter the registry via
 *     `RAC_STATIC_PLUGIN_REGISTER(<name>)` from `rac_plugin_entry.h`.
 *   - RAC_PLUGIN_MODE_SHARED (Android / Linux / macOS / Windows default) — uses
 *     `dlopen(RTLD_NOW | RTLD_LOCAL)` on POSIX and `LoadLibraryA` on Win32.
 *
 * Symbol-resolution convention (from path → entry-symbol name):
 *   `/path/to/librunanywhere_<name>.so`        → `rac_plugin_entry_<name>`
 *   `/path/to/librunanywhere_<name>.dylib`     → `rac_plugin_entry_<name>`
 *   `c:\path\to\runanywhere_<name>.dll`        → `rac_plugin_entry_<name>`
 *   Plugins not following the `runanywhere_` infix may name their file
 *   anything ending in their plugin metadata.name (the loader strips the
 *   `lib` prefix and the file extension and looks for the longest
 *   `rac_plugin_entry_*` symbol that matches the suffix).
 */

#include "plugin_registry_internal.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_loader.h"

#if !defined(RAC_PLUGIN_MODE_STATIC) || !RAC_PLUGIN_MODE_STATIC
#if defined(_WIN32)
#include <windows.h>
using rac_lib_handle_t = HMODULE;
static rac_lib_handle_t rac_dl_open(const char* p) {
    return LoadLibraryA(p);
}
static void* rac_dl_sym(rac_lib_handle_t h, const char* s) {
    return reinterpret_cast<void*>(GetProcAddress(h, s));
}
static void rac_dl_close(rac_lib_handle_t h) {
    FreeLibrary(h);
}
static const char* rac_dl_error() {
    return "LoadLibrary failed";
}
#else
#include <dlfcn.h>
using rac_lib_handle_t = void*;
static rac_lib_handle_t rac_dl_open(const char* p) {
    return dlopen(p, RTLD_NOW | RTLD_LOCAL);
}
static void* rac_dl_sym(rac_lib_handle_t h, const char* s) {
    return dlsym(h, s);
}
static void rac_dl_close(rac_lib_handle_t h) {
    dlclose(h);
}
static const char* rac_dl_error() {
    return dlerror();
}
#endif
#endif

namespace {

constexpr const char* LOG_CAT = "PluginLoader";

#if !defined(RAC_PLUGIN_MODE_STATIC) || !RAC_PLUGIN_MODE_STATIC
/* RAII guard for a dlopen handle. Auto-closes on scope exit unless `release()`
 * is called on the final success branch. Replaces the prior manual
 * `rac_dl_close(handle)` on every error path: a future maintainer who adds a
 * new validation step between the dlopen and the final
 * `rac_plugin_registry_set_dl_handle` no longer needs to remember to balance
 * the open — the destructor handles it. Linux `dlopen` refcounts the mapping,
 * so any leaked handle would persist for the whole process lifetime. */
struct DlGuard {
    rac_lib_handle_t h{nullptr};
    DlGuard() = default;
    explicit DlGuard(rac_lib_handle_t handle) : h(handle) {}
    ~DlGuard() {
        if (h != nullptr)
            rac_dl_close(h);
    }
    DlGuard(const DlGuard&) = delete;
    DlGuard& operator=(const DlGuard&) = delete;
    DlGuard(DlGuard&& other) noexcept : h(other.h) { other.h = nullptr; }
    DlGuard& operator=(DlGuard&& other) noexcept {
        if (this != &other) {
            if (h != nullptr)
                rac_dl_close(h);
            h = other.h;
            other.h = nullptr;
        }
        return *this;
    }
    rac_lib_handle_t release() noexcept {
        auto r = h;
        h = nullptr;
        return r;
    }
};

/**
 * Derive the plugin entry-symbol name from a library path.
 *
 * Examples:
 *   "/lib/librunanywhere_llamacpp.so"  → "rac_plugin_entry_llamacpp"
 *   "../runanywhere_onnx.dylib"         → "rac_plugin_entry_onnx"
 *   "C:\plugins\runanywhere_qhexrt.dll" → "rac_plugin_entry_qhexrt"
 *   "/foo/myplugin.so"                  → "rac_plugin_entry_myplugin"
 *
 * The "rac_plugin_entry_" prefix is fixed; everything between the last path
 * separator + optional "lib" prefix + optional "runanywhere_" prefix and the
 * file extension is the plugin name.
 */
std::string entry_symbol_from_path(const char* path) {
    if (path == nullptr)
        return {};
    std::string s(path);
    // Drop directory.
    auto last_sep = s.find_last_of("/\\");
    if (last_sep != std::string::npos)
        s.erase(0, last_sep + 1);
    // Drop "lib" prefix (POSIX shared-lib convention; harmless on Win32).
    if (s.starts_with("lib"))
        s.erase(0, 3);
    // Drop file extension.
    auto dot = s.find('.');
    if (dot != std::string::npos)
        s.erase(dot);
    // Drop optional "runanywhere_" infix used by in-tree plugins.
    if (s.starts_with("runanywhere_"))
        s.erase(0, std::strlen("runanywhere_"));
    return std::string("rac_plugin_entry_") + s;
}
#endif

}  // namespace

extern "C" {

uint32_t rac_plugin_api_version(void) {
    return RAC_PLUGIN_API_VERSION;
}

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC

rac_result_t rac_registry_load_plugin(const char* path) {
    if (path == nullptr)
        return RAC_ERROR_NULL_POINTER;
    RAC_LOG_DEBUG(LOG_CAT,
                  "rac_registry_load_plugin('%s'): host built with "
                  "RAC_STATIC_PLUGINS=ON; dynamic loading is disabled. Use "
                  "RAC_STATIC_PLUGIN_REGISTER(<name>) instead.",
                  path);
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

#else /* RAC_PLUGIN_MODE_SHARED — real dlopen path */

rac_result_t rac_registry_load_plugin(const char* path) {
    if (path == nullptr)
        return RAC_ERROR_NULL_POINTER;

    DlGuard guard{rac_dl_open(path)};
    if (guard.h == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "rac_registry_load_plugin('%s'): dlopen failed (%s)", path,
                      rac_dl_error());
        return RAC_ERROR_PLUGIN_LOAD_FAILED;
    }

    const std::string sym = entry_symbol_from_path(path);
    void* entry_sym = rac_dl_sym(guard.h, sym.c_str());
    if (entry_sym == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "rac_registry_load_plugin('%s'): dlsym('%s') failed (%s)", path,
                      sym.c_str(), rac_dl_error());
        return RAC_ERROR_PLUGIN_LOAD_FAILED;
    }

    auto entry = reinterpret_cast<rac_plugin_entry_fn>(entry_sym);
    const rac_engine_vtable_t* vt = entry();
    if (vt == nullptr || vt->metadata.name == nullptr) {
        RAC_LOG_ERROR(LOG_CAT,
                      "rac_registry_load_plugin('%s'): entry '%s' returned NULL or unnamed vtable",
                      path, sym.c_str());
        return RAC_ERROR_PLUGIN_LOAD_FAILED;
    }

    /* Registry centralizes ABI + capability + dedup checks. The single log
     * line on ABI mismatch is emitted from there (see
     * rac_plugin_registry.cpp). We do NOT (void)-cast the result here. */
    rac_result_t rc = rac_plugin_register(vt);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "rac_registry_load_plugin('%s'): rac_plugin_register('%s') -> %d",
                      path, vt->metadata.name, static_cast<int>(rc));
        (void)rac_engine_manifest_detach_vtable(vt);
        return rc;
    }

    /* Replacement load: the registry accepts equal-priority duplicates by
     * overwriting the by-name entry. Any previously tracked OS handle must be
     * dlclosed here — `rac_plugin_registry_set_dl_handle` overwrites the
     * stored handle unconditionally and the registry itself has no ownership
     * of the OS library mapping (see plugin_registry_internal.h). Without
     * this we leak one shared-library mapping per same-name reload from a
     * different path, and on POSIX the extra refcount from a same-path
     * re-dlopen is never balanced. Taking before setting also avoids a race
     * window where a concurrent unload could see the new handle before we
     * drop the old one. Note `prior` may equal `guard.h` on POSIX when the
     * same path is reopened (dlopen returns the same handle and bumps the
     * refcount); the matching dlclose still has to happen so the OS refcount
     * returns to 1 after the redundant load. */
    if (void* prior = rac_plugin_registry_take_dl_handle(vt->metadata.name); prior != nullptr) {
        rac_dl_close(static_cast<rac_lib_handle_t>(prior));
    }

    /* Track the handle so unload can dlclose it exactly once. Ownership of the
     * dlopen mapping transfers from `guard` to the registry here — `release()`
     * suppresses the destructor's close so we don't double-free. */
    rac_plugin_registry_set_dl_handle(vt->metadata.name, guard.release());
    RAC_LOG_DEBUG(LOG_CAT, "rac_registry_load_plugin('%s'): registered '%s' from '%s'", path,
                  vt->metadata.name, sym.c_str());
    return RAC_SUCCESS;
}

#endif /* RAC_PLUGIN_MODE_STATIC */

rac_result_t rac_registry_unload_plugin(const char* name) {
    if (name == nullptr)
        return RAC_ERROR_NULL_POINTER;

#if !defined(RAC_PLUGIN_MODE_STATIC) || !RAC_PLUGIN_MODE_STATIC
    /* Take the handle BEFORE unregister so we don't lose track of it on the
     * race window where another thread re-registers the same name. */
    void* handle = rac_plugin_registry_take_dl_handle(name);
#endif

    rac_result_t rc = rac_plugin_unregister(name);

#if !defined(RAC_PLUGIN_MODE_STATIC) || !RAC_PLUGIN_MODE_STATIC
    if (handle != nullptr) {
        /* The plugin is now unregistered (removed from every primitive bucket
         * under the registry lock), so no caller can obtain its vtable. Close
         * the dynamic library to unmap the plugin's code and `.rodata`. */
        rac_dl_close(static_cast<rac_lib_handle_t>(handle));
    }
#endif

    return rc;
}

size_t rac_registry_plugin_count(void) {
    return rac_plugin_count();
}

rac_result_t rac_registry_list_plugins(const char*** out_names, size_t* out_count) {
    if (out_names == nullptr || out_count == nullptr)
        return RAC_ERROR_NULL_POINTER;
    *out_count = rac_plugin_registry_snapshot_names(out_names);
    return RAC_SUCCESS;
}

void rac_registry_free_plugin_list(const char** names, size_t count) {
    if (names == nullptr)
        return;
    for (size_t i = 0; i < count; ++i) {
        std::free(const_cast<char*>(names[i]));
    }
    std::free(static_cast<void*>(const_cast<char**>(names)));
}

}  // extern "C"
