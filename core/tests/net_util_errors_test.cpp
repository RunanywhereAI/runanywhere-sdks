// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Tests for the new net + util + extended-errors modules.

#include <gtest/gtest.h>

#include <cstring>
#include <string>
#include <vector>

#include "ra_errors.h"
#include "environment.h"
#include "http_client.h"
#include "audio_utils.h"

using ra::core::net::AuthManager;
using ra::core::net::default_endpoints_for;
using ra::core::net::Environment;
using ra::core::net::HttpClient;
using ra::core::net::HttpMethod;
using ra::core::net::HttpRequest;
using ra::core::util::decode_wav_f32;
using ra::core::util::encode_wav_f32;
using ra::core::util::encode_wav_s16;

// -----------------------------------------------------------------------------
// Extended errors — every code maps to a non-empty descriptive string.
// -----------------------------------------------------------------------------
TEST(ExtendedErrors, EveryDefinedCodeHasDescriptiveString) {
    const ra_extended_error_t codes[] = {
        RA_EX_NOT_INITIALIZED, RA_EX_ALREADY_INITIALIZED,
        RA_EX_INITIALIZATION_FAILED, RA_EX_INVALID_CONFIGURATION,
        RA_EX_INVALID_API_KEY, RA_EX_CONFIGURATION_CONFLICT,
        RA_EX_MODEL_NOT_FOUND, RA_EX_MODEL_LOAD_FAILED,
        RA_EX_MODEL_CHECKSUM_MISMATCH, RA_EX_MODEL_CORRUPTED,
        RA_EX_GENERATION_FAILED, RA_EX_GENERATION_TIMEOUT,
        RA_EX_CONTEXT_TOO_LONG, RA_EX_NETWORK_UNAVAILABLE,
        RA_EX_NETWORK_ERROR, RA_EX_REQUEST_FAILED,
        RA_EX_CONNECTION_TIMEOUT, RA_EX_TLS_HANDSHAKE_FAILED,
        RA_EX_STORAGE_FULL, RA_EX_FILE_NOT_FOUND,
        RA_EX_HARDWARE_NOT_SUPPORTED, RA_EX_GPU_NOT_AVAILABLE,
        RA_EX_COMPONENT_NOT_READY, RA_EX_COMPONENT_BUSY,
        RA_EX_VALIDATION_FAILED, RA_EX_INVALID_PARAMETER,
        RA_EX_AUDIO_FORMAT_NOT_SUPPORTED, RA_EX_AUDIO_DEVICE_ERROR,
        RA_EX_LANGUAGE_NOT_SUPPORTED, RA_EX_VOICE_NOT_AVAILABLE,
        RA_EX_AUTHENTICATION_FAILED, RA_EX_AUTHORIZATION_FAILED,
        RA_EX_SECURITY_ERROR, RA_EX_ZIP_SLIP_DETECTED,
        RA_EX_EXTRACTION_FAILED, RA_EX_UNSUPPORTED_ARCHIVE_FORMAT,
        RA_EX_ARCHIVE_CORRUPTED, RA_EX_SERVICE_NOT_AVAILABLE,
        RA_EX_PLUGIN_NOT_LOADED, RA_EX_PLUGIN_ABI_MISMATCH,
        RA_EX_EVENT_DISPATCH_FAILED, RA_EX_EVENT_QUEUE_FULL,
    };
    for (auto code : codes) {
        const char* s = ra_extended_error_str(code);
        ASSERT_NE(s, nullptr);
        EXPECT_NE(std::string(s), "") << "empty string for code " << code;
        EXPECT_NE(std::string(s), "Unknown extended error")
            << "code " << code << " fell through to Unknown";
    }
}

TEST(ExtendedErrors, UnknownCodeReturnsUnknown) {
    EXPECT_STREQ(ra_extended_error_str(-99999), "Unknown extended error");
}

// -----------------------------------------------------------------------------
// AuthManager + environments
// -----------------------------------------------------------------------------
TEST(AuthManager, ProductionDefaultsUseApiRunanywhereAi) {
    const auto p = default_endpoints_for(Environment::kProd);
    EXPECT_NE(p.api_base_url.find("api.runanywhere.ai"), std::string::npos);
}

TEST(AuthManager, DevDefaultsPointAtLocalhost) {
    const auto d = default_endpoints_for(Environment::kDev);
    EXPECT_NE(d.api_base_url.find("localhost"), std::string::npos);
}

TEST(AuthManager, SetAndGetApiKey) {
    auto& a = AuthManager::global();
    a.set_api_key("test-key-xyz");
    EXPECT_TRUE(a.has_api_key());
    EXPECT_EQ(a.api_key(), "test-key-xyz");
    a.set_api_key("");
    EXPECT_FALSE(a.has_api_key());
}

TEST(AuthManager, SetEnvironmentResetsEndpoints) {
    auto& a = AuthManager::global();
    a.set_environment(Environment::kDev);
    EXPECT_EQ(a.environment(), Environment::kDev);
    EXPECT_NE(a.endpoints().api_base_url.find("localhost"), std::string::npos);
    a.set_environment(Environment::kProd);
    EXPECT_EQ(a.environment(), Environment::kProd);
    EXPECT_NE(a.endpoints().api_base_url.find("api.runanywhere.ai"),
              std::string::npos);
}

// -----------------------------------------------------------------------------
// HttpClient — default factory returns a working instance; we test only the
// structural paths since live HTTP would require a fixture server.
// -----------------------------------------------------------------------------
TEST(HttpClient, FactoryReturnsLiveInstance) {
    auto client = HttpClient::create();
    ASSERT_NE(client, nullptr);

    HttpRequest req;
    req.method = HttpMethod::kGet;
    req.url    = "http://127.0.0.1:1";  // should fail-fast (nothing listening)
    req.connect_s = 2;
    req.timeout_s = 3;

    auto rsp = client->send(req);
    // We expect a transport error (connection refused / timeout) — status
    // stays 0 and error_message is populated. The test just confirms the
    // plumbing reaches libcurl and returns a populated response.
    EXPECT_FALSE(rsp.error_message.empty());
    EXPECT_GE(rsp.elapsed_s, 0.0);
}

// -----------------------------------------------------------------------------
// Audio utilities — WAV round-trip
// -----------------------------------------------------------------------------
TEST(AudioUtils, EncodeDecodeF32RoundTrip) {
    constexpr int sr = 16000;
    std::vector<float> samples(sr);  // 1s of audio
    for (int i = 0; i < sr; ++i) {
        samples[i] = static_cast<float>((i % 200) - 100) / 100.f;
    }
    auto wav = encode_wav_f32(samples.data(), samples.size(), sr, 1);
    ASSERT_GT(wav.size(), 44u);

    int out_sr = 0, out_ch = 0;
    auto decoded = decode_wav_f32(wav.data(), wav.size(), &out_sr, &out_ch);
    EXPECT_EQ(out_sr, sr);
    EXPECT_EQ(out_ch, 1);
    ASSERT_EQ(decoded.size(), samples.size());

    // 16-bit quantization means tolerance ≈ 1 step = 1/32768 plus a
    // safety margin for rounding direction asymmetry. Observed worst
    // case on Apple Silicon is ~4e-5 which fits well inside 1/16384.
    for (std::size_t i = 0; i < samples.size(); ++i) {
        EXPECT_NEAR(decoded[i], samples[i], 1.f / 16384.f);
    }
}

TEST(AudioUtils, EncodeS16ProducesCorrectHeader) {
    std::vector<std::int16_t> s = {0, 16384, -16384, 32767, -32768};
    auto wav = encode_wav_s16(s.data(), s.size(), 44100, 2);
    ASSERT_GT(wav.size(), 44u);

    EXPECT_EQ(std::memcmp(wav.data(), "RIFF", 4), 0);
    EXPECT_EQ(std::memcmp(wav.data() + 8, "WAVE", 4), 0);
    EXPECT_EQ(std::memcmp(wav.data() + 12, "fmt ", 4), 0);

    // Sample rate at offset 24; channels at offset 22.
    const auto* sr_bytes = wav.data() + 24;
    const std::uint32_t sr_parsed =
        sr_bytes[0] | (sr_bytes[1] << 8) | (sr_bytes[2] << 16) | (sr_bytes[3] << 24);
    EXPECT_EQ(sr_parsed, 44100u);
    const auto* ch_bytes = wav.data() + 22;
    const std::uint16_t ch_parsed = ch_bytes[0] | (ch_bytes[1] << 8);
    EXPECT_EQ(ch_parsed, 2u);
}

TEST(AudioUtils, DecodeGarbageReturnsEmpty) {
    std::vector<std::uint8_t> garbage(100, 0xaa);
    int sr = 0, ch = 0;
    auto samples = decode_wav_f32(garbage.data(), garbage.size(), &sr, &ch);
    EXPECT_TRUE(samples.empty());
}

TEST(AudioUtils, EncodeHandlesEmptyInputGracefully) {
    auto wav = encode_wav_f32(nullptr, 0, 16000, 1);
    EXPECT_TRUE(wav.empty());
}
