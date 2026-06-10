/**
 * HybridRunAnywhereCore+PluginLoader.cpp
 *
 * React Native bridge for Swift-parity RunAnywhere.pluginLoader.
 * Commons owns plugin registry and dynamic loader semantics.
 */

#include "HybridRunAnywhereCore+Common.hpp"

#include "rac/plugin/rac_plugin_loader.h"

#include <cstdio>
#include <stdexcept>

namespace margelo::nitro::runanywhere {

namespace {

std::string jsonEscape(const std::string& value) {
    std::string out;
    out.reserve(value.size() + 8);
    for (char ch : value) {
        switch (ch) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (static_cast<unsigned char>(ch) < 0x20) {
                    char buf[7];
                    std::snprintf(
                        buf,
                        sizeof(buf),
                        "\\u%04x",
                        static_cast<unsigned int>(static_cast<unsigned char>(ch)));
                    out += buf;
                } else {
                    out += ch;
                }
        }
    }
    return out;
}

std::string namesJsonArray() {
    const char** names = nullptr;
    size_t count = 0;
    const auto rc = rac_registry_list_plugins(&names, &count);
    if (rc != RAC_SUCCESS) {
        throw std::runtime_error("pluginLoader.registeredNames failed");
    }
    std::string json = "[";
    for (size_t i = 0; i < count; ++i) {
        if (i > 0) json += ",";
        json += "\"";
        json += jsonEscape(names && names[i] ? names[i] : "");
        json += "\"";
    }
    json += "]";
    if (names) {
        rac_registry_free_plugin_list(names, count);
    }
    return json;
}

std::string loadedJsonArray() {
    const char** names = nullptr;
    size_t count = 0;
    const auto rc = rac_registry_list_plugins(&names, &count);
    if (rc != RAC_SUCCESS) {
        throw std::runtime_error("pluginLoader.listLoaded failed");
    }
    std::string json = "[";
    for (size_t i = 0; i < count; ++i) {
        if (i > 0) json += ",";
        const std::string name = names && names[i] ? names[i] : "";
        json += "{\"name\":\"";
        json += jsonEscape(name);
        json += "\",\"path\":\"\"}";
    }
    json += "]";
    if (names) {
        rac_registry_free_plugin_list(names, count);
    }
    return json;
}

std::string pluginNameFromPath(const std::string& path) {
    auto slash = path.find_last_of("/\\");
    std::string stem = slash == std::string::npos ? path : path.substr(slash + 1);
    auto dot = stem.find_last_of('.');
    if (dot != std::string::npos) {
        stem = stem.substr(0, dot);
    }
    if (stem.rfind("lib", 0) == 0) {
        stem = stem.substr(3);
    }
    return stem;
}

void throwIfPluginFailed(rac_result_t rc, const std::string& operation, const std::string& context) {
    if (rc == RAC_SUCCESS) return;
    throw std::runtime_error(operation + " failed (" + context + "): " + std::to_string(static_cast<int>(rc)));
}

} // namespace

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::pluginLoaderApiVersion() {
    return Promise<double>::async([]() -> double {
        return static_cast<double>(rac_plugin_api_version());
    });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::pluginLoaderRegisteredCount() {
    return Promise<double>::async([]() -> double {
        return static_cast<double>(rac_registry_plugin_count());
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::pluginLoaderRegisteredNames() {
    return Promise<std::string>::async([]() -> std::string {
        return namesJsonArray();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::pluginLoaderListLoaded() {
    return Promise<std::string>::async([]() -> std::string {
        return loadedJsonArray();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::pluginLoaderLoad(const std::string& path) {
    return Promise<std::string>::async([path]() -> std::string {
        throwIfPluginFailed(rac_registry_load_plugin(path.c_str()), "pluginLoader.load", path);
        const auto name = pluginNameFromPath(path);
        return "{\"name\":\"" + jsonEscape(name) + "\",\"path\":\"" + jsonEscape(path) + "\"}";
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::pluginLoaderUnload(const std::string& name) {
    return Promise<void>::async([name]() {
        throwIfPluginFailed(rac_registry_unload_plugin(name.c_str()), "pluginLoader.unload", name);
    });
}

} // namespace margelo::nitro::runanywhere
