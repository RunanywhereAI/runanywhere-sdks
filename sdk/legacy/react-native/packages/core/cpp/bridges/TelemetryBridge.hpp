/**
 * TelemetryBridge.hpp
 *
 * C++ telemetry bridge for React Native - aligned with Swift/Kotlin SDKs.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Telemetry.swift
 *
 * Architecture:
 * - C++ telemetry manager handles all event logic (batching, JSON building)
 * - Platform SDK (React Native) only provides HTTP transport
 * - Events from analytics callback are routed to telemetry manager
 */

#pragma once

#include <string>
#include <mutex>
#include "rac_telemetry_manager.h"
#include "rac_analytics_events.h"
#include "rac_environment.h"

namespace runanywhere {
namespace bridges {

/**
 * TelemetryBridge - Manages C++ telemetry manager lifecycle
 *
 * This matches Swift's CppBridge.Telemetry implementation:
 * - Creates/destroys telemetry manager
 * - Registers HTTP callback for sending events
 * - Routes analytics events to telemetry manager
 */
class TelemetryBridge {
public:
    /**
     * Singleton accessor
     */
    static TelemetryBridge& shared();

    /**
     * Initialize telemetry manager
     *
     * @param environment SDK environment (affects endpoints and encoding)
     * @param deviceId Persistent device UUID
     * @param deviceModel Device model string (e.g., "iPhone 16 Pro")
     * @param osVersion OS version string (e.g., "18.0")
     * @param sdkVersion SDK version string
     */
    void initialize(
        rac_environment_t environment,
        const std::string& deviceId,
        const std::string& deviceModel,
        const std::string& osVersion,
        const std::string& sdkVersion
    );

    /**
     * Shutdown telemetry manager
     * Flushes pending events and destroys manager
     */
    void shutdown();

    /**
     * Check if telemetry is initialized
     */
    bool isInitialized() const;

    /**
     * Track analytics event from C++ callback
     * Routes to rac_telemetry_manager_track_analytics
     */
    void trackAnalyticsEvent(
        rac_event_type_t eventType,
        const rac_analytics_event_data_t* data
    );

    /**
     * Flush pending telemetry events immediately
     */
    void flush();

    /**
     * Register analytics events callback
     * This routes analytics events to the telemetry manager
     */
    void registerEventsCallback();

    /**
     * Unregister analytics events callback
     */
    void unregisterEventsCallback();

    /**
     * Get telemetry manager handle (for advanced use)
     */
    rac_telemetry_manager_t* getHandle() const { return manager_; }

    /**
     * Get current environment
     */
    rac_environment_t getEnvironment() const { return environment_; }

private:
    TelemetryBridge() = default;
    ~TelemetryBridge();

    // Non-copyable
    TelemetryBridge(const TelemetryBridge&) = delete;
    TelemetryBridge& operator=(const TelemetryBridge&) = delete;

    // Telemetry manager handle
    rac_telemetry_manager_t* manager_ = nullptr;

    // Current environment
    rac_environment_t environment_ = RAC_ENV_PRODUCTION;

    // Thread safety
    mutable std::mutex mutex_;

    // Events callback registered flag
    bool eventsCallbackRegistered_ = false;
};

} // namespace bridges
} // namespace runanywhere

