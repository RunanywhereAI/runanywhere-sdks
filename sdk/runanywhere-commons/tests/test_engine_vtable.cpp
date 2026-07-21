/**
 * @file test_engine_vtable.cpp
 * @brief Unit tests for the unified engine plugin registry.
 *
 * Nine scenarios required by the spec:
 *   1. Happy-path register → find → unregister.
 *   2. ABI version mismatch → RAC_ERROR_ABI_VERSION_MISMATCH.
 *   3. capability_check()≠0 → RAC_ERROR_CAPABILITY_UNSUPPORTED, plugin not in registry.
 *   4. NULL op-struct → rac_engine_vtable_slot() returns NULL for that primitive.
 *   5. Unregister by name.
 *   6. Duplicate name rejection (lower priority).
 *   7. Duplicate name promotion (higher priority replaces existing).
 *   8. Priority ordering (higher → rac_plugin_find returns it first).
 *   9. Static registration via RAC_STATIC_PLUGIN_REGISTER (smoke-check).
 */

#include <cassert>
#include <cstddef>
#include <cstdio>
#include <cstring>

#include "../src/generated/proto/model_types.pb.h"
#include "rac/core/rac_error.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

// ABI v8 promotes the vocoder pointer from the existing reserve without changing the
// 17-pointer primitive/reserve tail or the total vtable size.
static_assert((sizeof(rac_engine_vtable_t) - offsetof(rac_engine_vtable_t, llm_ops)) /
                  sizeof(void*) ==
              17);
static_assert(offsetof(rac_engine_vtable_t, diarization_ops) ==
              offsetof(rac_engine_vtable_t, diffusion_ops) + sizeof(void*));
static_assert(offsetof(rac_engine_vtable_t, segmentation_ops) ==
              offsetof(rac_engine_vtable_t, diarization_ops) + sizeof(void*));
static_assert(offsetof(rac_engine_vtable_t, vocoder_ops) ==
              offsetof(rac_engine_vtable_t, segmentation_ops) + sizeof(void*));
static_assert(offsetof(rac_engine_vtable_t, reserved_slot_3) ==
              offsetof(rac_engine_vtable_t, vocoder_ops) + sizeof(void*));

static_assert(RAC_MODEL_FORMAT_ID_UNSPECIFIED ==
              static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_UNSPECIFIED));
static_assert(RAC_MODEL_FORMAT_ID_GGUF ==
              static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_GGUF));
static_assert(RAC_MODEL_FORMAT_ID_GGML ==
              static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_GGML));
static_assert(RAC_MODEL_FORMAT_ID_ONNX ==
              static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_ONNX));
static_assert(RAC_MODEL_FORMAT_ID_ORT == static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_ORT));
static_assert(RAC_MODEL_FORMAT_ID_BIN == static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_BIN));
static_assert(RAC_MODEL_FORMAT_ID_COREML ==
              static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_COREML));
static_assert(RAC_MODEL_FORMAT_ID_MLMODEL ==
              static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_MLMODEL));
static_assert(RAC_MODEL_FORMAT_ID_MLPACKAGE ==
              static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_MLPACKAGE));
static_assert(RAC_MODEL_FORMAT_ID_TFLITE ==
              static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_TFLITE));
static_assert(RAC_MODEL_FORMAT_ID_SAFETENSORS ==
              static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_SAFETENSORS));
static_assert(RAC_MODEL_FORMAT_ID_QNN_CONTEXT ==
              static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_QNN_CONTEXT));
static_assert(RAC_MODEL_FORMAT_ID_ZIP == static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_ZIP));
static_assert(RAC_MODEL_FORMAT_ID_FOLDER ==
              static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_FOLDER));
static_assert(RAC_MODEL_FORMAT_ID_PROPRIETARY ==
              static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_PROPRIETARY));
static_assert(RAC_MODEL_FORMAT_ID_UNKNOWN ==
              static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_UNKNOWN));

static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_UNSPECIFIED) ==
              RAC_MODEL_FORMAT_ID_UNSPECIFIED);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_GGUF) == RAC_MODEL_FORMAT_ID_GGUF);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_GGML) == RAC_MODEL_FORMAT_ID_GGML);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_ONNX) == RAC_MODEL_FORMAT_ID_ONNX);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_ORT) == RAC_MODEL_FORMAT_ID_ORT);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_BIN) == RAC_MODEL_FORMAT_ID_BIN);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_COREML) == RAC_MODEL_FORMAT_ID_COREML);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_MLMODEL) == RAC_MODEL_FORMAT_ID_MLMODEL);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_MLPACKAGE) == RAC_MODEL_FORMAT_ID_MLPACKAGE);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_TFLITE) == RAC_MODEL_FORMAT_ID_TFLITE);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_SAFETENSORS) ==
              RAC_MODEL_FORMAT_ID_SAFETENSORS);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_QNN_CONTEXT) ==
              RAC_MODEL_FORMAT_ID_QNN_CONTEXT);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_ZIP) == RAC_MODEL_FORMAT_ID_ZIP);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_FOLDER) == RAC_MODEL_FORMAT_ID_FOLDER);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_PROPRIETARY) ==
              RAC_MODEL_FORMAT_ID_PROPRIETARY);
static_assert(static_cast<uint32_t>(RAC_MODEL_FORMAT_UNKNOWN) == RAC_MODEL_FORMAT_ID_UNKNOWN);

namespace {

int g_capability_check_rc = RAC_SUCCESS;

rac_result_t fake_capability_check() {
    return g_capability_check_rc;
}

// A "pretend" LLM ops sentinel — never deref'd, only compared by address.
// We cast through uintptr_t to avoid an incompatible-pointer-types error
// when the real rac_llm_service_ops is forward-declared as an incomplete
// struct from rac_engine_vtable.h.
static const int k_fake_llm_ops_sentinel = 0xABCD;
const void* k_fake_llm_ops = static_cast<const void*>(&k_fake_llm_ops_sentinel);

const rac_primitive_t k_manifest_primitives[] = {
    RAC_PRIMITIVE_GENERATE_TEXT,
};
const rac_primitive_t k_bad_manifest_primitives[] = {
    RAC_PRIMITIVE_EMBED,
};
const rac_runtime_id_t k_manifest_runtimes[] = {
    RAC_RUNTIME_CPU,
};
const uint32_t k_manifest_formats[] = {
    RAC_MODEL_FORMAT_ID_GGUF,
};

const rac_engine_manifest_t k_manifest = {
    .name = "manifested",
    .display_name = "Manifested Engine",
    .version = "1.2.3",
    .package_owner = "runanywhere-tests",
    .package_name = "test_engine_manifest",
    .availability = RAC_ENGINE_AVAILABILITY_PUBLIC,
    .priority = 77,
    .capability_flags = 4,
    .primitives = k_manifest_primitives,
    .primitives_count = sizeof(k_manifest_primitives) / sizeof(k_manifest_primitives[0]),
    .runtimes = k_manifest_runtimes,
    .runtimes_count = sizeof(k_manifest_runtimes) / sizeof(k_manifest_runtimes[0]),
    .formats = k_manifest_formats,
    .formats_count = sizeof(k_manifest_formats) / sizeof(k_manifest_formats[0]),
    .reserved_0 = 0,
    .reserved_1 = 0,
};

const rac_engine_manifest_t k_bad_manifest = {
    .name = "manifested",
    .display_name = "Manifested Engine",
    .version = "1.2.3",
    .package_owner = "runanywhere-tests",
    .package_name = "test_engine_manifest",
    .availability = RAC_ENGINE_AVAILABILITY_PUBLIC,
    .priority = 77,
    .capability_flags = 4,
    .primitives = k_bad_manifest_primitives,
    .primitives_count = sizeof(k_bad_manifest_primitives) / sizeof(k_bad_manifest_primitives[0]),
    .runtimes = k_manifest_runtimes,
    .runtimes_count = sizeof(k_manifest_runtimes) / sizeof(k_manifest_runtimes[0]),
    .formats = k_manifest_formats,
    .formats_count = sizeof(k_manifest_formats) / sizeof(k_manifest_formats[0]),
    .reserved_0 = 0,
    .reserved_1 = 0,
};

const rac_engine_vtable_t k_manifest_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_manifest),
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,
    /* llm_ops          */
    reinterpret_cast<const struct rac_llm_service_ops*>(&k_fake_llm_ops_sentinel),
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,
    /* diarization_ops  */ nullptr,
    /* segmentation_ops */ nullptr,
    /* vocoder_ops      */ nullptr,
    /* reserved_slot_3..9 */
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
};

rac_engine_vtable_t make_vt(const char* name, int32_t priority,
                            uint32_t abi_version = RAC_PLUGIN_API_VERSION,
                            rac_result_t (*cap)() = nullptr, const void* llm_ops = k_fake_llm_ops) {
    rac_engine_vtable_t v{};
    v.metadata.abi_version = abi_version;
    v.metadata.name = name;
    v.metadata.display_name = name;
    v.metadata.engine_version = "0.0.0";
    v.metadata.priority = priority;
    v.metadata.capability_flags = 0;
    v.capability_check = cap;
    v.on_unload = nullptr;
    v.llm_ops = static_cast<const struct rac_llm_service_ops*>(llm_ops);
    return v;
}

int test_count = 0;
int test_failed = 0;

#define CHECK(cond, label)                                                                       \
    do {                                                                                         \
        ++test_count;                                                                            \
        if (cond) {                                                                              \
            std::fprintf(stdout, "  ok:   %s\n", label);                                         \
        } else {                                                                                 \
            ++test_failed;                                                                       \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) — %s\n", label, __FILE__, __LINE__, #cond); \
        }                                                                                        \
    } while (0)

}  // namespace

int main() {
    std::fprintf(stdout, "test_engine_vtable\n");

    // (1) happy path
    {
        auto vt = make_vt("happy", 50);
        rac_result_t rc = rac_plugin_register(&vt);
        CHECK(rc == RAC_SUCCESS, "happy: register ok");
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == &vt, "happy: find returns vt");
        CHECK(rac_plugin_unregister("happy") == RAC_SUCCESS, "happy: unregister ok");
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == nullptr, "happy: post-unreg empty");
    }

    // (2) ABI mismatch
    {
        auto vt = make_vt("abi-v7", 50, 7u);
        rac_result_t rc = rac_plugin_register(&vt);
        CHECK(rc == RAC_ERROR_ABI_VERSION_MISMATCH, "abi: v7 plugin rejected by v8 host");
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == nullptr, "abi: not inserted");
    }

    // (3) capability_check rejection
    {
        g_capability_check_rc = RAC_ERROR_CAPABILITY_UNSUPPORTED;
        auto vt = make_vt("cap-no", 50, RAC_PLUGIN_API_VERSION, fake_capability_check);
        rac_result_t rc = rac_plugin_register(&vt);
        CHECK(rc == RAC_ERROR_CAPABILITY_UNSUPPORTED, "cap: rejected silently");
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == nullptr, "cap: not inserted");
        g_capability_check_rc = RAC_SUCCESS;
    }

    // (4) NULL op slot → rac_engine_vtable_slot returns NULL
    {
        auto vt = make_vt("null-slot", 50, RAC_PLUGIN_API_VERSION, nullptr, nullptr);
        rac_result_t rc = rac_plugin_register(&vt);
        CHECK(rc == RAC_SUCCESS, "null-slot: register ok (no served primitives)");
        CHECK(rac_engine_vtable_slot(&vt, RAC_PRIMITIVE_GENERATE_TEXT) == nullptr,
              "null-slot: slot NULL");
        rac_plugin_unregister("null-slot");
    }

    // (5) unregister nonexistent
    {
        const int diarization_sentinel = 9;
        const int segmentation_sentinel = 10;
        const int vocoder_sentinel = 11;
        rac_engine_vtable_t vt{};
        vt.diarization_ops =
            reinterpret_cast<const struct rac_diarization_service_ops*>(&diarization_sentinel);
        vt.segmentation_ops =
            reinterpret_cast<const struct rac_segmentation_service_ops*>(&segmentation_sentinel);
        vt.vocoder_ops = reinterpret_cast<const struct rac_vocoder_service_ops*>(&vocoder_sentinel);
        CHECK(rac_engine_vtable_slot(&vt, RAC_PRIMITIVE_DIARIZE) == &diarization_sentinel,
              "v8: DIARIZE resolves diarization_ops");
        CHECK(rac_engine_vtable_slot(&vt, RAC_PRIMITIVE_SEGMENT) == &segmentation_sentinel,
              "v8: SEGMENT resolves segmentation_ops");
        CHECK(rac_engine_vtable_slot(&vt, RAC_PRIMITIVE_VOCODE) == &vocoder_sentinel,
              "v8: VOCODE resolves vocoder_ops");
        CHECK(std::strcmp(rac_primitive_name(RAC_PRIMITIVE_DIARIZE), "diarize") == 0,
              "v8: DIARIZE name is stable");
        CHECK(std::strcmp(rac_primitive_name(RAC_PRIMITIVE_SEGMENT), "segment") == 0,
              "v8: SEGMENT name is stable");
        CHECK(std::strcmp(rac_primitive_name(RAC_PRIMITIVE_VOCODE), "vocode") == 0,
              "v8: VOCODE name is stable");
    }

    // (6) unregister nonexistent
    {
        rac_result_t rc = rac_plugin_unregister("does-not-exist");
        CHECK(rc == RAC_ERROR_NOT_FOUND, "unreg-missing: returns NOT_FOUND");
    }

    // (7) duplicate-name: lower priority rejected
    {
        auto hi = make_vt("dup", 100);
        rac_plugin_register(&hi);
        auto lo = make_vt("dup", 10);
        rac_result_t rc = rac_plugin_register(&lo);
        CHECK(rc == RAC_ERROR_PLUGIN_DUPLICATE, "dup: low priority rejected");
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == &hi, "dup: hi still primary");
        rac_plugin_unregister("dup");
    }

    // (8) duplicate-name: equal-or-higher priority promotes
    {
        auto lo = make_vt("prom", 10);
        rac_plugin_register(&lo);
        auto hi = make_vt("prom", 100);
        rac_result_t rc = rac_plugin_register(&hi);
        CHECK(rc == RAC_SUCCESS, "prom: hi priority accepted");
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == &hi, "prom: hi replaces lo");
        rac_plugin_unregister("prom");
    }

    // (9) priority order — higher wins across distinct names
    {
        auto a = make_vt("a", 10);
        auto b = make_vt("b", 100);
        auto c = make_vt("c", 50);
        rac_plugin_register(&a);
        rac_plugin_register(&b);
        rac_plugin_register(&c);
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == &b, "priority: highest wins");

        const rac_engine_vtable_t* arr[4] = {};
        size_t n = 0;
        rac_plugin_list(RAC_PRIMITIVE_GENERATE_TEXT, arr, 4, &n);
        CHECK(n == 3, "priority: list returns 3");
        CHECK(arr[0] == &b, "priority: sorted desc (highest)");
        CHECK(arr[1] == &c, "priority: sorted desc (middle)");
        CHECK(arr[2] == &a, "priority: sorted desc (lowest)");
        rac_plugin_unregister("a");
        rac_plugin_unregister("b");
        rac_plugin_unregister("c");
    }

    // (10) declarative manifest attaches to the vtable and is published only
    //     after plugin registration accepts the vtable.
    {
        CHECK(rac_engine_availability_name(RAC_ENGINE_AVAILABILITY_PUBLIC) != nullptr,
              "manifest: availability has stable name");
        CHECK(rac_engine_manifest_validate_vtable(&k_manifest, &k_manifest_vtable) == RAC_SUCCESS,
              "manifest: valid manifest matches vtable");
        CHECK(rac_engine_manifest_validate_vtable(&k_bad_manifest, &k_manifest_vtable) ==
                  RAC_ERROR_INVALID_PARAMETER,
              "manifest: primitive mismatch rejected");
        CHECK(rac_engine_manifest_find("manifested") == nullptr,
              "manifest: not visible before attach/register");
        CHECK(rac_engine_manifest_attach_vtable(&k_manifest, &k_manifest_vtable) == RAC_SUCCESS,
              "manifest: attach ok");
        CHECK(rac_engine_manifest_count() == 0,
              "manifest: attach does not publish before register");
        CHECK(rac_plugin_register(&k_manifest_vtable) == RAC_SUCCESS, "manifest: register ok");
        const rac_engine_manifest_t* found = rac_engine_manifest_find("manifested");
        CHECK(found == &k_manifest, "manifest: find returns accepted manifest");
        CHECK(found != nullptr, "manifest: ownership and availability readable (non-null)");
        CHECK(found->availability == RAC_ENGINE_AVAILABILITY_PUBLIC,
              "manifest: ownership and availability readable (availability)");
        CHECK(std::strcmp(found->package_owner, "runanywhere-tests") == 0,
              "manifest: ownership and availability readable (owner)");
        CHECK(rac_plugin_unregister("manifested") == RAC_SUCCESS, "manifest: unregister ok");
        CHECK(rac_engine_manifest_find("manifested") == nullptr,
              "manifest: unregister removes manifest");
    }

    // (11) static registration — validate RAC_STATIC_PLUGIN_REGISTER expands
    //     to a no-op at compile time for C TUs (can only use in C++ TUs).
    //     Here we just re-verify rac_plugin_count reads back to 0 after all
    //     tests clean up.
    { CHECK(rac_plugin_count() == 0, "count: cleanly empty at end"); }

    std::fprintf(stdout, "\n%d checks, %d failed\n", test_count, test_failed);
    return test_failed == 0 ? 0 : 1;
}
