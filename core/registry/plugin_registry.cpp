// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "plugin_registry.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

#if !defined(RA_STATIC_PLUGINS)
#  include <dlfcn.h>
#endif

namespace ra::core {

namespace {
// Only referenced inside load_plugin's dlsym path. Under RA_STATIC_PLUGINS
// plugins register themselves via RA_STATIC_PLUGIN_REGISTER and the
// symbol name is unused — guard accordingly so -Werror=unused passes.
#if !defined(RA_STATIC_PLUGINS)
constexpr const char* kEntrySymbol = "ra_plugin_entry";
#endif
}

PluginRegistry& PluginRegistry::global() {
    static PluginRegistry instance;
    return instance;
}

bool PluginRegistry::populate_from_entry(ra_plugin_entry_fn entry,
                                         std::string_view   name_hint,
                                         void*              dl_handle,
                                         bool               is_static,
                                         const std::string& path,
                                         PluginHandle*      out) {
    if (!entry || !out) return false;

    ra_engine_vtable_t vt{};
    ra_status_t rc = entry(&vt);
    if (rc != RA_OK) return false;

    // Verify plugin API version.
    if (vt.metadata.abi_version != RA_PLUGIN_API_VERSION) {
        std::fprintf(stderr,
            "[runanywhere] plugin '%.*s' ABI mismatch: got %u, want %u\n",
            static_cast<int>(name_hint.size()), name_hint.data(),
            vt.metadata.abi_version, RA_PLUGIN_API_VERSION);
        return false;
    }

    // Capability gate.
    if (vt.capability_check && !vt.capability_check()) {
        std::fprintf(stderr,
            "[runanywhere] plugin '%.*s' declined: capability_check returned false\n",
            static_cast<int>(name_hint.size()), name_hint.data());
        return false;
    }

    out->name      = vt.metadata.name ? vt.metadata.name : std::string(name_hint);
    out->version   = vt.metadata.version ? vt.metadata.version : "";
    out->path      = path;
    out->vtable    = vt;
    out->dl_handle = dl_handle;
    out->is_static = is_static;
    return true;
}

void PluginRegistry::register_static(std::string_view   name,
                                      ra_plugin_entry_fn entry) {
    auto h = std::make_shared<PluginHandle>();
    if (!populate_from_entry(entry, name, nullptr,
                             /*is_static=*/true,
                             /*path=*/"", h.get())) {
        return;
    }

    std::lock_guard<std::mutex> lk(mu_);
    // Reject duplicates silently — static registration is idempotent.
    for (const auto& existing : plugins_) {
        if (existing->name == h->name) return;
    }
    plugins_.push_back(std::move(h));
}

ra_status_t PluginRegistry::load_plugin(std::string_view dylib_path) {
#if defined(RA_STATIC_PLUGINS)
    (void)dylib_path;
    return RA_ERR_RUNTIME_UNAVAILABLE;
#else
    std::string sz(dylib_path);
    void* handle = ::dlopen(sz.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        const char* err = ::dlerror();
        std::fprintf(stderr, "[runanywhere] dlopen(%s) failed: %s\n",
                     sz.c_str(), err ? err : "unknown");
        return RA_ERR_IO;
    }

    auto entry = reinterpret_cast<ra_plugin_entry_fn>(
        ::dlsym(handle, kEntrySymbol));
    if (!entry) {
        std::fprintf(stderr, "[runanywhere] dlsym(%s) failed in %s\n",
                     kEntrySymbol, sz.c_str());
        ::dlclose(handle);
        return RA_ERR_IO;
    }

    auto h = std::make_shared<PluginHandle>();
    if (!populate_from_entry(entry, /*name_hint=*/sz, handle,
                             /*is_static=*/false, sz, h.get())) {
        ::dlclose(handle);
        return RA_ERR_ABI_MISMATCH;
    }

    std::lock_guard<std::mutex> lk(mu_);
    for (const auto& existing : plugins_) {
        if (existing->name == h->name) {
            ::dlclose(handle);
            return RA_OK;  // already loaded, treat as success
        }
    }
    plugins_.push_back(std::move(h));
    return RA_OK;
#endif
}

ra_status_t PluginRegistry::unload_plugin(std::string_view name) {
    std::shared_ptr<PluginHandle> handle_to_drop;
    {
        std::lock_guard<std::mutex> lk(mu_);
        auto it = std::find_if(plugins_.begin(), plugins_.end(),
            [&](const std::shared_ptr<PluginHandle>& p) {
                return p && p->name == name;
            });
        if (it == plugins_.end()) return RA_ERR_INVALID_ARGUMENT;
        handle_to_drop = *it;
        plugins_.erase(it);
    }

    // Call shutdown outside the lock — it may take non-trivial time and
    // we don't want to block other threads that are querying the registry.
    if (handle_to_drop && handle_to_drop->vtable.plugin_shutdown) {
        handle_to_drop->vtable.plugin_shutdown();
    }

#if !defined(RA_STATIC_PLUGINS)
    // Any outstanding PluginHandleRef keeps the shared_ptr (and therefore
    // this memory) alive, but we still close the dlopen handle so the OS
    // can reclaim the mapped image. Callers who hold a PluginHandleRef
    // MUST have destroyed all sessions before they called unload_plugin.
    if (handle_to_drop && !handle_to_drop->is_static &&
        handle_to_drop->dl_handle) {
        ::dlclose(handle_to_drop->dl_handle);
        handle_to_drop->dl_handle = nullptr;
    }
#endif
    return RA_OK;
}

PluginHandleRef PluginRegistry::find(ra_primitive_t    primitive,
                                       ra_model_format_t format) const {
    std::lock_guard<std::mutex> lk(mu_);
    for (const auto& p : plugins_) {
        if (!p) continue;
        bool serves_primitive = false;
        for (std::size_t i = 0; i < p->vtable.metadata.primitives_count; ++i) {
            if (p->vtable.metadata.primitives[i] == primitive) {
                serves_primitive = true;
                break;
            }
        }
        if (!serves_primitive) continue;

        bool serves_format = false;
        for (std::size_t i = 0; i < p->vtable.metadata.formats_count; ++i) {
            if (p->vtable.metadata.formats[i] == format) {
                serves_format = true;
                break;
            }
        }
        if (serves_format) return p;
    }
    return {};
}

PluginHandleRef PluginRegistry::find_by_name(std::string_view name) const {
    std::lock_guard<std::mutex> lk(mu_);
    for (const auto& p : plugins_) {
        if (p && p->name == name) return p;
    }
    return {};
}

void PluginRegistry::enumerate(
        std::function<void(const PluginHandleRef&)> fn) const {
    // Snapshot so the callback can invoke registry mutations without
    // deadlocking on our own mutex.
    std::vector<PluginHandleRef> snapshot;
    {
        std::lock_guard<std::mutex> lk(mu_);
        snapshot.reserve(plugins_.size());
        for (const auto& p : plugins_) {
            if (p) snapshot.push_back(p);
        }
    }
    for (const auto& p : snapshot) fn(p);
}

std::size_t PluginRegistry::size() const {
    std::lock_guard<std::mutex> lk(mu_);
    return plugins_.size();
}

extern "C" void ra_registry_register_static(const char*        name,
                                             ra_plugin_entry_fn entry) {
    PluginRegistry::global().register_static(
        name ? name : "unknown", entry);
}

}  // namespace ra::core
