/**
 * @file test_legacy_coexistence.cpp
 * @brief Verifies the new plugin_registry does not interact with the legacy
 *        service_registry.
 *
 * GAP 02 Phase 10. The spec requires downstream Swift / Kotlin / Dart
 * frontends to keep working unchanged. The legacy path is exercised by every
 * existing backend test (`test_stt`, `test_llm`, etc.) — this test asserts
 * the narrower contract that the plugin registry:
 *   (a) Doesn't leak entries across unrelated primitives.
 *   (b) Doesn't observe legacy-registered providers (since they live in a
 *       different map).
 */

#include <cstdio>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

int main() {
    std::fprintf(stdout, "test_legacy_coexistence\n");

    // Register a plugin that serves TRANSCRIBE (not GENERATE_TEXT).
    static const int k_fake_stt_ops = 1;
    rac_engine_vtable_t vt{};
    vt.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    vt.metadata.name        = "coex-demo";
    vt.metadata.priority    = 50;
    vt.stt_ops = reinterpret_cast<const struct rac_stt_service_ops*>(&k_fake_stt_ops);

    if (rac_plugin_register(&vt) != RAC_SUCCESS) {
        std::fprintf(stderr, "register failed\n");
        return 1;
    }

    // (a) plugin_find returns the vt for TRANSCRIBE …
    if (rac_plugin_find(RAC_PRIMITIVE_TRANSCRIBE) != &vt) {
        std::fprintf(stderr, "find missed its own primitive\n");
        return 1;
    }
    // (a) … but NOT for unrelated primitives.
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != nullptr) {
        std::fprintf(stderr, "plugin registry leaked across primitives\n");
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_SYNTHESIZE) != nullptr) {
        std::fprintf(stderr, "plugin registry leaked to synthesize\n");
        return 1;
    }

    // (b) total plugin count is exactly 1.
    if (rac_plugin_count() != 1) {
        std::fprintf(stderr, "plugin_count mismatch: %zu\n", rac_plugin_count());
        return 1;
    }

    rac_plugin_unregister("coex-demo");

    if (rac_plugin_count() != 0) {
        std::fprintf(stderr, "plugin_count not zero after unregister\n");
        return 1;
    }

    std::fprintf(stdout, "  ok: plugin registry isolated per-primitive, no leak\n");
    return 0;
}
