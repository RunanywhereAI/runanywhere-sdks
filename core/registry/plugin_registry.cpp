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
constexpr const char* kEntrySymbol = "ra_plugin_entry";
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
    PluginHandle h{};
    if (!populate_from_entry(entry, name, nullptr,
                             /*is_static=*/true,
                             /*path=*/"", &h)) {
        return;
    }

    std::lock_guard<std::mutex> lk(mu_);
    // Reject duplicates silently — static registration is idempotent.
    for (const auto& existing : plugins_) {
        if (existing.name == h.name) return;
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
        std::fprintf(stderr, "[runanywhere] dlopen(%s) failed: %s\n",
                     sz.c_str(), ::dlerror());
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

    PluginHandle h{};
    if (!populate_from_entry(entry, /*name_hint=*/sz, handle,
                             /*is_static=*/false, sz, &h)) {
        ::dlclose(handle);
        return RA_ERR_ABI_MISMATCH;
    }

    std::lock_guard<std::mutex> lk(mu_);
    for (const auto& existing : plugins_) {
        if (existing.name == h.name) {
            ::dlclose(handle);
            return RA_OK;  // already loaded, treat as success
        }
    }
    plugins_.push_back(std::move(h));
    return RA_OK;
#endif
}

ra_status_t PluginRegistry::unload_plugin(std::string_view name) {
    std::lock_guard<std::mutex> lk(mu_);
    auto it = std::find_if(plugins_.begin(), plugins_.end(),
        [&](const PluginHandle& p) { return p.name == name; });
    if (it == plugins_.end()) return RA_ERR_INVALID_ARGUMENT;

    if (it->vtable.plugin_shutdown) {
        it->vtable.plugin_shutdown();
    }
#if !defined(RA_STATIC_PLUGINS)
    if (!it->is_static && it->dl_handle) {
        ::dlclose(it->dl_handle);
    }
#endif
    plugins_.erase(it);
    return RA_OK;
}

const PluginHandle* PluginRegistry::find(ra_primitive_t    primitive,
                                          ra_model_format_t format) const {
    std::lock_guard<std::mutex> lk(mu_);
    for (const auto& p : plugins_) {
        bool serves_primitive = false;
        for (std::size_t i = 0; i < p.vtable.metadata.primitives_count; ++i) {
            if (p.vtable.metadata.primitives[i] == primitive) {
                serves_primitive = true;
                break;
            }
        }
        if (!serves_primitive) continue;

        bool serves_format = false;
        for (std::size_t i = 0; i < p.vtable.metadata.formats_count; ++i) {
            if (p.vtable.metadata.formats[i] == format) {
                serves_format = true;
                break;
            }
        }
        if (serves_format) return &p;
    }
    return nullptr;
}

const PluginHandle* PluginRegistry::find_by_name(std::string_view name) const {
    std::lock_guard<std::mutex> lk(mu_);
    for (const auto& p : plugins_) {
        if (p.name == name) return &p;
    }
    return nullptr;
}

void PluginRegistry::enumerate(
        std::function<void(const PluginHandle&)> fn) const {
    std::lock_guard<std::mutex> lk(mu_);
    for (const auto& p : plugins_) fn(p);
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
