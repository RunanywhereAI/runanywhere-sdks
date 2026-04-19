// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Generic PluginLoader<VTABLE> — generalized from RCLI MetalRTLoader.
//
// Use this for any plugin that:
//   1. Exports named symbols to be resolved via dlsym, AND
//   2. Has an ABI version handshake, AND
//   3. Optionally pre-checks hardware capabilities before load.
//
// The engine plugin registry (plugin_registry.cpp) uses a specialization of
// this template to load ra_engine_vtable_t. Other dlopen use cases (e.g.
// loading a proprietary accelerator dylib) can instantiate their own vtable
// types.

#ifndef RA_CORE_PLUGIN_LOADER_H
#define RA_CORE_PLUGIN_LOADER_H

#if !defined(RA_STATIC_PLUGINS)
#  include <dlfcn.h>
#endif

#include <functional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace ra::core {

struct SymbolSpec {
    const char* name;
    void**      out_target;   // where to write the resolved pointer
    bool        required;
};

template <typename VTABLE>
class PluginLoader {
public:
    using CapabilityCheck = std::function<bool(const VTABLE&)>;

    PluginLoader() = default;
    ~PluginLoader() { unload(); }

    PluginLoader(const PluginLoader&)            = delete;
    PluginLoader& operator=(const PluginLoader&) = delete;
    PluginLoader(PluginLoader&&)                 = delete;
    PluginLoader& operator=(PluginLoader&&)      = delete;

#if defined(RA_STATIC_PLUGINS)
    // Static plugins: caller supplies the already-populated vtable.
    bool adopt(const VTABLE& vt) {
        vtable_ = vt;
        loaded_ = true;
        return true;
    }
#else
    // Dynamic plugins: resolve symbols from the given dylib path.
    bool load(std::string_view             path,
              const std::vector<SymbolSpec>& symbols,
              int                            expected_abi_version,
              CapabilityCheck                capability_check = nullptr) {
        unload();

        std::string sz(path);
        handle_ = ::dlopen(sz.c_str(), RTLD_NOW | RTLD_LOCAL);
        if (!handle_) {
            // dlerror() returns the last error and CLEARS it. A second call
            // returns nullptr — constructing std::string from nullptr is UB.
            // Capture once, check for null, then assign.
            const char* err = ::dlerror();
            last_error_ = err ? err : "dlopen failed";
            return false;
        }

        for (const auto& spec : symbols) {
            void* sym = ::dlsym(handle_, spec.name);
            if (!sym) {
                if (spec.required) {
                    last_error_ = std::string("dlsym(") + spec.name +
                                  ") failed: required symbol missing";
                    unload();
                    return false;
                }
                continue;
            }
            *spec.out_target = sym;
        }

        // Optional hardware gate.
        if (capability_check && !capability_check(vtable_)) {
            last_error_ = "capability_check rejected the plugin";
            unload();
            return false;
        }
        (void)expected_abi_version;

        loaded_ = true;
        return true;
    }

    void unload() {
        if (handle_) {
            ::dlclose(handle_);
            handle_ = nullptr;
        }
        loaded_ = false;
    }
#endif  // !RA_STATIC_PLUGINS

#if defined(RA_STATIC_PLUGINS)
    // Static-mode unload is a no-op — plugin lifetime follows the process.
    void unload() { loaded_ = false; }
#endif

    bool                loaded() const noexcept { return loaded_; }
    const VTABLE&       vtable() const noexcept { return vtable_; }
    VTABLE&             vtable()       noexcept { return vtable_; }
    const std::string&  last_error() const noexcept { return last_error_; }

private:
    VTABLE      vtable_{};
    bool        loaded_ = false;
    std::string last_error_;
#if !defined(RA_STATIC_PLUGINS)
    void*       handle_ = nullptr;
#endif
};

}  // namespace ra::core

#endif  // RA_CORE_PLUGIN_LOADER_H
