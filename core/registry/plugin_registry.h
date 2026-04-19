// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// L2 plugin registry — dual-path: dlopen on Android/macOS/Linux, static on
// iOS/WASM. The interface is identical; the difference is whether plugins
// are discovered at runtime or registered at compile time.
//
// Registration happens exactly once per process. Plugins advertise
// capabilities (primitives + formats + runtimes) up front, which the L3
// router inspects to select an engine for a given request.

#ifndef RA_CORE_PLUGIN_REGISTRY_H
#define RA_CORE_PLUGIN_REGISTRY_H

#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

#include "../abi/ra_plugin.h"
#include "../abi/ra_primitives.h"

namespace ra::core {

struct PluginHandle {
    std::string                 name;
    std::string                 version;
    std::string                 path;        // Empty for static plugins.
    ra_engine_vtable_t          vtable{};
    void*                       dl_handle;   // nullptr for static plugins.
    bool                        is_static;
};

using PluginHandleRef = std::shared_ptr<const PluginHandle>;

class PluginRegistry {
public:
    static PluginRegistry& global();

    PluginRegistry(const PluginRegistry&)            = delete;
    PluginRegistry& operator=(const PluginRegistry&) = delete;

    // --- Static registration (iOS / WASM only) ---
    // Called automatically via RA_STATIC_PLUGIN_REGISTER. Thread-safe.
    void register_static(std::string_view name, ra_plugin_entry_fn entry);

    // --- Dynamic registration (Android / macOS / Linux) ---
    // Loads the plugin at `dylib_path`, resolves `ra_plugin_entry`, verifies
    // ABI version, calls capability_check() if present. Returns RA_OK on
    // success, an error code otherwise.
    ra_status_t load_plugin(std::string_view dylib_path);

    // Unloads a previously-loaded plugin by name. Any outstanding
    // PluginHandleRef keeps the handle memory alive until released, so
    // in-flight sessions can complete gracefully — but the caller must
    // still cancel and destroy sessions before the shared_ptr drops, since
    // unload closes the dlopen handle that backs the vtable.
    ra_status_t unload_plugin(std::string_view name);

    // --- Lookup ---
    // Returns a stable, ref-counted handle to the first plugin that
    // advertises the given primitive AND supports the given model format.
    // The returned shared_ptr survives even if the registry is mutated
    // concurrently; the caller is free to hold it for the lifetime of any
    // session it owns.
    PluginHandleRef find(ra_primitive_t primitive,
                          ra_model_format_t format) const;

    // Returns the plugin with the given name, or nullptr-equivalent.
    PluginHandleRef find_by_name(std::string_view name) const;

    // Enumerate every registered plugin. The callback receives a
    // ref-counted handle that stays valid for the duration of the call.
    // Safe to call from any thread.
    void enumerate(std::function<void(const PluginHandleRef&)> fn) const;

    std::size_t size() const;

private:
    PluginRegistry() = default;

    bool populate_from_entry(ra_plugin_entry_fn entry,
                             std::string_view   name_hint,
                             void*              dl_handle,
                             bool               is_static,
                             const std::string& path,
                             PluginHandle*      out);

    mutable std::mutex                                    mu_;
    std::vector<std::shared_ptr<PluginHandle>>           plugins_;
};

// Exported for the C ABI bridge — used by RA_STATIC_PLUGIN_REGISTER.
extern "C" void ra_registry_register_static(const char*        name,
                                             ra_plugin_entry_fn entry);

}  // namespace ra::core

#endif  // RA_CORE_PLUGIN_REGISTRY_H
