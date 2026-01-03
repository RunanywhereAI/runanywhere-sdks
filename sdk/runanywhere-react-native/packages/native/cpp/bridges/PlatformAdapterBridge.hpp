/**
 * @file PlatformAdapterBridge.hpp
 * @brief Platform adapter bridge for React Native
 *
 * Provides platform-specific callbacks (file I/O, logging, time) required
 * by the runanywhere-commons library. Must be initialized before rac_init().
 */

#pragma once

#include <functional>
#include <memory>
#include <string>

// Forward declarations - actual headers come from RACommons.xcframework
#ifdef HAS_RACOMMONS
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_types.h"
#else
// Stub types when RACommons is not available
typedef int rac_result_t;
typedef int rac_bool_t;
typedef int rac_log_level_t;
typedef void* rac_handle_t;
#define RAC_SUCCESS 0
#define RAC_TRUE 1
#define RAC_FALSE 0
#endif

namespace runanywhere {
namespace bridges {

/**
 * @brief Callbacks for platform operations provided by JavaScript/React Native
 */
struct PlatformCallbacks {
    std::function<bool(const std::string&)> fileExists;
    std::function<std::string(const std::string&)> fileRead;
    std::function<bool(const std::string&, const std::string&)> fileWrite;
    std::function<bool(const std::string&)> fileDelete;
    std::function<void(int, const std::string&, const std::string&)> log;
    std::function<int64_t()> nowMs;
};

/**
 * @brief Platform adapter bridge singleton
 *
 * Provides the rac_platform_adapter_t required by runanywhere-commons.
 * Must be initialized before any rac_* calls.
 */
class PlatformAdapterBridge {
public:
    static PlatformAdapterBridge& shared();

    /**
     * @brief Initialize the platform adapter with callbacks
     *
     * @param callbacks Platform-specific callback functions
     */
    void initialize(const PlatformCallbacks& callbacks);

    /**
     * @brief Shutdown and cleanup
     */
    void shutdown();

    /**
     * @brief Check if initialized
     */
    bool isInitialized() const { return initialized_; }

#ifdef HAS_RACOMMONS
    /**
     * @brief Get the platform adapter pointer for rac_set_platform_adapter
     */
    const rac_platform_adapter_t* getAdapter() const;
#endif

private:
    PlatformAdapterBridge();
    ~PlatformAdapterBridge();

    // Disable copy/move
    PlatformAdapterBridge(const PlatformAdapterBridge&) = delete;
    PlatformAdapterBridge& operator=(const PlatformAdapterBridge&) = delete;

#ifdef HAS_RACOMMONS
    rac_platform_adapter_t adapter_;
#endif
    PlatformCallbacks callbacks_;
    bool initialized_ = false;

    // Static callback implementations for rac_platform_adapter_t
#ifdef HAS_RACOMMONS
    static rac_bool_t fileExistsCallback(const char* path, void* user_data);
    static rac_result_t fileReadCallback(const char* path, void** out_data,
                                         size_t* out_size, void* user_data);
    static rac_result_t fileWriteCallback(const char* path, const void* data,
                                          size_t size, void* user_data);
    static rac_result_t fileDeleteCallback(const char* path, void* user_data);
    static void logCallback(rac_log_level_t level, const char* category,
                           const char* message, void* user_data);
    static int64_t nowMsCallback(void* user_data);
#endif
};

} // namespace bridges
} // namespace runanywhere
