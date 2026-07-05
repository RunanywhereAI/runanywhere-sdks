/**
 * @file rac_plugin_entry_genie.cpp
 * @brief Unified-ABI entry point for the Qualcomm Genie (NPU) backend.
 *
 * Shell plugin: the entry point remains inspectable,
 * but registration is rejected and no LLM/routing metadata is advertised
 * until real Genie LLM ops are wired. SDK discovery alone is not enough:
 * genie is OFF by default and never routable in-tree
 * (`RAC_GENIE_LLM_OPS_AVAILABLE=0`), so every routable seam stays absent.
 *
 * The ABI surface intentionally stays identical in both modes so that
 * downstream SDKs (runanywhere_genie Flutter plugin, Kotlin Genie
 * module) can load the shell without platform-specific branches while the
 * router only sees Genie when the Qualcomm SDK-backed ops are real.
 *
 * The not-routable manifest + all-NULL vtable + entry are emitted by the
 * shared `RAC_ENGINE_UNAVAILABLE_PLUGIN` shell (engines/common/), which genie
 * is the first consumer of; only `genie_capability_check()` (its SDK/Android
 * 3-way gate) is engine-specific. When real Genie LLM ops are wired
 * (`RAC_GENIE_LLM_OPS_AVAILABLE=1`), replace the shared shell with a
 * hand-written routable manifest/vtable exposing `RAC_PRIMITIVE_GENERATE_TEXT`.
 */

#include "genie_backend.h"
#include "common/rac_engine_unavailable.h"

#include "rac/plugin/rac_plugin_entry.h"

namespace {

// capability_check runs during rac_plugin_register. Reject the shell so the
// router never sees Genie as an eligible LLM backend in public/default builds.
// Non-Android hosts are rejected (CAPABILITY_UNSUPPORTED) because the runtime
// targets Snapdragon Android; Android hosts without SDK-backed ops are rejected
// (BACKEND_UNAVAILABLE). The 3-way decision is delegated to the shared helper.
//
// SDK-discovery seam: RAC_GENIE_SDK_AVAILABLE only governs whether the shell
// compiles against Qualcomm headers — it never makes Genie routable on its own.
// `backend_present` additionally requires RAC_GENIE_LLM_OPS_AVAILABLE (real
// SDK-backed ops), which is a local build fact pinned to 0 in CMakeLists.txt.
rac_result_t genie_capability_check(void) {
    return rac_engine_unavailable_capability(
#if defined(__ANDROID__)
        1, /* platform_supported: runtime targets Snapdragon Android */
#else
        0,
#endif
#if defined(RAC_GENIE_SDK_AVAILABLE) && RAC_GENIE_SDK_AVAILABLE && \
    defined(RAC_GENIE_LLM_OPS_AVAILABLE) && RAC_GENIE_LLM_OPS_AVAILABLE
        1 /* backend_present: SDK-backed LLM ops are wired */
#else
        0
#endif
    );
}

}  // namespace

extern "C" {

RAC_ENGINE_UNAVAILABLE_PLUGIN(genie, "Qualcomm Genie (NPU)", genie_capability_check)

}  // extern "C"
