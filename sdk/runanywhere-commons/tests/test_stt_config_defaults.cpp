/**
 * @file test_stt_config_defaults.cpp
 * @brief Parity tests for rac_stt_configuration_defaults_proto.
 *
 * Verifies the canonical STTConfiguration defaults emitted by commons match
 * Swift's `RASTTConfiguration.defaults()`
 * (sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/STT/
 * RASTTConfiguration+Helpers.swift). When the Swift extension is slimmed in
 * P3, every SDK will call into this ABI for default-population so a single
 * source of truth governs the values.
 */

#include <cstdint>
#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef RAC_HAVE_PROTOBUF
#include "stt_options.pb.h"
#endif

namespace {

#define ASSERT_TRUE(cond)                                                                   \
    do {                                                                                    \
        if (!(cond)) {                                                                      \
            std::fprintf(stderr, "ASSERT FAILED: %s @ %s:%d\n", #cond, __FILE__, __LINE__); \
            return 1;                                                                       \
        }                                                                                   \
    } while (0)

#define ASSERT_EQ(a, b)                                                                            \
    do {                                                                                           \
        if (!((a) == (b))) {                                                                       \
            std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d\n", #a, #b, __FILE__, __LINE__); \
            return 1;                                                                              \
        }                                                                                          \
    } while (0)

#ifdef RAC_HAVE_PROTOBUF

// Verifies the returned proto bytes parse to the canonical default values
// from Swift's RASTTConfiguration.defaults():
//   model_id      = ""
//   language      = STT_LANGUAGE_EN
//   sample_rate   = 16000
//   enable_vad    = false
int test_stt_configuration_defaults_match_swift() {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);

    rac_result_t rc = rac_stt_configuration_defaults_proto(&buffer);
    ASSERT_EQ(rc, RAC_SUCCESS);
    ASSERT_EQ(buffer.status, RAC_SUCCESS);

    runanywhere::v1::STTConfiguration cfg;
    ASSERT_TRUE(cfg.ParseFromArray(buffer.data, static_cast<int>(buffer.size)));

    ASSERT_EQ(cfg.model_id(), std::string(""));
    ASSERT_EQ(cfg.language(), runanywhere::v1::STT_LANGUAGE_EN);
    ASSERT_EQ(cfg.sample_rate(), 16000);
    ASSERT_EQ(cfg.enable_vad(), false);

    rac_proto_buffer_free(&buffer);
    return 0;
}

int test_stt_configuration_defaults_null_out() {
    rac_result_t rc = rac_stt_configuration_defaults_proto(nullptr);
    ASSERT_EQ(rc, RAC_ERROR_NULL_POINTER);
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main(int /*argc*/, char** /*argv*/) {
#ifndef RAC_HAVE_PROTOBUF
    std::printf("SKIP: RAC_HAVE_PROTOBUF not defined; STT config defaults tests skipped.\n");
    return 0;
#else
    struct TestCase {
        const char* name;
        int (*fn)();
    };
    static const TestCase kTests[] = {
        {"stt_configuration_defaults_match_swift", test_stt_configuration_defaults_match_swift},
        {"stt_configuration_defaults_null_out", test_stt_configuration_defaults_null_out},
    };

    int failures = 0;
    for (const auto& t : kTests) {
        std::printf("RUN  %s\n", t.name);
        int rc = t.fn();
        if (rc != 0) {
            std::printf("FAIL %s\n", t.name);
            failures++;
        } else {
            std::printf("PASS %s\n", t.name);
        }
    }

    if (failures > 0) {
        std::fprintf(stderr, "\n%d test(s) failed.\n", failures);
        return 1;
    }
    std::printf("\nAll %zu test(s) passed.\n", sizeof(kTests) / sizeof(kTests[0]));
    return 0;
#endif
}
