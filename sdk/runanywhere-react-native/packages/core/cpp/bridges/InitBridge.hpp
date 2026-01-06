/**
 * @file InitBridge.hpp
 * @brief SDK initialization bridge for React Native
 *
 * Handles rac_init() and rac_shutdown() lifecycle management.
 * Matches Swift's CppBridge initialization pattern.
 */

#pragma once

#include <string>

#ifdef HAS_RACOMMONS
#include "rac/core/rac_core.h"
#include "rac/core/rac_types.h"
#else
typedef int rac_result_t;
#define RAC_SUCCESS 0
#endif

namespace runanywhere {
namespace bridges {

/**
 * @brief SDK initialization bridge singleton
 *
 * Manages the lifecycle of the runanywhere-commons SDK.
 */
class InitBridge {
public:
    static InitBridge& shared();

    /**
     * @brief Initialize the SDK
     *
     * @param configJson Configuration JSON string
     * @return RAC_SUCCESS or error code
     */
    rac_result_t initialize(const std::string& configJson);

    /**
     * @brief Shutdown the SDK
     */
    void shutdown();

    /**
     * @brief Check if SDK is initialized
     */
    bool isInitialized() const { return initialized_; }

private:
    InitBridge() = default;
    ~InitBridge();

    // Disable copy/move
    InitBridge(const InitBridge&) = delete;
    InitBridge& operator=(const InitBridge&) = delete;

    bool initialized_ = false;
};

} // namespace bridges
} // namespace runanywhere
