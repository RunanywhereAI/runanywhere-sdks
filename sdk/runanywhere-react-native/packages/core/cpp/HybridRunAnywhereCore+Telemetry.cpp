/**
 * HybridRunAnywhereCore+Telemetry.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Telemetry
// ============================================================================
// Telemetry
// Matches Swift: CppBridge+Telemetry.swift
// C++ handles all telemetry logic - batching, JSON building, routing
// ============================================================================

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::flushTelemetry() {
    return Promise<void>::async([]() -> void {
        LOGI("Flushing telemetry events...");
        TelemetryBridge::shared().flush();
        LOGI("Telemetry flushed");
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isTelemetryInitialized() {
    return Promise<bool>::async([]() -> bool {
        return TelemetryBridge::shared().isInitialized();
    });
}

} // namespace margelo::nitro::runanywhere
