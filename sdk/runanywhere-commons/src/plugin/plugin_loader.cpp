/**
 * @file plugin_loader.cpp
 * @brief Dynamic plugin loader implementation.
 *
 * GAP 03 — see v2_gap_specs/GAP_03_DYNAMIC_PLUGIN_LOADING.md.
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

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_loader.h"

#include "plugin_registry_internal.h"

#if !defined(RAC_PLUGIN_MODE_STATIC) || !RAC_PLUGIN_MODE_STATIC
  #if defined(_WIN32)
    #include <windows.h>
    using rac_lib_handle_t = HMODULE;
    static rac_lib_handle_t rac_dl_open(const char* p)         { return LoadLibraryA(p); }
    static void*            rac_dl_sym(rac_lib_handle_t h, const char* s) {
        return reinterpret_cast<void*>(GetProcAddress(h, s));
    }
    static void             rac_dl_close(rac_lib_handle_t h)   { FreeLibrary(h); }
    static const char*      rac_dl_error()                      { return "LoadLibrary failed"; }
  #else
    #include <dlfcn.h>
    using rac_lib_handle_t = void*;
    static rac_lib_handle_t rac_dl_open(const char* p)         { return dlopen(p, RTLD_NOW | RTLD_LOCAL); }
    static void*            rac_dl_sym(rac_lib_handle_t h, const char* s) { return dlsym(h, s); }
    static void             rac_dl_close(rac_lib_handle_t h)   { dlclose(h); }
    static const char*      rac_dl_error()                      { return dlerror(); }
  #endif
#endif

namespace {

constexpr const char* LOG_CAT = "PluginLoader";

/**
 * Derive the plugin entry-symbol name from a library path.
 *
 * Examples:
 *   "/lib/librunanywhere_llamacpp.so"  → "rac_plugin_entry_llamacpp"
 *   "../runanywhere_onnx.dylib"         → "rac_plugin_entry_onnx"
 *   "C:\plugins\runanywhere_metalrt.dll"→ "rac_plugin_entry_metalrt"
 *   "/foo/myplugin.so"                  → "rac_plugin_entry_myplugin"
 *
 * The "rac_plugin_entry_" prefix is fixed; everything between the last path
 * separator + optional "lib" prefix + optional "runanywhere_" prefix and the
 * file extension is the plugin name.
 */
std::string entry_symbol_from_path(const char* path) {
    if (path == nullptr) return {};
    std::string s(path);
    // Drop directory.
    auto last_sep = s.find_last_of("/\\");
    if (last_sep != std::string::npos) s.erase(0, last_sep + 1);
    // Drop "lib" prefix (POSIX shared-lib convention; harmless on Win32).
    if (s.rfind("lib", 0) == 0) s.erase(0, 3);
    // Drop file extension.
    auto dot = s.find('.');
    if (dot != std::string::npos) s.erase(dot);
    // Drop optional "runanywhere_" infix used by in-tree plugins.
    if (s.rfind("runanywhere_", 0) == 0) s.erase(0, std::strlen("runanywhere_"));
    return std::string("rac_plugin_entry_") + s;
}

}  // namespace

extern "C" {

uint32_t rac_plugin_api_version(void) {
    return RAC_PLUGIN_API_VERSION;
}

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC

rac_result_t rac_registry_load_plugin(const char* path) {
    if (path == nullptr) return RAC_ERROR_NULL_POINTER;
    RAC_LOG_DEBUG(LOG_CAT,
                  "rac_registry_load_plugin('%s'): host built with "
                  "RAC_STATIC_PLUGINS=ON; dynamic loading is disabled. Use "
                  "RAC_STATIC_PLUGIN_REGISTER(<name>) instead.",
                  path);
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

#else  /* RAC_PLUGIN_MODE_SHARED — real dlopen path */

rac_result_t rac_registry_load_plugin(const char* path) {
    if (path == nullptr) return RAC_ERROR_NULL_POINTER;

    rac_lib_handle_t handle = rac_dl_open(path);
    if (handle == nullptr) {
        RAC_LOG_ERROR(LOG_CAT,
                      "rac_registry_load_plugin('%s'): dlopen failed (%s)",
                      path,
                      rac_dl_error());
        return RAC_ERROR_PLUGIN_LOAD_FAILED;
    }

    const std::string sym = entry_symbol_from_path(path);
    void* entry_sym = rac_dl_sym(handle, sym.c_str());
    if (entry_sym == nullptr) {
        RAC_LOG_ERROR(LOG_CAT,
                      "rac_registry_load_plugin('%s'): dlsym('%s') failed (%s)",
                      path,
                      sym.c_str(),
                      rac_dl_error());
        rac_dl_close(handle);
        return RAC_ERROR_PLUGIN_LOAD_FAILED;
    }

    auto entry = reinterpret_cast<rac_plugin_entry_fn>(entry_sym);
    const rac_engine_vtable_t* vt = entry();
    if (vt == nullptr || vt->metadata.name == nullptr) {
        RAC_LOG_ERROR(LOG_CAT,
                      "rac_registry_load_plugin('%s'): entry '%s' returned NULL or unnamed vtable",
                      path,
                      sym.c_str());
        rac_dl_close(handle);
        return RAC_ERROR_PLUGIN_LOAD_FAILED;
    }

    /* Registry centralizes ABI + capability + dedup checks. The single log
     * line on ABI mismatch is emitted from there (see
     * rac_plugin_registry.cpp). We do NOT (void)-cast the result here. */
    rac_result_t rc = rac_plugin_register(vt);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT,
                      "rac_registry_load_plugin('%s'): rac_plugin_register('%s') -> %d",
                      path,
                      vt->metadata.name,
                      static_cast<int>(rc));
        rac_dl_close(handle);
        return rc;
    }

    /* Track the handle so unload can dlclose it exactly once. */
    rac_plugin_registry_set_dl_handle(vt->metadata.name, handle);
    RAC_LOG_DEBUG(LOG_CAT,
                  "rac_registry_load_plugin('%s'): registered '%s' from '%s'",
                  path,
                  vt->metadata.name,
                  sym.c_str());
    return RAC_SUCCESS;
}

#endif  /* RAC_PLUGIN_MODE_STATIC */

rac_result_t rac_registry_unload_plugin(const char* name) {
    if (name == nullptr) return RAC_ERROR_NULL_POINTER;

#if !defined(RAC_PLUGIN_MODE_STATIC) || !RAC_PLUGIN_MODE_STATIC
    /* Take the handle BEFORE unregister so we don't lose track of it on the
     * race window where another thread re-registers the same name. */
    void* handle = rac_plugin_registry_take_dl_handle(name);
#endif

    rac_result_t rc = rac_plugin_unregister(name);

#if !defined(RAC_PLUGIN_MODE_STATIC) || !RAC_PLUGIN_MODE_STATIC
    if (handle != nullptr) {
        rac_dl_close(static_cast<rac_lib_handle_t>(handle));
    }
#endif

    return rc;
}

size_t rac_registry_plugin_count(void) {
    return rac_plugin_count();
}

rac_result_t rac_registry_list_plugins(const char*** out_names, size_t* out_count) {
    if (out_names == nullptr || out_count == nullptr) return RAC_ERROR_NULL_POINTER;
    *out_count = rac_plugin_registry_snapshot_names(out_names);
    return RAC_SUCCESS;
}

void rac_registry_free_plugin_list(const char** names, size_t count) {
    if (names == nullptr) return;
    for (size_t i = 0; i < count; ++i) {
        std::free(const_cast<char*>(names[i]));
    }
    std::free(const_cast<char**>(names));
}

}  // extern "C"
