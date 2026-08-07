/**
 * @file test_tts_config_defaults.cpp
 * @brief Parity tests for rac_tts_configuration_defaults_proto.
 *
 * TTSConfiguration was deleted from tts_options.proto entirely (it was
 * write-only: engine pinning already resolves off ModelLoadRequest, and
 * "which voice" is TTSOptions.model). rac_tts_configuration_defaults_proto
 * now populates the surviving TTSOptions message directly with the same
 * canonical defaults Swift's `RATTSConfiguration.defaults()` used to carry
 * (sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/TTS/
 * RATTSConfiguration+Helpers.swift), minus the two fields that no longer
 * exist: enable_neural_voice (was TTSConfiguration-only, no replacement) and
 * enable_ssml (reserved outright in TTSOptions -- no backend parses SSML).
 */

#include <cstdint>
#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef RAC_HAVE_PROTOBUF
#include "model_types.pb.h"
#include "tts_options.pb.h"
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

#define ASSERT_FLOAT_EQ(a, b)                                                                      \
    do {                                                                                           \
        if (!((a) == (b))) {                                                                       \
            std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d (got=%f expected=%f)\n", #a, #b, \
                         __FILE__, __LINE__, static_cast<double>(a), static_cast<double>(b));      \
            return 1;                                                                              \
        }                                                                                          \
    } while (0)

#ifdef RAC_HAVE_PROTOBUF

// Verifies the returned proto bytes parse to the canonical TTSOptions
// defaults rac_tts_configuration_defaults_proto populates directly (see
// rac_tts_config_defaults.cpp):
//   voice          = "default"
//   language_code  = "en-US"
//   speed          = 1.0
//   pitch          = 1.0
//   volume         = 1.0
//   audio_format   = AUDIO_FORMAT_PCM
//   sample_rate    = 0   (0 = "native rate" -- naming a rate forces a resample)
int test_tts_configuration_defaults_match_swift() {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);

    rac_result_t rc = rac_tts_configuration_defaults_proto(&buffer);
    ASSERT_EQ(rc, RAC_SUCCESS);
    ASSERT_EQ(buffer.status, RAC_SUCCESS);

    runanywhere::v1::TTSOptions opts;
    ASSERT_TRUE(opts.ParseFromArray(buffer.data, static_cast<int>(buffer.size)));

    ASSERT_EQ(opts.voice(), std::string("default"));
    ASSERT_EQ(opts.language_code(), std::string("en-US"));
    ASSERT_FLOAT_EQ(opts.speed(), 1.0f);
    ASSERT_FLOAT_EQ(opts.pitch(), 1.0f);
    ASSERT_FLOAT_EQ(opts.volume(), 1.0f);
    ASSERT_EQ(opts.audio_format(), runanywhere::v1::AUDIO_FORMAT_PCM);
    ASSERT_EQ(opts.sample_rate(), 0);

    rac_proto_buffer_free(&buffer);
    return 0;
}

int test_tts_configuration_defaults_null_out() {
    rac_result_t rc = rac_tts_configuration_defaults_proto(nullptr);
    ASSERT_EQ(rc, RAC_ERROR_NULL_POINTER);
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main(int /*argc*/, char** /*argv*/) {
#ifndef RAC_HAVE_PROTOBUF
    std::printf("SKIP: RAC_HAVE_PROTOBUF not defined; TTS config defaults tests skipped.\n");
    return 0;
#else
    struct TestCase {
        const char* name;
        int (*fn)();
    };
    static const TestCase kTests[] = {
        {"tts_configuration_defaults_match_swift", test_tts_configuration_defaults_match_swift},
        {"tts_configuration_defaults_null_out", test_tts_configuration_defaults_null_out},
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
