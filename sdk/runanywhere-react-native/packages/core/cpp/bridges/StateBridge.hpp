/**
 * @file StateBridge.hpp
 * @brief SDK state bridge for React Native
 *
 * Matches Swift's CppBridge+State.swift pattern, providing:
 * - SDK initialization state
 * - Services readiness state
 */

#pragma once

#include <string>

#ifdef HAS_RACOMMONS
#include "rac/core/rac_sdk_state.h"
#else
typedef int rac_result_t;
#define RAC_SUCCESS 0
#endif

namespace runanywhere {
namespace bridges {

/**
 * @brief SDK state enumeration
 */
enum class SDKState {
    Uninitialized,
    Initializing,
    Initialized,
    ServicesReady,
    ShuttingDown,
    Error
};

/**
 * @brief SDK state bridge singleton
 *
 * Matches CppBridge+State.swift API.
 */
class StateBridge {
public:
    static StateBridge& shared();

    // State queries
    bool isSDKInitialized() const;
    bool areServicesReady() const;
    SDKState getState() const;

    // State transitions (internal use)
    void setState(SDKState state);

private:
    StateBridge() = default;
    ~StateBridge() = default;

    // Disable copy/move
    StateBridge(const StateBridge&) = delete;
    StateBridge& operator=(const StateBridge&) = delete;

    SDKState state_ = SDKState::Uninitialized;
};

} // namespace bridges
} // namespace runanywhere
