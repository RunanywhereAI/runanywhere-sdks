/**
 * @file PlatformAdapterBridge.cpp
 * @brief Platform adapter bridge implementation
 */

#include "PlatformAdapterBridge.hpp"
#include <chrono>
#include <cstring>

namespace runanywhere {
namespace bridges {

PlatformAdapterBridge& PlatformAdapterBridge::shared() {
    static PlatformAdapterBridge instance;
    return instance;
}

PlatformAdapterBridge::PlatformAdapterBridge() {
#ifdef HAS_RACOMMONS
    std::memset(&adapter_, 0, sizeof(adapter_));
#endif
}

PlatformAdapterBridge::~PlatformAdapterBridge() {
    shutdown();
}

void PlatformAdapterBridge::initialize(const PlatformCallbacks& callbacks) {
    if (initialized_) {
        return;
    }

    callbacks_ = callbacks;

#ifdef HAS_RACOMMONS
    // Setup platform adapter callbacks
    adapter_.file_exists = fileExistsCallback;
    adapter_.file_read = fileReadCallback;
    adapter_.file_write = fileWriteCallback;
    adapter_.file_delete = fileDeleteCallback;
    adapter_.log = logCallback;
    adapter_.now_ms = nowMsCallback;
    adapter_.user_data = this;

    // Optional callbacks (set to nullptr)
    adapter_.secure_get = nullptr;
    adapter_.secure_set = nullptr;
    adapter_.secure_delete = nullptr;
    adapter_.track_error = nullptr;
    adapter_.get_memory_info = nullptr;
    adapter_.http_download = nullptr;
    adapter_.http_download_cancel = nullptr;
    adapter_.extract_archive = nullptr;

    // Register with commons
    rac_set_platform_adapter(&adapter_);
#endif

    initialized_ = true;
}

void PlatformAdapterBridge::shutdown() {
    if (!initialized_) {
        return;
    }

    initialized_ = false;
    callbacks_ = {};
}

#ifdef HAS_RACOMMONS
const rac_platform_adapter_t* PlatformAdapterBridge::getAdapter() const {
    return initialized_ ? &adapter_ : nullptr;
}

rac_bool_t PlatformAdapterBridge::fileExistsCallback(const char* path, void* user_data) {
    auto* bridge = static_cast<PlatformAdapterBridge*>(user_data);
    if (!bridge || !bridge->callbacks_.fileExists) {
        return RAC_FALSE;
    }
    return bridge->callbacks_.fileExists(path) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t PlatformAdapterBridge::fileReadCallback(const char* path, void** out_data,
                                                      size_t* out_size, void* user_data) {
    auto* bridge = static_cast<PlatformAdapterBridge*>(user_data);
    if (!bridge || !bridge->callbacks_.fileRead || !out_data || !out_size) {
        return -1; // RAC_ERROR_INVALID_ARGUMENT
    }

    try {
        std::string content = bridge->callbacks_.fileRead(path);

        // Allocate memory for the content (caller must free)
        *out_size = content.size();
        *out_data = malloc(*out_size);
        if (!*out_data) {
            return -6; // RAC_ERROR_OUT_OF_MEMORY
        }
        std::memcpy(*out_data, content.data(), *out_size);

        return RAC_SUCCESS;
    } catch (...) {
        return -10; // RAC_ERROR_IO
    }
}

rac_result_t PlatformAdapterBridge::fileWriteCallback(const char* path, const void* data,
                                                       size_t size, void* user_data) {
    auto* bridge = static_cast<PlatformAdapterBridge*>(user_data);
    if (!bridge || !bridge->callbacks_.fileWrite) {
        return -1; // RAC_ERROR_INVALID_ARGUMENT
    }

    try {
        std::string content(static_cast<const char*>(data), size);
        bool success = bridge->callbacks_.fileWrite(path, content);
        return success ? RAC_SUCCESS : -10; // RAC_ERROR_IO
    } catch (...) {
        return -10; // RAC_ERROR_IO
    }
}

rac_result_t PlatformAdapterBridge::fileDeleteCallback(const char* path, void* user_data) {
    auto* bridge = static_cast<PlatformAdapterBridge*>(user_data);
    if (!bridge || !bridge->callbacks_.fileDelete) {
        return -1; // RAC_ERROR_INVALID_ARGUMENT
    }

    try {
        bool success = bridge->callbacks_.fileDelete(path);
        return success ? RAC_SUCCESS : -10; // RAC_ERROR_IO
    } catch (...) {
        return -10; // RAC_ERROR_IO
    }
}

void PlatformAdapterBridge::logCallback(rac_log_level_t level, const char* category,
                                        const char* message, void* user_data) {
    auto* bridge = static_cast<PlatformAdapterBridge*>(user_data);
    if (!bridge || !bridge->callbacks_.log) {
        return;
    }

    bridge->callbacks_.log(static_cast<int>(level),
                           category ? category : "",
                           message ? message : "");
}

int64_t PlatformAdapterBridge::nowMsCallback(void* user_data) {
    auto* bridge = static_cast<PlatformAdapterBridge*>(user_data);
    if (bridge && bridge->callbacks_.nowMs) {
        return bridge->callbacks_.nowMs();
    }

    // Fallback to system time
    auto now = std::chrono::system_clock::now();
    auto duration = now.time_since_epoch();
    return std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
}
#endif

} // namespace bridges
} // namespace runanywhere
