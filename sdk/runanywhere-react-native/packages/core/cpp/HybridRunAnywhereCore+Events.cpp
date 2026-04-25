/**
 * HybridRunAnywhereCore+Events.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Events
// ============================================================================
// Events
// ============================================================================

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::emitEvent(
    const std::string& eventJson) {
    return Promise<void>::async([eventJson]() -> void {
        std::string type = extractStringValue(eventJson, "type");
        std::string categoryStr = extractStringValue(eventJson, "category", "sdk");

        EventCategory category = EventCategory::SDK;
        if (categoryStr == "model") category = EventCategory::Model;
        else if (categoryStr == "llm") category = EventCategory::LLM;
        else if (categoryStr == "stt") category = EventCategory::STT;
        else if (categoryStr == "tts") category = EventCategory::TTS;

        EventBridge::shared().trackEvent(type, category, EventDestination::All, eventJson);
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::pollEvents() {
    // Events are push-based via callback, not polling
    return Promise<std::string>::async([]() -> std::string {
        return "[]";
    });
}

} // namespace margelo::nitro::runanywhere
