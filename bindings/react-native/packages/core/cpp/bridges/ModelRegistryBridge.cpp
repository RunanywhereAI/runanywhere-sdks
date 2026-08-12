/**
 * @file ModelRegistryBridge.cpp
 * @brief C++ bridge for model registry operations.
 *
 * Mirrors Swift's CppBridge+ModelRegistry.swift pattern.
 *
 * Bridge classification (see docs/CPP_PROTO_OWNERSHIP.md
 * "Bridge Layer Audit"):
 *   - `initialize()`, `shutdown()`, `getHandle()` stay as `internal`
 *     adapter glue — the proto wrappers in
 *     HybridRunAnywhereCore+Registry.cpp / +Lifecycle.cpp /
 *     +Storage.cpp call `ModelRegistryBridge::shared().getHandle()` to
 *     reach the global commons registry.
 *   - Model CRUD/query operations use the proto-byte APIs in
 *     HybridRunAnywhereCore+Registry.cpp.
 */

#include "ModelRegistryBridge.hpp"
#include "rac_core.h"  // For rac_get_model_registry()

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "ModelRegistryBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[ModelRegistryBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[ModelRegistryBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[ModelRegistryBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

ModelRegistryBridge& ModelRegistryBridge::shared() {
    static ModelRegistryBridge instance;
    return instance;
}

ModelRegistryBridge::~ModelRegistryBridge() {
    shutdown();
}

rac_result_t ModelRegistryBridge::initialize() {
    if (handle_) {
        LOGD("Model registry already initialized");
        return RAC_SUCCESS;
    }

    // Use the GLOBAL model registry (same as Swift SDK)
    // This ensures models registered by backends are visible to the SDK
    handle_ = rac_get_model_registry();

    if (handle_) {
        LOGI("Using global C++ model registry");
        return RAC_SUCCESS;
    } else {
        LOGE("Failed to get global model registry");
        return RAC_ERROR_NOT_INITIALIZED;
    }
}

void ModelRegistryBridge::shutdown() {
    // NOTE: We're using the GLOBAL registry - DO NOT clear the handle
    // The global registry persists for the lifetime of the app
    // Just log that shutdown was called, but don't actually release the handle
    LOGI("Model registry shutdown called (global registry handle retained)");
    // DO NOT: handle_ = nullptr;
}

} // namespace bridges
} // namespace runanywhere
