/**
 * @file test_plugin_registry_isolation.cpp
 * @brief Verifies plugin-registry entries remain isolated by primitive.
 *
 * This test asserts that the registry:
 *   (a) Finds a plugin for its registered primitive.
 *   (b) Does not leak the plugin across unrelated primitives.
 *   (c) Removes the plugin cleanly when it is unregistered.
 */

#include <cstdio>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

int main() {
    std::fprintf(stdout, "test_plugin_registry_isolation\n");

    // Register a plugin that serves TRANSCRIBE (not GENERATE_TEXT).
    static const int k_fake_stt_ops = 1;
    rac_engine_vtable_t vt{};
    vt.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    vt.metadata.name = "coex-demo";
    vt.metadata.priority = 50;
    vt.stt_ops = reinterpret_cast<const struct rac_stt_service_ops*>(&k_fake_stt_ops);

    if (rac_plugin_register(&vt) != RAC_SUCCESS) {
        std::fprintf(stderr, "register failed\n");
        return 1;
    }

    // (a) plugin_find returns the vtable for TRANSCRIBE …
    if (rac_plugin_find(RAC_PRIMITIVE_TRANSCRIBE) != &vt) {
        std::fprintf(stderr, "find missed its own primitive\n");
        return 1;
    }
    // (b) … but not for unrelated primitives.
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != nullptr) {
        std::fprintf(stderr, "plugin registry leaked across primitives\n");
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_SYNTHESIZE) != nullptr) {
        std::fprintf(stderr, "plugin registry leaked to synthesize\n");
        return 1;
    }

    // The registry contains exactly the plugin registered above.
    if (rac_plugin_count() != 1) {
        std::fprintf(stderr, "plugin_count mismatch: %zu\n", rac_plugin_count());
        return 1;
    }

    // (c) Unregister removes the plugin completely.
    rac_plugin_unregister("coex-demo");

    if (rac_plugin_count() != 0) {
        std::fprintf(stderr, "plugin_count not zero after unregister\n");
        return 1;
    }

    std::fprintf(stdout, "  ok: plugin registry isolated per-primitive, no leak\n");
    return 0;
}
